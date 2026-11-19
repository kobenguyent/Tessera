import SwiftUI
import TesseraCore

struct StudioView: View {
    @EnvironmentObject private var appState: AppState

    @State private var dismissedBannerVersion: SemanticVersion?
    @State private var showingSidebar = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 0) {
                if showingSidebar {
                    LayoutSidebarView(showingSidebar: $showingSidebar)
                        .frame(width: 260)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider().opacity(0.6)
                }

                VStack(spacing: 0) {
                    if let release = appState.updateState.availableRelease,
                       dismissedBannerVersion != release.version {
                        updateBanner(release: release)
                        Divider().opacity(0.6)
                    }

                    if let layout = appState.selectedLayout {
                        LayoutWorkspaceView(layout: layout, showingSidebar: $showingSidebar)
                    } else {
                        ContentUnavailableView {
                            Label("No Mosaic Selected", systemImage: "square.grid.2x2")
                        } description: {
                            Text("Create a new terminal mosaic or choose one from the sidebar.")
                        } actions: {
                            Button("Create New Mosaic") {
                                appState.createNewLayout()
                            }
                            .buttonStyle(TesseraProminentButtonStyle())
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea(.container, edges: .top)
            .animation(TesseraMotion.smooth, value: showingSidebar)

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
        .sheet(isPresented: $appState.showingCommandLibrarySheet) {
            CommandLibrarySheet()
                .environmentObject(appState)
        }
    }

    private func updateBanner(release: UpdateRelease) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: "#10B981"))
                .frame(width: 7, height: 7)
            Text("Tessera **\(release.version.tagString)** is available on GitHub Releases")
                .font(.system(size: 12.5))
                .lineLimit(1)
            if case .downloading(let progress, _, _) = appState.updateState {
                ProgressView(value: progress, total: 1.0)
                    .frame(width: 110)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(.caption, design: .monospaced))
            }
            Spacer(minLength: 8)
            Button("Details & Install") {
                appState.showingUpdateSheet = true
            }
            .font(.system(size: 11.5, weight: .semibold))
            .buttonStyle(TesseraProminentButtonStyle(tint: Color(hex: "#10B981"), cornerRadius: 7, horizontalPadding: 10, verticalPadding: 4.5))
            .fixedSize()

            Button {
                withAnimation(TesseraMotion.smooth) {
                    dismissedBannerVersion = release.version
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(TesseraIconButtonStyle(size: 22))
            .help("Dismiss banner")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background(Color(hex: "#10B981").opacity(0.09))
    }
}
