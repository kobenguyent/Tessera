import AppKit
import SwiftUI
import TesseraCore

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }

            terminalsTab
                .tabItem { Label("Terminals", systemImage: "terminal") }

            commandsTab
                .tabItem { Label("Commands", systemImage: "books.vertical") }

            updatesTab
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }

            cliAndDataTab
                .tabItem { Label("CLI & Data", systemImage: "square.and.arrow.up.on.square") }
        }
        .frame(width: 640, height: 470)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("Default Terminal") {
                Picker("Default Terminal Driver", selection: Binding(
                    get: { appState.settings.defaultTerminal },
                    set: {
                        appState.settings.defaultTerminal = $0
                        appState.saveSettings()
                    }
                )) {
                    ForEach(TerminalKind.allCases) { kind in
                        let installed = appState.isTerminalInstalled(kind)
                        Text(installed ? "\(kind.displayName)" : "\(kind.displayName) (Not detected)")
                            .tag(kind)
                    }
                }
                Text(appState.settings.defaultTerminal.shortSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About Tessera") {
                LabeledContent("Version", value: TesseraMetadata.currentVersion.tagString)
                LabeledContent("Bundle ID", value: TesseraMetadata.bundleIdentifier)
                LabeledContent("Layouts Saved", value: "\(appState.layouts.count)")
                LabeledContent("Commands in Library", value: "\(appState.commandLibrary.count)")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Terminals Matrix

    private var terminalsTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Detected Terminal Emulators")
                    .font(.headline)
                Spacer()
                Button {
                    appState.refreshTerminals()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding([.horizontal, .top], 16)

            List(appState.detectedTerminals) { item in
                let caps = item.kind.capabilities
                HStack(spacing: 12) {
                    Image(systemName: item.kind.symbolName)
                        .font(.title3)
                        .foregroundStyle(item.isInstalled ? Color(hex: "#10B981") : .secondary)
                        .frame(width: 26)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(item.kind.displayName)
                                .font(.callout.weight(.semibold))
                            if item.isInstalled {
                                PillBadge(text: "Installed", tint: Color(hex: "#10B981"))
                            } else {
                                PillBadge(text: "Not Found", tint: .secondary)
                            }
                            if caps.nativeSplits {
                                PillBadge(text: "Native Splits", tint: Color(hex: "#6366F1"))
                            }
                        }

                        Text(item.resolvedPath ?? item.kind.shortSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Command Library

    private var commandsTab: some View {
        CommandLibraryManagerView(showInsertAction: false)
            .padding(16)
    }

    // MARK: - Updates & GitHub Releases

    private var updatesTab: some View {
        Form {
            Section("GitHub Releases Auto-Update") {
                TextField("GitHub Repository (owner/repo)", text: Binding(
                    get: { appState.settings.githubRepository },
                    set: {
                        appState.settings.githubRepository = $0
                        appState.saveSettings()
                    }
                ))
                .font(.system(.body, design: .monospaced))

                Toggle("Automatically check for updates", isOn: Binding(
                    get: { appState.settings.autoCheckForUpdates },
                    set: {
                        appState.settings.autoCheckForUpdates = $0
                        appState.saveSettings()
                    }
                ))

                Picker("Check Frequency", selection: Binding(
                    get: { Int(appState.settings.updateCheckIntervalHours) },
                    set: {
                        appState.settings.updateCheckIntervalHours = Double($0)
                        appState.saveSettings()
                    }
                )) {
                    Text("Every 6 hours").tag(6)
                    Text("Every 12 hours").tag(12)
                    Text("Daily (24 hours)").tag(24)
                    Text("Weekly").tag(168)
                }
                .disabled(!appState.settings.autoCheckForUpdates)

                Toggle("Include pre-release builds (alpha/beta/rc)", isOn: Binding(
                    get: { appState.settings.includePrereleases },
                    set: {
                        appState.settings.includePrereleases = $0
                        appState.saveSettings()
                    }
                ))
            }

            Section("Status") {
                LabeledContent("Current Version", value: TesseraMetadata.currentVersion.tagString)
                if let lastCheck = appState.settings.lastUpdateCheckDate {
                    LabeledContent("Last Checked", value: lastCheck.formatted(date: .abbreviated, time: .shortened))
                }
                if let skipped = appState.settings.skippedVersion {
                    HStack {
                        Text("Skipped Version: v\(skipped)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") {
                            appState.settings.skippedVersion = nil
                            appState.saveSettings()
                        }
                        .controlSize(.small)
                    }
                }

                HStack {
                    Button {
                        Task { await appState.checkForUpdates(userInitiated: true) }
                    } label: {
                        Label("Check for Updates Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)

                    if appState.updateState.hasActionableUpdate {
                        Button("View Available Update") {
                            appState.showingUpdateSheet = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - CLI & Data

    private var cliAndDataTab: some View {
        Form {
            Section("Companion CLI (`tessera`)") {
                Text("Launch any mosaic from scripts, Raycast, Alfred, or your shell with `tessera run <layout>`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    appState.installBundledCLI()
                } label: {
                    Label("Install `tessera` CLI to PATH", systemImage: "terminal")
                }

                if let status = appState.cliInstallStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Backup & Presets") {
                HStack(spacing: 10) {
                    Button {
                        appState.exportLayoutsWithPanel()
                    } label: {
                        Label("Export Layouts JSON…", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        appState.importLayoutsWithPanel()
                    } label: {
                        Label("Import Layouts JSON…", systemImage: "square.and.arrow.down")
                    }
                }

                Button("Restore Built-in Preset Mosaics") {
                    appState.restoreBuiltInPresets()
                }
            }

            Section("Command Library") {
                HStack(spacing: 10) {
                    Button {
                        appState.exportCommandsWithPanel()
                    } label: {
                        Label("Export Commands JSON…", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        appState.importCommandsWithPanel()
                    } label: {
                        Label("Import Commands JSON…", systemImage: "square.and.arrow.down")
                    }
                }

                Button("Restore Default Command Library") {
                    appState.restoreBuiltInCommands()
                }
            }
        }
        .formStyle(.grouped)
    }
}
