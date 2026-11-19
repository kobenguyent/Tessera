import AppKit
import SwiftUI
import TesseraCore

struct ScriptPreviewSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let plan: LaunchPlan

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title Header
            HStack(spacing: 10) {
                Image(systemName: plan.terminal.symbolName)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.previewTitle)
                        .font(.headline)
                    Text(plan.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                PillBadge(text: plan.previewLanguage.uppercased(), tint: Color(hex: "#6366F1"))
            }

            if !plan.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(plan.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            // Code Display
            ScrollView([.vertical, .horizontal]) {
                Text(plan.previewContent)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(Color(red: 0.08, green: 0.09, blue: 0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )

            // Footer Actions
            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(plan.previewContent, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.8))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied!" : "Copy Script", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                if let selected = appState.selectedLayout {
                    Button {
                        dismiss()
                        appState.launch(layout: selected, terminalOverride: plan.terminal)
                    } label: {
                        Label("Launch in \(plan.terminal.displayName)", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 660, idealWidth: 740, minHeight: 460, idealHeight: 540)
    }
}
