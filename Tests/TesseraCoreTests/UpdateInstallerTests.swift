import Foundation
import Testing
@testable import TesseraCore

@Suite("Streamlined Self-Update Installer")
struct UpdateInstallerTests {
    @Test("Resolves install mode properly for .app bundle vs unpackaged binary and validates Zsh syntax")
    func installModeAndScriptSyntax() throws {
        let dmgURL = URL(fileURLWithPath: "/tmp/My Downloads/Tessera-1.2.0-macOS-universal.dmg")
        let appURL = URL(fileURLWithPath: "/Applications/Tessera.app")

        let replacePlan = UpdateInstallPlan(
            downloadedAssetURL: dmgURL,
            targetAppURL: appURL,
            processID: 999999,
            relaunchAfterInstall: true
        )
        #expect(replacePlan.mode == .replaceAndRelaunch(targetAppURL: appURL))

        let script = try UpdateInstaller.buildInstallScript(plan: replacePlan, selfScriptPath: "/tmp/self.sh")
        #expect(script.contains("hdiutil attach -nobrowse -readonly -mountpoint"))
        #expect(script.contains("open -n \"$TARGET_APP\""))

        let syntax = ScriptValidator.validateSync(script: script, language: "zsh")
        #expect(syntax.isValid, "Generated updater script failed zsh -n: \(syntax.message)")

        let devPlan = UpdateInstallPlan(
            downloadedAssetURL: dmgURL,
            targetAppURL: URL(fileURLWithPath: "/Users/dev/Tessera/.build/debug"),
            processID: 999999
        )
        #expect(devPlan.mode == .openArtifactAndQuit)
        let devScript = try UpdateInstaller.buildInstallScript(plan: devPlan)
        #expect(ScriptValidator.validateSync(script: devScript, language: "zsh").isValid)

        let badPlan = UpdateInstallPlan(
            downloadedAssetURL: URL(fileURLWithPath: "/tmp/Tessera.tar.gz"),
            targetAppURL: appURL
        )
        #expect(throws: UpdateInstallerError.self) {
            _ = try UpdateInstaller.buildInstallScript(plan: badPlan)
        }
    }

    @Test("Replaces existing Tessera.app atomically from a downloaded ZIP archive")
    func endToEndZipSelfUpdate() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("tessera-zip-update-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let installedApp = tempRoot.appendingPathComponent("Installed/Tessera.app", isDirectory: true)
        let newApp = tempRoot.appendingPathComponent("Staging/Tessera.app", isDirectory: true)
        try createMockApp(at: installedApp, version: "1.0.0")
        try createMockApp(at: newApp, version: "1.2.0")

        let zipURL = tempRoot.appendingPathComponent("Tessera-1.2.0-macOS-universal.zip")
        try runChecked("/usr/bin/ditto", ["-c", "-k", "--keepParent", newApp.path, zipURL.path])

        let scriptURL = tempRoot.appendingPathComponent("run-update.sh")
        let plan = UpdateInstallPlan(
            downloadedAssetURL: zipURL,
            targetAppURL: installedApp,
            processID: 999_999, // Already exited PID so script proceeds immediately
            relaunchAfterInstall: false
        )
        let script = try UpdateInstaller.buildInstallScript(plan: plan, selfScriptPath: scriptURL.path)
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        try runChecked("/bin/zsh", [scriptURL.path])

        let marker = try String(
            contentsOf: installedApp.appendingPathComponent("Contents/version.txt"),
            encoding: .utf8
        )
        #expect(marker == "1.2.0")
        #expect(!fm.fileExists(atPath: scriptURL.path))
    }

    @Test("Mounts DMG, replaces existing Tessera.app atomically, and detaches cleanly")
    func endToEndDmgSelfUpdate() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("tessera-dmg-update-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let installedApp = tempRoot.appendingPathComponent("Installed/Tessera.app", isDirectory: true)
        let dmgSourceDir = tempRoot.appendingPathComponent("DMGSource", isDirectory: true)
        let newApp = dmgSourceDir.appendingPathComponent("Tessera.app", isDirectory: true)
        try createMockApp(at: installedApp, version: "1.0.0")
        try createMockApp(at: newApp, version: "1.3.0")

        let dmgURL = tempRoot.appendingPathComponent("Tessera-1.3.0-macOS-universal.dmg")
        try runChecked("/usr/bin/hdiutil", [
            "create",
            "-volname", "Tessera 1.3.0",
            "-srcfolder", dmgSourceDir.path,
            "-ov",
            "-format", "UDZO",
            dmgURL.path
        ])

        let scriptURL = tempRoot.appendingPathComponent("run-dmg-update.sh")
        let plan = UpdateInstallPlan(
            downloadedAssetURL: dmgURL,
            targetAppURL: installedApp,
            processID: 999_999,
            relaunchAfterInstall: false
        )
        let script = try UpdateInstaller.buildInstallScript(plan: plan, selfScriptPath: scriptURL.path)
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        try runChecked("/bin/zsh", [scriptURL.path])

        let marker = try String(
            contentsOf: installedApp.appendingPathComponent("Contents/version.txt"),
            encoding: .utf8
        )
        #expect(marker == "1.3.0")
        #expect(!fm.fileExists(atPath: scriptURL.path))
    }

    private func createMockApp(at url: URL, version: String) throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try version.write(to: contents.appendingPathComponent("version.txt"), atomically: true, encoding: .utf8)
    }

    private func runChecked(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            Issue.record("\(executable) failed (\(process.terminationStatus)): \(err)")
            throw UpdateInstallerError.failedToLaunchHelper(err)
        }
    }
}
