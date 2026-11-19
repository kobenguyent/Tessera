import AppKit
import SwiftUI
import TesseraCore

struct UpdateSheetView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: "#10B981").opacity(0.18))
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color(hex: "#10B981").opacity(0.45), lineWidth: 1)
                        )
                    Image(systemName: "arrow.down.app.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color(hex: "#10B981"))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Tessera Software Update")
                        .font(.title3.bold())
                    Text("GitHub Releases · \(appState.settings.githubRepository)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            contentBody

            Divider()

            footerButtons
        }
        .padding(22)
        .frame(width: 540)
    }

    @ViewBuilder
    private var contentBody: some View {
        switch appState.updateState {
        case .checking:
            HStack(spacing: 12) {
                ProgressView()
                Text("Checking GitHub Releases for \(appState.settings.githubRepository)…")
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, minHeight: 120)

        case .upToDate(let current, let latest, let checkedAt):
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color(hex: "#10B981"))
                Text("You're up to date!")
                    .font(.headline)
                Text("Installed: \(current.tagString)" + (latest.map { " · Latest release: \($0.tagString)" } ?? ""))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Last checked \(checkedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 140)

        case .updateAvailable(let update):
            VStack(alignment: .leading, spacing: 10) {
                releaseDetailsView(update: update)
                if update.preferredAsset != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.circle.fill")
                            .foregroundStyle(Color(hex: "#10B981"))
                        Text(
                            UpdateInstaller.currentAppBundleURL() != nil
                                ? "Once downloaded and verified, Tessera will automatically close, update, and relaunch."
                                : "Once downloaded and verified, Tessera will close and open the downloaded installer."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

        case .downloading(let progress, let assetName, let update):
            VStack(alignment: .leading, spacing: 12) {
                releaseDetailsView(update: update)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Downloading \(assetName)…")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(.system(.callout, design: .monospaced))
                    }
                    ProgressView(value: progress, total: 1.0)
                }
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

        case .installing(let downloaded):
            VStack(alignment: .leading, spacing: 12) {
                releaseDetailsView(update: downloaded.release)
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Closing Tessera to install \(downloaded.release.version.tagString)…")
                            .font(.callout.weight(.semibold))
                        Text(
                            downloaded.checksumVerified
                                ? "SHA-256 verified (\(downloaded.sha256Hex.prefix(16))…) · Relaunching automatically"
                                : "Applying update and relaunching automatically"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color(hex: "#10B981").opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

        case .readyToInstall(let downloaded):
            VStack(alignment: .leading, spacing: 12) {
                releaseDetailsView(update: downloaded.release)
                HStack(spacing: 10) {
                    Image(systemName: downloaded.checksumVerified ? "checkmark.shield.fill" : "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color(hex: "#10B981"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ready to Install: \(downloaded.fileURL.lastPathComponent)")
                            .font(.callout.weight(.semibold))
                        Text(
                            downloaded.checksumVerified
                                ? "SHA-256 checksum verified (\(downloaded.sha256Hex.prefix(16))…)"
                                : "Saved to \(downloaded.fileURL.path)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color(hex: "#10B981").opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

        case .failed(let message):
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                Text("Could Not Check for Updates")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 130)

        case .idle:
            VStack(spacing: 8) {
                Text("Current Version: \(TesseraMetadata.currentVersion.tagString)")
                    .font(.headline)
                Text("Check GitHub Releases to download the latest native macOS build.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 110)
        }
    }

    private func releaseDetailsView(update: UpdateRelease) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PillBadge(text: TesseraMetadata.currentVersion.tagString, tint: .secondary)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PillBadge(text: update.version.tagString, systemImage: "sparkles", tint: Color(hex: "#10B981"))

                if update.release.isPrerelease {
                    PillBadge(text: "Pre-release", tint: .orange)
                }

                Spacer()

                if let published = update.release.publishedAt {
                    Text(published.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(update.release.displayTitle)
                .font(.headline)

            if let asset = update.preferredAsset {
                HStack(spacing: 6) {
                    Image(systemName: "shippingbox.fill")
                        .foregroundStyle(Color(hex: "#6366F1"))
                    Text("\(asset.name) · \(asset.formattedSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if update.release.checksumAsset != nil {
                        PillBadge(text: "SHA-256 Verified", systemImage: "lock.shield", tint: Color(hex: "#0EA5E9"))
                    }
                }
            }

            ScrollView {
                Text(
                    (update.release.body?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                        ?? "No release notes provided for this version."
                )
                .font(.system(size: 12))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .frame(height: 170)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
        HStack {
            if let release = appState.updateState.availableRelease {
                Button("Skip Version") {
                    appState.skipUpdate(release)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Button("View on GitHub") {
                    NSWorkspace.shared.open(release.release.htmlURL)
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)

            switch appState.updateState {
            case .updateAvailable(let update):
                if update.preferredAsset != nil {
                    Button {
                        appState.downloadAvailableUpdate()
                    } label: {
                        Label("Download & Install", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#10B981"))
                } else {
                    Button("Open Release Page") {
                        NSWorkspace.shared.open(update.release.htmlURL)
                    }
                    .buttonStyle(.borderedProminent)
                }

            case .readyToInstall(let downloaded):
                Button("Reveal in Finder") {
                    appState.openDownloadedInstaller(downloaded)
                }
                .buttonStyle(.bordered)

                Button {
                    appState.installUpdateAndTerminate(downloaded)
                } label: {
                    Label("Quit & Install Update", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#10B981"))

            case .checking, .downloading, .installing:
                EmptyView()

            default:
                Button("Check Now") {
                    Task { await appState.checkForUpdates(userInitiated: true) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
