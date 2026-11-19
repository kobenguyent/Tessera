import Foundation

public enum UpdateInstallMode: Equatable, Sendable {
    case replaceAndRelaunch(targetAppURL: URL)
    case openArtifactAndQuit
}

public struct UpdateInstallPlan: Equatable, Sendable {
    public let downloadedAssetURL: URL
    public let mode: UpdateInstallMode
    public let processID: Int32
    public let relaunchAfterInstall: Bool

    public init(
        downloadedAssetURL: URL,
        targetAppURL: URL? = UpdateInstaller.currentAppBundleURL(),
        processID: Int32 = ProcessInfo.processInfo.processIdentifier,
        relaunchAfterInstall: Bool = true
    ) {
        self.downloadedAssetURL = downloadedAssetURL
        if let targetAppURL, targetAppURL.pathExtension.lowercased() == "app" {
            self.mode = .replaceAndRelaunch(targetAppURL: targetAppURL)
        } else {
            self.mode = .openArtifactAndQuit
        }
        self.processID = processID
        self.relaunchAfterInstall = relaunchAfterInstall
    }
}

public enum UpdateInstallerError: LocalizedError, Sendable {
    case assetNotFound(String)
    case unsupportedArchive(String)
    case failedToLaunchHelper(String)

    public var errorDescription: String? {
        switch self {
        case .assetNotFound(let path):
            return "Downloaded update file was not found at \(path)."
        case .unsupportedArchive(let name):
            return "Unsupported update package format: \(name). Expected .dmg or .zip."
        case .failedToLaunchHelper(let reason):
            return "Could not start the update installer helper: \(reason)"
        }
    }
}

/// Orchestrates streamlined macOS self-updates:
/// waits for the current app process to close, extracts the `.dmg` or `.zip`,
/// atomically replaces `Tessera.app` (with rollback safety), and relaunches the new version.
public enum UpdateInstaller {
    public static func currentAppBundleURL() -> URL? {
        let bundleURL = Bundle.main.bundleURL
        return bundleURL.pathExtension.lowercased() == "app" ? bundleURL : nil
    }

    /// Generates a self-contained `/bin/zsh` script that performs the update after the running app closes.
    public static func buildInstallScript(
        plan: UpdateInstallPlan,
        selfScriptPath: String? = nil
    ) throws -> String {
        let assetPath = plan.downloadedAssetURL.path
        let ext = plan.downloadedAssetURL.pathExtension.lowercased()
        guard ext == "dmg" || ext == "zip" else {
            throw UpdateInstallerError.unsupportedArchive(plan.downloadedAssetURL.lastPathComponent)
        }

        let quotedAsset = CommandFormatter.shellSingleQuote(assetPath)
        let cleanupSelfLine: String
        if let selfScriptPath {
            cleanupSelfLine = "  rm -f \(CommandFormatter.shellSingleQuote(selfScriptPath)) 2>/dev/null || true"
        } else {
            cleanupSelfLine = ""
        }

        switch plan.mode {
        case .openArtifactAndQuit:
            return """
            #!/bin/zsh
            set -euo pipefail
            APP_PID=\(plan.processID)
            ASSET=\(quotedAsset)

            cleanup() {
            \(cleanupSelfLine)
              true
            }
            trap cleanup EXIT

            # Wait briefly for the current process to exit cleanly
            for _ in {1..100}; do
              if ! kill -0 "$APP_PID" 2>/dev/null; then
                break
              fi
              sleep 0.1
            done

            open "$ASSET"
            """

        case .replaceAndRelaunch(let targetAppURL):
            let quotedTarget = CommandFormatter.shellSingleQuote(targetAppURL.path)
            let extractBlock: String
            if ext == "dmg" {
                extractBlock = """
                MOUNT_DIR="$WORK_DIR/mount"
                mkdir -p "$MOUNT_DIR"
                hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_DIR" "$ASSET" >/dev/null
                MOUNTED=1
                SRC_APP="$(find "$MOUNT_DIR" -maxdepth 2 -name '*.app' -print -quit)"
                if [[ -z "$SRC_APP" || ! -d "$SRC_APP" ]]; then
                  echo "No .app bundle found inside DMG" >&2
                  exit 1
                fi
                ditto "$SRC_APP" "$STAGED_APP"
                hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach "$MOUNT_DIR" -force -quiet || true
                MOUNTED=0
                """
            } else {
                extractBlock = """
                EXTRACT_DIR="$WORK_DIR/extract"
                mkdir -p "$EXTRACT_DIR"
                ditto -x -k "$ASSET" "$EXTRACT_DIR"
                SRC_APP="$(find "$EXTRACT_DIR" -maxdepth 2 -name '*.app' -print -quit)"
                if [[ -z "$SRC_APP" || ! -d "$SRC_APP" ]]; then
                  echo "No .app bundle found inside ZIP" >&2
                  exit 1
                fi
                mv "$SRC_APP" "$STAGED_APP"
                """
            }

            let relaunchBlock = plan.relaunchAfterInstall
                ? """
                sleep 0.2
                open -n "$TARGET_APP" || open "$TARGET_APP"
                """
                : "# Relaunch disabled for automated testing"

            return """
            #!/bin/zsh
            set -euo pipefail

            APP_PID=\(plan.processID)
            ASSET=\(quotedAsset)
            TARGET_APP=\(quotedTarget)
            PARENT_DIR="$(dirname "$TARGET_APP")"
            WORK_DIR="$(mktemp -d /tmp/tessera-updater.XXXXXX)"
            STAGED_APP="$WORK_DIR/Tessera.app"
            BACKUP_APP="$WORK_DIR/Tessera-previous.app"
            MOUNT_DIR=""
            MOUNTED=0

            cleanup() {
              if [[ "$MOUNTED" -eq 1 && -n "$MOUNT_DIR" ]]; then
                hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach "$MOUNT_DIR" -force -quiet || true
              fi
              rm -rf "$WORK_DIR" 2>/dev/null || true
            \(cleanupSelfLine)
            }
            trap cleanup EXIT

            # 1. Wait for current Tessera instance to exit completely (up to 20s)
            for _ in {1..200}; do
              if ! kill -0 "$APP_PID" 2>/dev/null; then
                break
              fi
              sleep 0.1
            done

            # 2. Extract updated Tessera.app from downloaded archive
            \(extractBlock)

            # Remove quarantine attribute so the newly installed app launches smoothly
            xattr -dr com.apple.quarantine "$STAGED_APP" 2>/dev/null || true

            # 3. Atomically swap the new app into place (with rollback on error)
            if [[ -w "$PARENT_DIR" ]] && [[ ! -e "$TARGET_APP" || -w "$TARGET_APP" ]]; then
              if [[ -e "$TARGET_APP" ]]; then
                mv "$TARGET_APP" "$BACKUP_APP"
              fi
              if ! mv "$STAGED_APP" "$TARGET_APP"; then
                if [[ -e "$BACKUP_APP" ]]; then
                  mv "$BACKUP_APP" "$TARGET_APP" 2>/dev/null || true
                fi
                open "$ASSET" 2>/dev/null || true
                exit 1
              fi
              rm -rf "$BACKUP_APP" 2>/dev/null || true
            else
              # Fallback to native macOS administrator elevation when installing into root-owned /Applications
              if ! osascript - "$STAGED_APP" "$TARGET_APP" <<'APPLESCRIPT'
            on run argv
              set stagedApp to quoted form of (item 1 of argv)
              set targetApp to quoted form of (item 2 of argv)
              do shell script "rm -rf " & targetApp & " && mv " & stagedApp & " " & targetApp with administrator privileges
            end run
            APPLESCRIPT
              then
                open "$ASSET" 2>/dev/null || true
                exit 1
              fi
            fi

            # 4. Relaunch updated Tessera.app
            \(relaunchBlock)
            """
        }
    }

    /// Writes and spawns the detached background updater script so it survives app termination.
    public static func launchDetachedInstaller(plan: UpdateInstallPlan) throws {
        guard FileManager.default.fileExists(atPath: plan.downloadedAssetURL.path) else {
            throw UpdateInstallerError.assetNotFound(plan.downloadedAssetURL.path)
        }

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tessera-updater-\(UUID().uuidString).sh")
        let script = try buildInstallScript(plan: plan, selfScriptPath: scriptURL.path)

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: scriptURL.path
            )
        } catch {
            throw UpdateInstallerError.failedToLaunchHelper(error.localizedDescription)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        process.standardInput = FileHandle.nullDevice

        // Redirect logs to /tmp/tessera-updater.log so diagnostics remain inspectable if anything fails
        let logPath = "/tmp/tessera-updater.log"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        if let logHandle = FileHandle(forWritingAtPath: logPath) {
            logHandle.seekToEndOfFile()
            process.standardOutput = logHandle
            process.standardError = logHandle
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }

        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: scriptURL)
            throw UpdateInstallerError.failedToLaunchHelper(error.localizedDescription)
        }
    }
}
