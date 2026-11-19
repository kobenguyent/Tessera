import SwiftUI
import TesseraCore

struct StudioView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // Non-intrusive GitHub Release Update Banner
                if let release = appState.updateState.availableRelease {
                    updateBanner(release: release)
                    Divider()
                }

                NavigationSplitView {
                    LayoutSidebarView()
                        .navigationSplitViewColumnWidth(min: 235, ideal: 265, max: 320)
                } detail: {
                    if let layout = appState.selectedLayout {
                        LayoutWorkspaceView(layout: layout)
                    } else {
                        ContentUnavailableView {
                            Label("No Mosaic Selected", systemImage: "square.grid.2x2")
                        } description: {
                            Text("Create a new terminal mosaic or choose one from the sidebar.")
                        } actions: {
                            Button("Create New Mosaic") {
                                appState.createNewLayout()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }

            // Floating Launch / Status Toast
            if let toast = appState.toast {
                HStack(spacing: 10) {
                    Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(toast.isError ? Color.orange : Color(hex: "#10B981"))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(toast.title)
                            .font(.callout.weight(.semibold))
                        if let subtitle = toast.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(toast.isError ? Color.orange.opacity(0.4) : Color(hex: "#10B981").opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                .padding(18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.25), value: appState.toast)
        .sheet(isPresented: $appState.showingUpdateSheet) {
            UpdateSheetView()
                .environmentObject(appState)
        }
    }

    private func updateBanner(release: UpdateRelease) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color(hex: "#10B981"))
            Text("Tessera **\(release.version.tagString)** is available on GitHub Releases")
                .font(.callout)
            if case .downloading(let progress, _, _) = appState.updateState {
                ProgressView(value: progress, total: 1.0)
                    .frame(width: 110)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(.caption, design: .monospaced))
            }
            Spacer()
            Button("Details & Install") {
                appState.showingUpdateSheet = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: "#10B981"))
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(hex: "#10B981").opacity(0.11))
    }
}
