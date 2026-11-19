import Foundation

/// Full SemVer 2.0 parser and comparator supporting optional `v` prefix,
/// prerelease identifiers (e.g. `1.2.0-beta.1`), and build metadata (`+build.42`).
public struct SemanticVersion: Codable, Equatable, Hashable, Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: [String]
    public let buildMetadata: [String]

    public init(
        major: Int,
        minor: Int,
        patch: Int,
        prerelease: [String] = [],
        buildMetadata: [String] = []
    ) {
        self.major = max(0, major)
        self.minor = max(0, minor)
        self.patch = max(0, patch)
        self.prerelease = prerelease
        self.buildMetadata = buildMetadata
    }

    public init?(parsing raw: String) {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            trimmed.removeFirst()
        }
        guard !trimmed.isEmpty else { return nil }

        // Split optional +build metadata
        let buildParts = trimmed.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        let withoutBuild = String(buildParts[0])
        let buildTokens: [String]
        if buildParts.count == 2 {
            let meta = String(buildParts[1])
            guard !meta.isEmpty else { return nil }
            buildTokens = meta.split(separator: ".").map(String.init)
        } else {
            buildTokens = []
        }

        // Split optional -prerelease
        let preParts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let coreString = String(preParts[0])
        let preTokens: [String]
        if preParts.count == 2 {
            let preRaw = String(preParts[1])
            guard !preRaw.isEmpty else { return nil }
            preTokens = preRaw.split(separator: ".").map(String.init)
            if preTokens.contains(where: { $0.isEmpty }) { return nil }
        } else {
            preTokens = []
        }

        // Parse major.minor[.patch]
        let coreNumbers = coreString.split(separator: ".", omittingEmptySubsequences: false)
        guard coreNumbers.count >= 2 && coreNumbers.count <= 3 else { return nil }
        guard let major = Int(coreNumbers[0]), major >= 0,
              let minor = Int(coreNumbers[1]), minor >= 0 else {
            return nil
        }
        let patch: Int
        if coreNumbers.count == 3 {
            guard let parsedPatch = Int(coreNumbers[2]), parsedPatch >= 0 else { return nil }
            patch = parsedPatch
        } else {
            patch = 0
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = preTokens
        self.buildMetadata = buildTokens
    }

    public var isPrerelease: Bool {
        !prerelease.isEmpty
    }

    public var description: String {
        var base = "\(major).\(minor).\(patch)"
        if !prerelease.isEmpty {
            base += "-" + prerelease.joined(separator: ".")
        }
        if !buildMetadata.isEmpty {
            base += "+" + buildMetadata.joined(separator: ".")
        }
        return base
    }

    public var tagString: String {
        "v\(description)"
    }

    // SemVer 2.0 equality ignores build metadata for precedence, but Equatable compares core + prerelease.
    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.major == rhs.major
            && lhs.minor == rhs.minor
            && lhs.patch == rhs.patch
            && lhs.prerelease == rhs.prerelease
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(major)
        hasher.combine(minor)
        hasher.combine(patch)
        hasher.combine(prerelease)
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // A normal version has higher precedence than a pre-release version.
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true): return false
        case (true, false): return false
        case (false, true): return true
        case (false, false):
            let count = min(lhs.prerelease.count, rhs.prerelease.count)
            for idx in 0..<count {
                let left = lhs.prerelease[idx]
                let right = rhs.prerelease[idx]
                if left == right { continue }
                switch (Int(left), Int(right)) {
                case let (.some(lNum), .some(rNum)):
                    return lNum < rNum
                case (.some, .none):
                    // Numeric identifiers always have lower precedence than non-numeric identifiers
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return left < right
                }
            }
            return lhs.prerelease.count < rhs.prerelease.count
        }
    }
}
