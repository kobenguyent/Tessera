import Foundation
import Testing
@testable import TesseraCore

@Suite("SemanticVersion")
struct SemanticVersionTests {
    @Test("Parses standard, short, v-prefixed, prerelease, and build metadata versions")
    func parsingValidVersions() throws {
        let v1 = try #require(SemanticVersion(parsing: "v1.2.3"))
        #expect(v1.major == 1)
        #expect(v1.minor == 2)
        #expect(v1.patch == 3)
        #expect(v1.description == "1.2.3")
        #expect(v1.tagString == "v1.2.3")

        let v2 = try #require(SemanticVersion(parsing: "2.4"))
        #expect(v2 == SemanticVersion(major: 2, minor: 4, patch: 0))

        let pre = try #require(SemanticVersion(parsing: "v1.5.0-beta.2+20261119"))
        #expect(pre.isPrerelease)
        #expect(pre.prerelease == ["beta", "2"])
        #expect(pre.buildMetadata == ["20261119"])
    }

    @Test("Rejects invalid version strings")
    func rejectsInvalidVersions() {
        #expect(SemanticVersion(parsing: "") == nil)
        #expect(SemanticVersion(parsing: "latest") == nil)
        #expect(SemanticVersion(parsing: "v1") == nil)
        #expect(SemanticVersion(parsing: "1.2.3.4") == nil)
        #expect(SemanticVersion(parsing: "1.2.3-") == nil)
        #expect(SemanticVersion(parsing: "1.2.3+") == nil)
    }

    @Test("Maintains strict SemVer 2.0 precedence ordering")
    func semVerOrdering() {
        let ordered = [
            "0.9.0",
            "1.0.0-alpha",
            "1.0.0-alpha.1",
            "1.0.0-alpha.beta",
            "1.0.0-beta.2",
            "1.0.0-beta.11",
            "1.0.0-rc.1",
            "1.0.0",
            "1.0.1",
            "1.1.0",
            "2.0.0"
        ].compactMap { SemanticVersion(parsing: $0) }

        #expect(ordered.count == 11)
        for idx in 0..<(ordered.count - 1) {
            #expect(ordered[idx] < ordered[idx + 1])
        }
    }
}
