import AppKit
import SwiftUI
import TesseraCore

final class TesseraAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure standard Dock + Window presence even when launched directly via `swift run`
        NSApplication.shared.setActivationPolicy(.regular)
        if let appIcon = TesseraAppIconRenderer.makeNSImage(pixelSize: 512) {
            NSApplication.shared.applicationIconImage = appIcon
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@main
struct TesseraApp: App {
    @NSApplicationDelegateAdaptor(TesseraAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        Window("Tessera Studio", id: "studio") {
            StudioView()
                .environmentObject(appState)
                .frame(minWidth: 1020, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1220, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Mosaic Layout") {
                    appState.createNewLayout()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("Mosaic") {
                Button("Launch Active Mosaic") {
                    if let layout = appState.selectedLayout {
                        appState.launch(layout: layout)
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(appState.selectedLayout == nil)

                Button("Toggle Script Editor") {
                    appState.workspaceMode = (appState.workspaceMode == .script) ? .mosaic : .script
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(appState.selectedLayout == nil)

                Button("Command Library…") {
                    appState.showingCommandLibrarySheet = true
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                Button("Import Layouts JSON…") {
                    appState.importLayoutsWithPanel()
                }
                Button("Export Layouts JSON…") {
                    appState.exportLayoutsWithPanel()
                }
            }

            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    appState.showingUpdateSheet = true
                    Task { await appState.checkForUpdates(userInitiated: true) }
                }
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Label {
                Text("Tessera")
            } icon: {
                Image(systemName: appState.updateState.hasActionableUpdate ? "square.grid.2x2.topleft.filled" : "square.grid.2x2.fill")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
