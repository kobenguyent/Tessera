import CryptoKit
import Foundation

public struct HTTPResponseData: Sendable {
    public let data: Data
    public let statusCode: Int
    public let headers: [String: String]

    public init(data: Data, statusCode: Int, headers: [String: String] = [:]) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
    }
}

public protocol HTTPFetching: Sendable {
    func fetch(_ request: URLRequest) async throws -> HTTPResponseData
    func download(from url: URL, to destination: URL, progress: (@Sendable (Double) -> Void)?) async throws -> URL
}

private final class StreamingDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: (@Sendable (Double) -> Void)?
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var movedURL: URL?
    private var moveError: Error?

    init(
        destination: URL,
        progress: (@Sendable (Double) -> Void)?,
        continuation: CheckedContinuation<URL, Error>
    ) {
        self.destination = destination
        self.progress = progress
        self.continuation = continuation
    }

    private func finish(with result: Result<URL, Error>) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(with: result)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let ratio = min(1.0, max(0.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        progress?(ratio)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            moveError = UpdateError.httpStatus(http.statusCode, "Download failed")
            return
        }
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: location, to: destination)
            movedURL = destination
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { session.finishTasksAndInvalidate() }
        if let error {
            finish(with: .failure(error))
            return
        }
        if let moveError {
            finish(with: .failure(moveError))
            return
        }
        if let movedURL {
            progress?(1.0)
            finish(with: .success(movedURL))
            return
        }
        finish(with: .failure(UpdateError.invalidResponse))
    }
}

public final class URLSessionHTTPClient: HTTPFetching, @unchecked Sendable {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    public func fetch(_ request: URLRequest) async throws -> HTTPResponseData {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }
        var normalizedHeaders: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            normalizedHeaders[String(describing: k).lowercased()] = String(describing: v)
        }
        return HTTPResponseData(data: data, statusCode: http.statusCode, headers: normalizedHeaders)
    }

    public func download(
        from url: URL,
        to destination: URL,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = StreamingDownloadDelegate(
                destination: destination,
                progress: progress,
                continuation: continuation
            )
            let delegateSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let task = delegateSession.downloadTask(with: url)
            task.resume()
        }
    }
}

public enum UpdateError: LocalizedError, Equatable, Sendable {
    case invalidRepository(String)
    case invalidResponse
    case httpStatus(Int, String)
    case rateLimited(resetHint: String?)
    case noReleasesPublished
    case missingDownloadAsset
    case checksumMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .invalidRepository(let repo):
            return "Invalid GitHub repository \"\(repo)\". Use \"owner/repo\" format."
        case .invalidResponse:
            return "Received an unexpected response from GitHub."
        case .httpStatus(let code, let detail):
            return "GitHub returned HTTP \(code): \(detail)"
        case .rateLimited(let hint):
            if let hint {
                return "GitHub API rate limit reached (\(hint)). Try again shortly."
            }
            return "GitHub API rate limit reached. Try again later."
        case .noReleasesPublished:
            return "No GitHub releases have been published for this repository yet."
        case .missingDownloadAsset:
            return "This release does not include a downloadable macOS .dmg or .zip asset."
        case .checksumMismatch(let expected, let actual):
            return "SHA-256 verification failed! Expected \(expected.prefix(12))… but got \(actual.prefix(12))…"
        }
    }
}

public struct UpdateRelease: Equatable, Sendable {
    public let version: SemanticVersion
    public let release: GitHubRelease
    public let preferredAsset: GitHubReleaseAsset?

    public init(version: SemanticVersion, release: GitHubRelease, preferredAsset: GitHubReleaseAsset?) {
        self.version = version
        self.release = release
        self.preferredAsset = preferredAsset
    }
}

public enum UpdateCheckOutcome: Equatable, Sendable {
    case upToDate(currentVersion: SemanticVersion, latestVersion: SemanticVersion?)
    case updateAvailable(UpdateRelease)
    case skipped(UpdateRelease)
}

public struct DownloadedUpdate: Equatable, Sendable {
    public let fileURL: URL
    public let release: UpdateRelease
    public let sha256Hex: String
    public let checksumVerified: Bool

    public init(fileURL: URL, release: UpdateRelease, sha256Hex: String, checksumVerified: Bool) {
        self.fileURL = fileURL
        self.release = release
        self.sha256Hex = sha256Hex
        self.checksumVerified = checksumVerified
    }
}

public struct UpdateService: Sendable {
    private let client: HTTPFetching
    private let architecture: String

    public init(
        client: HTTPFetching = URLSessionHTTPClient(),
        architecture: String = GitHubRelease.currentArchitecture
    ) {
        self.client = client
        self.architecture = architecture
    }

    public func checkForUpdates(
        repository: String,
        currentVersion: SemanticVersion = TesseraMetadata.currentVersion,
        includePrereleases: Bool = false,
        skippedVersion: String? = nil,
        ignoreSkipped: Bool = false
    ) async throws -> UpdateCheckOutcome {
        let trimmedRepo = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TesseraMetadata.isValidGitHubRepository(trimmedRepo),
              let url = URL(string: "https://api.github.com/repos/\(trimmedRepo)/releases?per_page=15") else {
            throw UpdateError.invalidRepository(repository)
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Tessera/\(currentVersion.description)", forHTTPHeaderField: "User-Agent")

        let response = try await client.fetch(request)

        if response.statusCode == 403 || response.statusCode == 429 {
            if response.headers["x-ratelimit-remaining"] == "0" || response.statusCode == 429 {
                throw UpdateError.rateLimited(resetHint: response.headers["x-ratelimit-reset"])
            }
        }
        if response.statusCode == 404 {
            throw UpdateError.noReleasesPublished
        }
        guard (200...299).contains(response.statusCode) else {
            let detail = String(data: response.data, encoding: .utf8) ?? "Request failed"
            throw UpdateError.httpStatus(response.statusCode, String(detail.prefix(180)))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let releases = try decoder.decode([GitHubRelease].self, from: response.data)

        let eligible: [(SemanticVersion, GitHubRelease)] = releases.compactMap { release in
            guard !release.isDraft else { return nil }
            if !includePrereleases && release.isPrerelease { return nil }
            guard let version = release.semanticVersion else { return nil }
            if !includePrereleases && version.isPrerelease { return nil }
            return (version, release)
        }

        guard let best = eligible.max(by: { $0.0 < $1.0 }) else {
            return .upToDate(currentVersion: currentVersion, latestVersion: nil)
        }

        let (latestVersion, latestRelease) = best
        guard latestVersion > currentVersion else {
            return .upToDate(currentVersion: currentVersion, latestVersion: latestVersion)
        }

        let updateRelease = UpdateRelease(
            version: latestVersion,
            release: latestRelease,
            preferredAsset: latestRelease.preferredMacAsset(architecture: architecture)
        )

        if !ignoreSkipped,
           let skippedRaw = skippedVersion,
           let skippedSemVer = SemanticVersion(parsing: skippedRaw),
           skippedSemVer == latestVersion {
            return .skipped(updateRelease)
        }

        return .updateAvailable(updateRelease)
    }

    /// Downloads the preferred macOS `.dmg` or `.zip` asset and verifies its SHA-256 against `SHA256SUMS.txt` when present.
    public func downloadUpdate(
        _ update: UpdateRelease,
        destinationDirectory: URL? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> DownloadedUpdate {
        guard let asset = update.preferredAsset else {
            throw UpdateError.missingDownloadAsset
        }

        let targetDir = destinationDirectory
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let destinationURL = targetDir.appendingPathComponent(asset.name)

        let downloadedURL = try await client.download(
            from: asset.browserDownloadURL,
            to: destinationURL,
            progress: progress
        )

        let actualHash = try Self.sha256Hex(of: downloadedURL)
        var verified = false

        if let checksumAsset = update.release.checksumAsset {
            var req = URLRequest(url: checksumAsset.browserDownloadURL)
            req.setValue("Tessera/\(TesseraMetadata.currentVersionString)", forHTTPHeaderField: "User-Agent")
            if let checksumResponse = try? await client.fetch(req),
               (200...299).contains(checksumResponse.statusCode),
               let text = String(data: checksumResponse.data, encoding: .utf8) {
                let map = SHA256SumsParser.parse(text)
                if let expected = map[asset.name] {
                    guard expected.lowercased() == actualHash.lowercased() else {
                        try? FileManager.default.removeItem(at: downloadedURL)
                        throw UpdateError.checksumMismatch(expected: expected, actual: actualHash)
                    }
                    verified = true
                }
            }
        }

        return DownloadedUpdate(
            fileURL: downloadedURL,
            release: update,
            sha256Hex: actualHash,
            checksumVerified: verified
        )
    }

    public static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 65_536)
            guard !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
