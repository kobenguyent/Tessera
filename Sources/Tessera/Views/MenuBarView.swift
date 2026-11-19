import AppKit
import SwiftUI
import TesseraCore

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var hoveredLayoutID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 7) {
                TesseraLogoView(size: 18)
                Text("Tessera Mosaics")
                    .font(.headline)
                Spacer()

                // Quick Terminal Override Menu
                Menu {
                    Button("Layout Default") {
                        appState.menuBarTerminalOverride = nil
                    }
                    Divider()
                    ForEach(TerminalKind.allCases) { kind in
                        Button {
                            appState.menuBarTerminalOverride = kind
                        } label: {
                            HStack {
                                Text(kind.displayName + (appState.isTerminalInstalled(kind) ? "" : " (Not installed)"))
                                if appState.menuBarTerminalOverride == kind {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "terminal")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(appState.menuBarTerminalOverride?.displayName ?? "Auto")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(TesseraSoftButtonStyle(cornerRadius: 7, horizontalPadding: 8, verticalPadding: 3.5))
                .fixedSize()
            }

            // Update Banner inside Menu Bar Popover
            if let release = appState.updateState.availableRelease {
                Button {
                    openStudioWindow()
                    appState.showingUpdateSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Color(hex: "#10B981"))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Update Available: \(release.version.tagString)")
                                .font(.caption.weight(.semibold))
                            Text("Click to view notes & download")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color(hex: "#10B981").opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Layouts Scroll List
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if !appState.pinnedLayouts.isEmpty {
                        Text("PINNED")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        ForEach(appState.pinnedLayouts) { layout in
                            menuBarLayoutButton(layout)
                        }

                        Divider().padding(.vertical, 4)
                    }

                    let others = appState.layouts.filter { !$0.isPinned }
                    if !others.isEmpty {
                        Text("ALL MOSAICS")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        ForEach(others) { layout in
                            menuBarLayoutButton(layout)
                        }
                    }
                }
            }
            .frame(maxHeight: 280)

            Divider()

            // Footer Actions
            HStack {
                Button {
                    openStudioWindow()
                } label: {
                    Label("Open Studio", systemImage: "macwindow")
                        .font(.callout)
                }
                .buttonStyle(.borderless)

                Spacer()

                Button {
                    Task {
                        await appState.checkForUpdates(userInitiated: true)
                        if appState.updateState.hasActionableUpdate {
                            openStudioWindow()
                        }
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)
                .help("Check for Updates")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("Quit")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .frame(width: 310)
    }

    private func menuBarLayoutButton(_ layout: TesseraLayout) -> some View {
        let effective = appState.resolvedTerminal(for: layout, override: appState.menuBarTerminalOverride)
        let isHovered = hoveredLayoutID == layout.id
        return Button {
            appState.launch(layout: layout, terminalOverride: appState.menuBarTerminalOverride)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: layout.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: layout.accentHex))
                    .frame(width: 24, height: 24)
                    .background(Color(hex: layout.accentHex).opacity(isHovered ? 0.24 : 0.16), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(layout.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(layout.totalPaneCount) pane\(layout.totalPaneCount == 1 ? "" : "s") · \(effective.displayName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .foregroundStyle(Color(hex: layout.accentHex).opacity(isHovered ? 1.0 : 0.72))
                    .scaleEffect(isHovered ? 1.08 : 1.0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .animation(TesseraMotion.hover, value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredLayoutID = hovering ? layout.id : (hoveredLayoutID == layout.id ? nil : hoveredLayoutID)
        }
    }

    private func openStudioWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "studio")
    }
}
