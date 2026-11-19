import Foundation

public struct GitHubReleaseAsset: Codable, Equatable, Hashable, Sendable {
    public let name: String
    public let browserDownloadURL: URL
    public let size: Int64
    public let contentType: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
        case contentType = "content_type"
    }

    public init(name: String, browserDownloadURL: URL, size: Int64, contentType: String? = nil) {
        self.name = name
        self.browserDownloadURL = browserDownloadURL
        self.size = size
        self.contentType = contentType
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

public struct GitHubRelease: Codable, Equatable, Hashable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: URL
    public let publishedAt: Date?
    public let isDraft: Bool
    public let isPrerelease: Bool
    public let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case isDraft = "draft"
        case isPrerelease = "prerelease"
        case assets
    }

    public init(
        tagName: String,
        name: String? = nil,
        body: String? = nil,
        htmlURL: URL,
        publishedAt: Date? = nil,
        isDraft: Bool = false,
        isPrerelease: Bool = false,
        assets: [GitHubReleaseAsset] = []
    ) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.htmlURL = htmlURL
        self.publishedAt = publishedAt
        self.isDraft = isDraft
        self.isPrerelease = isPrerelease
        self.assets = assets
    }

    public var semanticVersion: SemanticVersion? {
        SemanticVersion(parsing: tagName)
    }

    public var displayTitle: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return "Tessera \(tagName)"
    }

    /// Picks the best macOS native app download artifact (prefers `.dmg` matching universal/arch, then `.zip`).
    public func preferredMacAsset(architecture: String = GitHubRelease.currentArchitecture) -> GitHubReleaseAsset? {
        let lowerArch = architecture.lowercased()
        let candidates = assets.filter { asset in
            let lower = asset.name.lowercased()
            return lower.hasSuffix(".dmg") || lower.hasSuffix(".zip")
        }
        guard !candidates.isEmpty else { return nil }

        func score(_ asset: GitHubReleaseAsset) -> Int {
            let lower = asset.name.lowercased()
            var points = 0
            if lower.hasSuffix(".dmg") { points += 100 }
            else if lower.hasSuffix(".zip") { points += 60 }

            if lower.contains("tessera") && !lower.contains("cli") { points += 40 }
            if lower.contains("universal") { points += 30 }
            else if lower.contains(lowerArch) { points += 25 }
            else if (lowerArch == "arm64" && lower.contains("x86_64"))
                 || (lowerArch == "x86_64" && lower.contains("arm64")) {
                points -= 40
            }
            return points
        }

        return candidates.max(by: { score($0) < score($1) })
    }

    public var checksumAsset: GitHubReleaseAsset? {
        assets.first { asset in
            let lower = asset.name.lowercased()
            return lower == "sha256sums.txt" || lower.contains("sha256") || lower.hasSuffix(".sha256")
        }
    }

    public static var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "universal"
        #endif
    }
}

/// Parses standard `shasum -a 256` output (`<hex>  <filename>`) into a filename -> lowercase hex map.
public enum SHA256SumsParser {
    public static func parse(_ content: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard parts.count == 2 else { continue }
            let hash = String(parts[0]).lowercased()
            guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else { continue }
            var filename = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if filename.hasPrefix("*") {
                filename.removeFirst()
            }
            let basename = (filename as NSString).lastPathComponent
            result[filename] = hash
            result[basename] = hash
        }
        return result
    }
}
