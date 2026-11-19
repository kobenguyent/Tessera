import AppKit
import SwiftUI
import TesseraCore

struct ScriptEditorView: View {
    @EnvironmentObject private var appState: AppState
    let layout: TesseraLayout

    @State private var copied = false
    @State private var isValidating = false
    @State private var validationResult: ScriptValidationResult?

    private var terminal: TerminalKind {
        appState.resolvedTerminal(for: layout)
    }

    private var currentPlan: LaunchPlan {
        appState.makeLaunchPlan(for: layout, terminalOverride: terminal, includeLiveDraft: true)
    }

    private var hasUnsavedDraft: Bool {
        appState.hasUnsavedScriptDraft(for: layout, terminal: terminal)
    }

    private var hasSavedOverride: Bool {
        layout.hasCustomScript(for: terminal)
    }

    private var scriptTextBinding: Binding<String> {
        Binding(
            get: { appState.effectiveScriptText(for: layout, terminal: terminal) },
            set: { updated in
                appState.setLiveScriptDraft(updated, for: layout, terminal: terminal)
                if validationResult != nil {
                    validationResult = nil
                }
            }
        )
    }

    private var currentText: String {
        appState.effectiveScriptText(for: layout, terminal: terminal)
    }

    private var lineCount: Int {
        max(1, currentText.reduce(1) { $0 + ($1 == "\n" ? 1 : 0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Editor Toolbar
            editorToolbar
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(red: 0.11, green: 0.12, blue: 0.16))

            // Optional Syntax Validation Result Banner
            if let result = validationResult {
                HStack(spacing: 8) {
                    Image(systemName: result.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(result.isValid ? Color(hex: "#10B981") : Color.orange)
                    Text(result.message)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.92))
                        .textSelection(.enabled)
                        .lineLimit(3)
                    Spacer()
                    Button {
                        validationResult = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(result.isValid ? Color(hex: "#10B981").opacity(0.16) : Color.orange.opacity(0.18))
            }

            // Optional Adapter Warnings
            if !currentPlan.warnings.isEmpty && !hasSavedOverride && !hasUnsavedDraft {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(currentPlan.warnings.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.orange.opacity(0.10))
            }

            Divider().overlay(.white.opacity(0.08))

            // Native Code Editor with Line Numbers & Find Bar (⌘F)
            CodeEditorView(
                text: scriptTextBinding,
                language: currentPlan.previewLanguage
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().overlay(.white.opacity(0.08))

            // Status Bar
            statusBar
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color(red: 0.09, green: 0.10, blue: 0.14))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    hasUnsavedDraft
                        ? Color.orange.opacity(0.45)
                        : Color(hex: layout.accentHex).opacity(0.32),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        .onChange(of: layout.id) { _, _ in
            validationResult = nil
        }
        .onChange(of: terminal) { _, _ in
            validationResult = nil
        }
    }

    // MARK: - Toolbar

    private var editorToolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: terminal.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: layout.accentHex))
                Text(currentPlan.previewTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                PillBadge(
                    text: currentPlan.previewLanguage.uppercased(),
                    tint: Color(hex: "#6366F1")
                )

                stateBadge
            }

            Spacer(minLength: 8)

            // Syntax Check Button
            Button {
                validateCurrentScript()
            } label: {
                HStack(spacing: 4) {
                    if isValidating {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "checkmark.shield")
                    }
                    Text("Validate")
                }
                .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isValidating)
            .help("Check script syntax without executing")

            // Copy Button
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(currentText, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    copied = false
                }
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // Discard Unsaved Edits (keeps saved override if any)
            if hasUnsavedDraft {
                Button {
                    appState.discardLiveScriptDraft(for: layout, terminal: terminal)
                    validationResult = nil
                } label: {
                    Text("Revert")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Discard unsaved edits")
            }

            // Regenerate from Visual Mosaic (clears draft & saved override)
            if hasSavedOverride || hasUnsavedDraft {
                Button {
                    appState.resetScriptToGenerated(for: layout, terminal: terminal)
                    validationResult = nil
                } label: {
                    Label("Reset to Mosaic", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Clear custom script and regenerate from visual panes")
            }

            // Save Custom Script Override to Layout (⌘S)
            Button {
                appState.saveLiveScriptOverride(for: layout, terminal: terminal)
            } label: {
                Label("Save Override", systemImage: "square.and.arrow.down")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(hasUnsavedDraft ? Color(hex: "#10B981") : Color.secondary.opacity(0.45))
            .controlSize(.small)
            .disabled(!hasUnsavedDraft)
            .keyboardShortcut("s", modifiers: .command)
            .help("Persist edited script for \(terminal.displayName) in this layout (⌘S)")
        }
    }

    @ViewBuilder
    private var stateBadge: some View {
        if hasUnsavedDraft {
            PillBadge(text: "Unsaved Draft · Runs Live", systemImage: "pencil.circle.fill", tint: .orange)
        } else if hasSavedOverride {
            PillBadge(text: "Saved Custom Script", systemImage: "checkmark.seal.fill", tint: Color(hex: "#10B981"))
        } else {
            PillBadge(text: "Auto-Generated", systemImage: "wand.and.stars", tint: Color(hex: "#0EA5E9"))
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text("\(lineCount) lines · \(currentText.count) chars")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))

            Text("·")
                .foregroundStyle(.white.opacity(0.3))

            Text("Edit freely and press ⌘↩ to run on the fly — or ⌘S to save as this terminal's override")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)

            Spacer()

            Text("⌘F Find")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
        }
    }

    private func validateCurrentScript() {
        let text = currentText
        let language = currentPlan.previewLanguage
        isValidating = true
        Task {
            let result = await ScriptValidator.validate(script: text, language: language)
            isValidating = false
            validationResult = result
        }
    }
}
