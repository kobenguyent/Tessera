import CryptoKit
import Foundation
import Testing
@testable import TesseraCore

private final class MockHTTPClient: HTTPFetching, @unchecked Sendable {
    var fetchHandler: (@Sendable (URLRequest) async throws -> HTTPResponseData)?
    var downloadData: Data = Data("mock-dmg-bytes".utf8)

    func fetch(_ request: URLRequest) async throws -> HTTPResponseData {
        guard let fetchHandler else {
            return HTTPResponseData(data: Data(), statusCode: 404)
        }
        return try await fetchHandler(request)
    }

    func download(
        from url: URL,
        to destination: URL,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        progress?(0.5)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try downloadData.write(to: destination, options: .atomic)
        progress?(1.0)
        return destination
    }
}

@Suite("GitHub Releases Auto-Update Service")
struct UpdateServiceTests {
    private let sampleReleasesJSON = """
    [
      {
        "tag_name": "v2.0.0-draft",
        "name": "Draft Release",
        "draft": true,
        "prerelease": false,
        "html_url": "https://github.com/kobenguyent/Tessera/releases/tag/v2.0.0-draft",
        "assets": []
      },
      {
        "tag_name": "v1.3.0-beta.1",
        "name": "Tessera 1.3 Beta",
        "draft": false,
        "prerelease": true,
        "html_url": "https://github.com/kobenguyent/Tessera/releases/tag/v1.3.0-beta.1",
        "assets": [
          {
            "name": "Tessera-1.3.0-beta.1-macOS-universal.dmg",
            "browser_download_url": "https://github.com/kobenguyent/Tessera/releases/download/v1.3.0-beta.1/Tessera-1.3.0-beta.1-macOS-universal.dmg",
            "size": 8400000
          }
        ]
      },
      {
        "tag_name": "v1.2.0",
        "name": "Tessera v1.2.0",
        "body": "### Highlights\\n- Added Ghostty support\\n- Faster mosaic editor",
        "draft": false,
        "prerelease": false,
        "published_at": "2026-11-18T10:00:00Z",
        "html_url": "https://github.com/kobenguyent/Tessera/releases/tag/v1.2.0",
        "assets": [
          {
            "name": "tessera-cli-1.2.0-macOS.tar.gz",
            "browser_download_url": "https://github.com/kobenguyent/Tessera/releases/download/v1.2.0/tessera-cli-1.2.0-macOS.tar.gz",
            "size": 1200000
          },
          {
            "name": "Tessera-1.2.0-macOS-universal.zip",
            "browser_download_url": "https://github.com/kobenguyent/Tessera/releases/download/v1.2.0/Tessera-1.2.0-macOS-universal.zip",
            "size": 7900000
          },
          {
            "name": "Tessera-1.2.0-macOS-universal.dmg",
            "browser_download_url": "https://github.com/kobenguyent/Tessera/releases/download/v1.2.0/Tessera-1.2.0-macOS-universal.dmg",
            "size": 8100000
          },
          {
            "name": "SHA256SUMS.txt",
            "browser_download_url": "https://github.com/kobenguyent/Tessera/releases/download/v1.2.0/SHA256SUMS.txt",
            "size": 256
          }
        ]
      }
    ]
    """

    @Test("Finds newer stable release, ignores drafts/prereleases, and prefers universal DMG")
    func findsNewerStableReleaseAndPrefersUniversalDMG() async throws {
        let client = MockHTTPClient()
        let jsonData = Data(sampleReleasesJSON.utf8)
        client.fetchHandler = { request in
            #expect(request.url?.absoluteString == "https://api.github.com/repos/kobenguyent/Tessera/releases?per_page=15")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
            return HTTPResponseData(data: jsonData, statusCode: 200)
        }

        let service = UpdateService(client: client, architecture: "arm64")
        let outcome = try await service.checkForUpdates(
            repository: "kobenguyent/Tessera",
            currentVersion: SemanticVersion(major: 1, minor: 0, patch: 0),
            includePrereleases: false
        )

        guard case .updateAvailable(let update) = outcome else {
            Issue.record("Expected .updateAvailable, got \(outcome)")
            return
        }
        #expect(update.version == SemanticVersion(major: 1, minor: 2, patch: 0))
        #expect(update.preferredAsset?.name == "Tessera-1.2.0-macOS-universal.dmg")
        #expect(update.release.checksumAsset?.name == "SHA256SUMS.txt")
    }

    @Test("Opting into pre-releases selects beta release")
    func includePrereleasesSelectsBetaVersion() async throws {
        let client = MockHTTPClient()
        let jsonData = Data(sampleReleasesJSON.utf8)
        client.fetchHandler = { _ in HTTPResponseData(data: jsonData, statusCode: 200) }

        let service = UpdateService(client: client)
        let outcome = try await service.checkForUpdates(
            repository: "kobenguyent/Tessera",
            currentVersion: SemanticVersion(major: 1, minor: 2, patch: 0),
            includePrereleases: true
        )

        guard case .updateAvailable(let update) = outcome else {
            Issue.record("Expected prerelease update, got \(outcome)")
            return
        }
        #expect(update.version.description == "1.3.0-beta.1")
    }

    @Test("Reports up-to-date when current version matches latest stable release")
    func reportsUpToDateWhenCurrentMatchesLatest() async throws {
        let client = MockHTTPClient()
        let jsonData = Data(sampleReleasesJSON.utf8)
        client.fetchHandler = { _ in HTTPResponseData(data: jsonData, statusCode: 200) }

        let service = UpdateService(client: client)
        let outcome = try await service.checkForUpdates(
            repository: "kobenguyent/Tessera",
            currentVersion: SemanticVersion(major: 1, minor: 2, patch: 0)
        )

        guard case .upToDate(let current, let latest) = outcome else {
            Issue.record("Expected .upToDate, got \(outcome)")
            return
        }
        #expect(current == SemanticVersion(major: 1, minor: 2, patch: 0))
        #expect(latest == SemanticVersion(major: 1, minor: 2, patch: 0))
    }

    @Test("Respects skipped version unless ignoreSkipped is requested")
    func respectsSkippedVersionUnlessIgnored() async throws {
        let client = MockHTTPClient()
        let jsonData = Data(sampleReleasesJSON.utf8)
        client.fetchHandler = { _ in HTTPResponseData(data: jsonData, statusCode: 200) }
        let service = UpdateService(client: client)

        let skippedOutcome = try await service.checkForUpdates(
            repository: "kobenguyent/Tessera",
            currentVersion: SemanticVersion(major: 1, minor: 0, patch: 0),
            skippedVersion: "1.2.0",
            ignoreSkipped: false
        )
        guard case .skipped(let skipped) = skippedOutcome else {
            Issue.record("Expected .skipped")
            return
        }
        #expect(skipped.version == SemanticVersion(major: 1, minor: 2, patch: 0))

        let forcedOutcome = try await service.checkForUpdates(
            repository: "kobenguyent/Tessera",
            currentVersion: SemanticVersion(major: 1, minor: 0, patch: 0),
            skippedVersion: "1.2.0",
            ignoreSkipped: true
        )
        guard case .updateAvailable = forcedOutcome else {
            Issue.record("Expected .updateAvailable when ignoreSkipped is true")
            return
        }
    }

    @Test("Handles GitHub API rate limits and invalid repository strings cleanly")
    func handlesRateLimitAndInvalidRepository() async {
        let client = MockHTTPClient()
        client.fetchHandler = { _ in
            HTTPResponseData(data: Data(), statusCode: 403, headers: ["x-ratelimit-remaining": "0"])
        }
        let service = UpdateService(client: client)

        await #expect(throws: UpdateError.rateLimited(resetHint: nil)) {
            _ = try await service.checkForUpdates(repository: "kobenguyent/Tessera")
        }

        await #expect(throws: UpdateError.invalidRepository("not-a-valid-repo")) {
            _ = try await service.checkForUpdates(repository: "not-a-valid-repo")
        }
    }

    @Test("Downloads asset, verifies SHA256SUMS.txt, and rejects tampered payloads")
    func downloadVerifiesSHA256AndRejectsTamperedFiles() async throws {
        let payload = Data("tessera-native-dmg-payload".utf8)
        let validHash = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let checksumFile = "\(validHash)  Tessera-1.2.0-macOS-universal.dmg\n"

        let client = MockHTTPClient()
        client.downloadData = payload
        let releasesData = Data(sampleReleasesJSON.utf8)
        client.fetchHandler = { request in
            if request.url?.lastPathComponent == "SHA256SUMS.txt" {
                return HTTPResponseData(data: Data(checksumFile.utf8), statusCode: 200)
            }
            return HTTPResponseData(data: releasesData, statusCode: 200)
        }

        let service = UpdateService(client: client)
        let outcome = try await service.checkForUpdates(
            repository: "kobenguyent/Tessera",
            currentVersion: SemanticVersion(major: 1, minor: 0, patch: 0)
        )
        guard case .updateAvailable(let update) = outcome else {
            Issue.record("Expected update")
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tessera-update-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let downloaded = try await service.downloadUpdate(update, destinationDirectory: tempDir)
        #expect(downloaded.checksumVerified)
        #expect(downloaded.sha256Hex == validHash)
        #expect(FileManager.default.fileExists(atPath: downloaded.fileURL.path))

        // Tamper with payload and confirm checksumMismatch is thrown and corrupted artifact is removed
        client.downloadData = Data("tampered-bytes".utf8)
        do {
            _ = try await service.downloadUpdate(update, destinationDirectory: tempDir)
            Issue.record("Expected checksumMismatch error")
        } catch let err as UpdateError {
            guard case .checksumMismatch = err else {
                Issue.record("Expected checksumMismatch, got \(err)")
                return
            }
            #expect(!FileManager.default.fileExists(atPath: downloaded.fileURL.path))
        }
    }
}
