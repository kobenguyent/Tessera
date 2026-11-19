import SwiftUI
import TesseraCore

struct LayoutSidebarView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var showingSidebar: Bool
    @State private var searchText = ""

    private var filteredLayouts: [TesseraLayout] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return appState.layouts }
        return appState.layouts.filter { layout in
            layout.name.lowercased().contains(query)
                || layout.subtitle.lowercased().contains(query)
                || layout.tags.contains(where: { $0.lowercased().contains(query) })
        }
    }

    private var pinned: [TesseraLayout] {
        filteredLayouts.filter(\.isPinned)
    }

    private var unpinned: [TesseraLayout] {
        filteredLayouts.filter { !$0.isPinned }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Traffic-Lights & Sidebar Toggle Bar (aligned to 46pt top header)
            HStack(spacing: 7) {
                // Space for native macOS traffic lights (close / minimize / zoom)
                Spacer().frame(width: 62)

                TesseraLogoView(size: 19)

                Text(TesseraMetadata.appName)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 6)

                Button {
                    withAnimation(TesseraMotion.smooth) {
                        appState.createNewLayout()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 13, height: 13)
                }
                .buttonStyle(TesseraSoftButtonStyle(cornerRadius: 7, horizontalPadding: 6, verticalPadding: 4.5))
                .help("New Mosaic Layout (⌘N)")

                Button {
                    withAnimation(TesseraMotion.smooth) {
                        showingSidebar.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 13, height: 13)
                }
                .buttonStyle(TesseraSoftButtonStyle(cornerRadius: 7, horizontalPadding: 6, verticalPadding: 4.5))
                .help("Hide Sidebar")
            }
            .padding(.horizontal, 12)
            .frame(height: 46)

            Divider().opacity(0.55)

            // Search box
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11, weight: .medium))
                TextField("Filter mosaics…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5.5)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Layouts list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if !pinned.isEmpty {
                        sidebarSectionHeader("PINNED")
                        ForEach(pinned) { layout in
                            SidebarLayoutRow(
                                layout: layout,
                                isSelected: appState.selectedLayoutID == layout.id
                            )
                        }
                    }

                    sidebarSectionHeader(pinned.isEmpty ? "MOSAICS" : "ALL MOSAICS")
                        .padding(.top, pinned.isEmpty ? 2 : 8)
                    ForEach(unpinned) { layout in
                        SidebarLayoutRow(
                            layout: layout,
                            isSelected: appState.selectedLayoutID == layout.id
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }

            Divider().opacity(0.55)

            // Footer: Version + Terminal count + Update button
            HStack(spacing: 6) {
                Text("v\(TesseraMetadata.currentVersionString) · \(appState.installedTerminals.count) terminals")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                updateFooterButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.38))
    }

    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(0.55)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
    }

    @ViewBuilder
    private var updateFooterButton: some View {
        switch appState.updateState {
        case .checking:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Checking…").font(.caption2).foregroundStyle(.secondary)
            }
        case .updateAvailable(let release):
            Button {
                appState.showingUpdateSheet = true
            } label: {
                PillBadge(
                    text: "Update \(release.version.tagString)",
                    systemImage: "arrow.down.circle.fill",
                    tint: Color(hex: "#10B981")
                )
            }
            .buttonStyle(.plain)
        case .downloading(let progress, _, _):
            Button {
                appState.showingUpdateSheet = true
            } label: {
                PillBadge(
                    text: "\(Int((progress * 100).rounded()))%",
                    systemImage: "arrow.down.circle",
                    tint: Color(hex: "#0EA5E9")
                )
            }
            .buttonStyle(.plain)
        case .installing:
            Button {
                appState.showingUpdateSheet = true
            } label: {
                PillBadge(
                    text: "Installing…",
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: Color(hex: "#10B981")
                )
            }
            .buttonStyle(.plain)
        case .readyToInstall:
            Button {
                appState.showingUpdateSheet = true
            } label: {
                PillBadge(
                    text: "Install Ready",
                    systemImage: "checkmark.seal.fill",
                    tint: Color(hex: "#10B981")
                )
            }
            .buttonStyle(.plain)
        default:
            Button {
                Task { await appState.checkForUpdates(userInitiated: true) }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Check GitHub Releases for Updates")
        }
    }
}

private struct SidebarLayoutRow: View {
    @EnvironmentObject private var appState: AppState
    let layout: TesseraLayout
    let isSelected: Bool
    @State private var isHovered = false

    private var accent: Color {
        Color(hex: layout.accentHex)
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(accent.opacity(isSelected ? 0.24 : 0.16))
                    .frame(width: 28, height: 28)
                Image(systemName: layout.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(layout.name)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if layout.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                    }
                    if layout.hasAnyCustomScript {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(Color(hex: "#10B981"))
                            .help("Has custom script override")
                    }
                }

                Text("\(layout.totalPaneCount) pane\(layout.totalPaneCount == 1 ? "" : "s") · \(appState.resolvedTerminal(for: layout).displayName)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            if isHovered {
                Button {
                    appState.launch(layout: layout)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(accent, in: Circle())
                        .shadow(color: accent.opacity(0.35), radius: 4, y: 1)
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.75).combined(with: .opacity))
                .help("Launch \(layout.name)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    isSelected
                        ? accent.opacity(0.16)
                        : (isHovered ? Color.primary.opacity(0.06) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    isSelected ? accent.opacity(0.38) : Color.clear,
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .animation(TesseraMotion.hover, value: isHovered)
        .animation(TesseraMotion.smooth, value: isSelected)
        .onTapGesture {
            withAnimation(TesseraMotion.smooth) {
                appState.selectLayout(layout.id)
            }
        }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Launch Mosaic") { appState.launch(layout: layout) }
            Button("Edit Script") { appState.openScriptEditor(for: layout) }
            Divider()
            Button(layout.isPinned ? "Unpin from Menu Bar" : "Pin to Menu Bar") {
                appState.togglePin(layout)
            }
            Button("Duplicate") { appState.duplicateLayout(layout) }
            Divider()
            Button("Delete", role: .destructive) { appState.deleteLayout(layout) }
        }
    }
}
