import SwiftUI
import TesseraCore

struct LayoutSidebarView: View {
    @EnvironmentObject private var appState: AppState
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
            // Brand header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: "#6366F1").opacity(0.22))
                        .frame(width: 28, height: 28)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color(hex: "#6366F1").opacity(0.45), lineWidth: 1)
                        )
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: "#818CF8"))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(TesseraMetadata.appName)
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    Text("v\(TesseraMetadata.currentVersionString)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Button {
                    appState.createNewLayout()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11.5, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("New Mosaic Layout (⌘N)")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 10)

            // Search box
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11.5, weight: .medium))
                TextField("Filter mosaics…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
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
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Layouts list
            List(selection: Binding(
                get: { appState.selectedLayoutID },
                set: { appState.selectLayout($0) }
            )) {
                if !pinned.isEmpty {
                    Section("Pinned") {
                        ForEach(pinned) { layout in
                            SidebarLayoutRow(layout: layout)
                                .tag(layout.id)
                        }
                    }
                }

                Section(pinned.isEmpty ? "Mosaics" : "All Mosaics") {
                    ForEach(unpinned) { layout in
                        SidebarLayoutRow(layout: layout)
                            .tag(layout.id)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Footer: Terminal count + Update button
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10.5, weight: .medium))
                    Text("\(appState.installedTerminals.count) terminals")
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                updateFooterButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
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
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(hex: layout.accentHex).opacity(0.18))
                    .frame(width: 28, height: 28)
                Image(systemName: layout.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: layout.accentHex))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(layout.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if layout.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    if layout.hasAnyCustomScript {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 9, weight: .semibold))
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
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color(hex: layout.accentHex), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Launch \(layout.name)")
            }
        }
        .padding(.vertical, 3)
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
