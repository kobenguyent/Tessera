import Foundation

public enum TesseraMetadata {
    public static let appName = "Tessera"
    public static let tagline = "Craft bespoke terminal mosaics & command rituals"
    public static let bundleIdentifier = "com.kobenguyent.Tessera"
    public static let defaultVersion = "1.0.0"
    public static let defaultGitHubRepository = "kobenguyent/Tessera"

    private static var enclosingAppBundle: Bundle? {
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") != nil {
            return Bundle.main
        }
        // When invoked as `Tessera.app/Contents/Helpers/tessera`, resolve the parent `.app` bundle
        guard let execURL = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
        var candidate = execURL.deletingLastPathComponent()
        for _ in 0..<4 {
            if candidate.pathExtension == "app", let bundle = Bundle(url: candidate) {
                return bundle
            }
            candidate.deleteLastPathComponent()
        }
        return nil
    }

    public static var currentVersionString: String {
        if let bundleVersion = enclosingAppBundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !bundleVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return bundleVersion
        }
        return defaultVersion
    }

    public static var currentVersion: SemanticVersion {
        SemanticVersion(parsing: currentVersionString) ?? SemanticVersion(major: 1, minor: 0, patch: 0)
    }

    public static var bundledGitHubRepository: String {
        if let envRepo = ProcessInfo.processInfo.environment["TESSERA_GITHUB_REPO"],
           isValidGitHubRepository(envRepo) {
            return envRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let plistRepo = enclosingAppBundle?.object(forInfoDictionaryKey: "TesseraGitHubRepo") as? String,
           isValidGitHubRepository(plistRepo) {
            return plistRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return defaultGitHubRepository
    }

    public static func isValidGitHubRepository(_ repo: String) -> Bool {
        let trimmed = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/")
        guard parts.count == 2 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }
}
