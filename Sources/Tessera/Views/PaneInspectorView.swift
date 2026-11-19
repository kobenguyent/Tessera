import SwiftUI
import TesseraCore

struct PaneInspectorView: View {
    @EnvironmentObject private var appState: AppState
    let layout: TesseraLayout
    let pane: PaneSpec

    @State private var newCommandText = ""
    @State private var showingQuickAddLibraryPopover = false
    @State private var libraryDraftLabel = ""
    @State private var libraryDraftCommand = ""
    @State private var libraryDraftCategory: CommandCategory = .custom

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
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Startup Commands")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                appState.showingCommandLibrarySheet = true
                            } label: {
                                Label("Library (\(appState.commandLibrary.count))", systemImage: "books.vertical")
                                    .font(.caption2.weight(.medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .help("Browse, add, and organize reusable custom commands (⇧⌘L)")
                        }

                        if pane.commands.isEmpty {
                            Text("No startup commands yet — pane opens an interactive shell.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(pane.commands.enumerated()), id: \.offset) { index, cmdText in
                                HStack(spacing: 6) {
                                    Text("$")
                                        .font(.system(.caption, design: .monospaced).bold())
                                        .foregroundStyle(Color(hex: layout.accentHex))
                                    TextField("Command", text: commandBinding(at: index))
                                        .font(.system(.callout, design: .monospaced))
                                        .textFieldStyle(.roundedBorder)

                                    let alreadySaved = appState.isCommandInLibrary(cmdText)
                                    Button {
                                        openQuickSavePopover(prefillCommand: cmdText)
                                    } label: {
                                        Image(systemName: alreadySaved ? "bookmark.fill" : "bookmark")
                                            .font(.caption)
                                            .foregroundStyle(alreadySaved ? Color(hex: "#A855F7") : .secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(cmdText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    .help(alreadySaved ? "Already in Command Library (click to save another copy)" : "Save this command to your Command Library")

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

                            Button {
                                openQuickSavePopover(prefillCommand: newCommandText)
                            } label: {
                                Image(systemName: "bookmark.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Add custom command to Library")
                            .popover(isPresented: $showingQuickAddLibraryPopover) {
                                quickAddLibraryPopover
                            }
                        }

                        // Reusable Command Library Chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(appState.commandLibrary) { snippet in
                                    Button {
                                        appState.updatePane(pane.id) { $0.commands.append(snippet.command) }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: snippet.category.symbolName)
                                                .font(.system(size: 8.5))
                                                .foregroundStyle(Color(hex: snippet.category.accentHex))
                                            Text(snippet.label)
                                        }
                                    }
                                    .font(.caption2)
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    .help("$ \(snippet.command)")
                                    .contextMenu {
                                        Button("Insert into Pane") {
                                            appState.updatePane(pane.id) { $0.commands.append(snippet.command) }
                                        }
                                        Button("Manage Command Library…") {
                                            appState.showingCommandLibrarySheet = true
                                        }
                                        Divider()
                                        Button("Remove from Library", role: .destructive) {
                                            appState.deleteCommandFromLibrary(snippet)
                                        }
                                    }
                                }

                                Button {
                                    openQuickSavePopover(prefillCommand: newCommandText)
                                } label: {
                                    Label("New…", systemImage: "plus")
                                }
                                .font(.caption2.weight(.semibold))
                                .buttonStyle(.borderedProminent)
                                .tint(Color(hex: layout.accentHex))
                                .controlSize(.mini)
                                .help("Add a new custom command to your library")
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

    private func openQuickSavePopover(prefillCommand: String) {
        let trimmed = prefillCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        libraryDraftCommand = trimmed
        libraryDraftLabel = trimmed.isEmpty ? "" : CommandSnippet.suggestedLabel(for: trimmed)
        libraryDraftCategory = .custom
        showingQuickAddLibraryPopover = true
    }

    private var quickAddLibraryPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Add to Command Library", systemImage: "bookmark.fill")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Label")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Start Backend", text: $libraryDraftLabel)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Command")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. docker compose up -d", text: $libraryDraftCommand)
                    .font(.system(.callout, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
            }

            Picker("Category", selection: $libraryDraftCategory) {
                ForEach(CommandCategory.allCases) { cat in
                    Label(cat.displayName, systemImage: cat.symbolName).tag(cat)
                }
            }

            HStack {
                Button("Open Full Library") {
                    showingQuickAddLibraryPopover = false
                    appState.showingCommandLibrarySheet = true
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Spacer()

                Button("Save") {
                    if appState.addCommandToLibrary(
                        label: libraryDraftLabel,
                        command: libraryDraftCommand,
                        category: libraryDraftCategory
                    ) != nil {
                        showingQuickAddLibraryPopover = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(libraryDraftCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 300)
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
