import SwiftUI
import TesseraCore

struct PaneInspectorView: View {
    @EnvironmentObject private var appState: AppState
    let layout: TesseraLayout
    let pane: PaneSpec

    @State private var newCommandText = ""

    private static let quickSnippets: [(label: String, command: String)] = [
        ("git status", "git status -sb"),
        ("npm dev", "npm run dev"),
        ("swift test", "swift test"),
        ("docker ps", "docker ps"),
        ("htop/top", "top -o cpu")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Label("Pane Inspector", systemImage: "slider.horizontal.3")
                        .font(.headline)
                    Spacer()
                    if let tab = appState.selectedTab, tab.root.leafCount > 1 {
                        Button(role: .destructive) {
                            appState.removePane(pane.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this pane")
                    }
                }

                // Identity & Focus
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pane Title")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("e.g. API Server", text: titleBinding)
                                .textFieldStyle(.roundedBorder)
                        }

                        Toggle(isOn: focusBinding) {
                            Label("Focus this pane on launch", systemImage: "star.fill")
                                .font(.callout)
                        }

                        HStack {
                            Text("Startup Delay")
                                .font(.callout)
                            Spacer()
                            Stepper(
                                value: delayBinding,
                                in: 0...30,
                                step: 0.5
                            ) {
                                Text(pane.delaySeconds == 0 ? "None" : String(format: "%.1fs", pane.delaySeconds))
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(pane.delaySeconds > 0 ? .orange : .secondary)
                            }
                        }
                    }
                    .padding(4)
                }

                // Working Directory & Profile
                GroupBox("Directory & Profile") {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Working Directory Override")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                TextField(
                                    "Inherits \(layout.workingDirectory)",
                                    text: workingDirectoryBinding
                                )
                                .font(.system(.callout, design: .monospaced))
                                .textFieldStyle(.roundedBorder)

                                Button {
                                    if let chosen = appState.pickDirectory(
                                        initialPath: pane.workingDirectory ?? layout.workingDirectory
                                    ) {
                                        appState.updatePane(pane.id) { $0.workingDirectory = chosen }
                                    }
                                } label: {
                                    Image(systemName: "folder")
                                }
                                .help("Browse folder")
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Terminal Profile (Optional)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("e.g. Default, Pro, Dracula (iTerm2 / Terminal)", text: profileBinding)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(4)
                }

                // Startup Commands
                GroupBox("Startup Commands") {
                    VStack(alignment: .leading, spacing: 8) {
                        if pane.commands.isEmpty {
                            Text("No startup commands yet — pane opens an interactive shell.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(pane.commands.enumerated()), id: \.offset) { index, _ in
                                HStack(spacing: 6) {
                                    Text("$")
                                        .font(.system(.caption, design: .monospaced).bold())
                                        .foregroundStyle(Color(hex: layout.accentHex))
                                    TextField("Command", text: commandBinding(at: index))
                                        .font(.system(.callout, design: .monospaced))
                                        .textFieldStyle(.roundedBorder)

                                    Button {
                                        appState.updatePane(pane.id) { p in
                                            guard p.commands.indices.contains(index) else { return }
                                            p.commands.remove(at: index)
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        HStack(spacing: 6) {
                            TextField("Add command (e.g. npm run dev)", text: $newCommandText)
                                .font(.system(.callout, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { appendCommand() }

                            Button("Add") { appendCommand() }
                                .disabled(newCommandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        // Quick snippet pills
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Self.quickSnippets, id: \.label) { snippet in
                                    Button("+ \(snippet.label)") {
                                        appState.updatePane(pane.id) { $0.commands.append(snippet.command) }
                                    }
                                    .font(.caption2)
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                            }
                        }
                    }
                    .padding(4)
                }

                // Environment Variables
                GroupBox("Environment Variables") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(pane.environment) { entry in
                            HStack(spacing: 6) {
                                TextField("KEY", text: envKeyBinding(id: entry.id))
                                    .font(.system(.caption, design: .monospaced))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 95)
                                Text("=")
                                    .foregroundStyle(.secondary)
                                TextField("value", text: envValueBinding(id: entry.id))
                                    .font(.system(.caption, design: .monospaced))
                                    .textFieldStyle(.roundedBorder)
                                Button {
                                    appState.updatePane(pane.id) { p in
                                        p.environment.removeAll(where: { $0.id == entry.id })
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button {
                            appState.updatePane(pane.id) { p in
                                p.environment.append(EnvEntry(key: "NODE_ENV", value: "development"))
                            }
                        } label: {
                            Label("Add Variable", systemImage: "plus")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(4)
                }

                // Split Actions
                GroupBox("Split This Pane") {
                    HStack(spacing: 8) {
                        Button {
                            appState.splitPane(pane.id, direction: .columns)
                        } label: {
                            Label("Left | Right", systemImage: "rectangle.split.2x1")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            appState.splitPane(pane.id, direction: .rows)
                        } label: {
                            Label("Top / Bottom", systemImage: "rectangle.split.1x2")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(4)
                }
            }
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private func appendCommand() {
        let trimmed = newCommandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.updatePane(pane.id) { $0.commands.append(trimmed) }
        newCommandText = ""
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { pane.title },
            set: { newValue in appState.updatePane(pane.id) { $0.title = newValue } }
        )
    }

    private var focusBinding: Binding<Bool> {
        Binding(
            get: { pane.focus },
            set: { newValue in
                if newValue {
                    appState.setFocusedPane(pane.id)
                } else {
                    appState.updatePane(pane.id) { $0.focus = false }
                }
            }
        )
    }

    private var delayBinding: Binding<Double> {
        Binding(
            get: { pane.delaySeconds },
            set: { newValue in appState.updatePane(pane.id) { $0.delaySeconds = max(0, newValue) } }
        )
    }

    private var workingDirectoryBinding: Binding<String> {
        Binding(
            get: { pane.workingDirectory ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                appState.updatePane(pane.id) { $0.workingDirectory = trimmed.isEmpty ? nil : newValue }
            }
        )
    }

    private var profileBinding: Binding<String> {
        Binding(
            get: { pane.profile ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                appState.updatePane(pane.id) { $0.profile = trimmed.isEmpty ? nil : newValue }
            }
        )
    }

    private func commandBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { pane.commands.indices.contains(index) ? pane.commands[index] : "" },
            set: { newValue in
                appState.updatePane(pane.id) { p in
                    guard p.commands.indices.contains(index) else { return }
                    p.commands[index] = newValue
                }
            }
        )
    }

    private func envKeyBinding(id: UUID) -> Binding<String> {
        Binding(
            get: { pane.environment.first(where: { $0.id == id })?.key ?? "" },
            set: { newValue in
                appState.updatePane(pane.id) { p in
                    if let idx = p.environment.firstIndex(where: { $0.id == id }) {
                        p.environment[idx].key = newValue
                    }
                }
            }
        )
    }

    private func envValueBinding(id: UUID) -> Binding<String> {
        Binding(
            get: { pane.environment.first(where: { $0.id == id })?.value ?? "" },
            set: { newValue in
                appState.updatePane(pane.id) { p in
                    if let idx = p.environment.firstIndex(where: { $0.id == id }) {
                        p.environment[idx].value = newValue
                    }
                }
            }
        )
    }
}
