import SwiftUI
import TesseraCore

struct PaneInspectorView: View {
    @EnvironmentObject private var appState: AppState
    let layout: TesseraLayout
    let pane: PaneSpec

    @State private var showingQuickAddLibraryPopover = false
    @State private var libraryDraftLabel = ""
    @State private var libraryDraftCommand = ""
    @State private var libraryDraftCategory: CommandCategory = .custom

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(spacing: 8) {
                    Text("Pane Inspector")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    Spacer()
                    if let tab = appState.selectedTab, tab.root.leafCount > 1 {
                        Button(role: .destructive) {
                            withAnimation(TesseraMotion.smooth) {
                                appState.removePane(pane.id)
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(TesseraIconButtonStyle(destructive: true, size: 24))
                        .help("Remove this pane")
                    }
                }
                .padding(.bottom, 2)

                // Identity & Focus
                InspectorSectionCard("Identity & Launch") {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pane Title")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextField("e.g. API Server", text: titleBinding)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                        }

                        Toggle("Focus this pane on launch", isOn: focusBinding)
                            .font(.system(size: 12))
                            .controlSize(.small)

                        HStack {
                            Text("Startup Delay")
                                .font(.system(size: 12))
                            Spacer()
                            Stepper(
                                value: delayBinding,
                                in: 0...30,
                                step: 0.5
                            ) {
                                Text(pane.delaySeconds == 0 ? "None" : String(format: "%.1fs", pane.delaySeconds))
                                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(pane.delaySeconds > 0 ? .orange : .secondary)
                                    .monospacedDigit()
                            }
                            .controlSize(.small)
                        }
                    }
                }

                // Working Directory & Profile
                InspectorSectionCard("Directory & Profile") {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Working Directory Override")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                TextField(
                                    "Inherits \(layout.workingDirectory)",
                                    text: workingDirectoryBinding
                                )
                                .font(.system(size: 11.5, design: .monospaced))
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)

                                Button {
                                    if let chosen = appState.pickDirectory(
                                        initialPath: pane.workingDirectory ?? layout.workingDirectory
                                    ) {
                                        appState.updatePane(pane.id) { $0.workingDirectory = chosen }
                                    }
                                } label: {
                                    Text("Browse")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .buttonStyle(TesseraSoftButtonStyle(cornerRadius: 7, horizontalPadding: 8, verticalPadding: 4.5))
                                .help("Browse folder")
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Terminal Profile (Optional)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextField("e.g. Default, Pro, Dracula", text: profileBinding)
                                .font(.system(size: 12))
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                        }
                    }
                }

                // Startup Commands (Multi-line native terminal command editor)
                InspectorSectionCard("Startup Commands") {
                    HStack(spacing: 5) {
                        Button {
                            let prefill = pane.nonEmptyCommands.last ?? ""
                            openQuickSavePopover(prefillCommand: prefill)
                        } label: {
                            Text("Save")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .buttonStyle(TesseraSoftButtonStyle(cornerRadius: 7, horizontalPadding: 7, verticalPadding: 3.5))
                        .help("Save command to your Command Library")
                        .popover(isPresented: $showingQuickAddLibraryPopover) {
                            quickAddLibraryPopover
                        }

                        Button {
                            appState.showingCommandLibrarySheet = true
                        } label: {
                            Text("Library (\(appState.commandLibrary.count))")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .buttonStyle(TesseraSoftButtonStyle(cornerRadius: 7, horizontalPadding: 7, verticalPadding: 3.5))
                        .help("Browse and organize reusable custom commands (⇧⌘L)")
                    }
                } content: {
                    VStack(alignment: .leading, spacing: 8) {
                        PaneCommandEditorView(
                            commands: commandsBinding,
                            accentHex: layout.accentHex,
                            placeholder: "One command per line (e.g. npm run dev)…",
                            fontSize: 11.5,
                            darkSurface: false
                        )
                        .frame(minHeight: 74, maxHeight: 140)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor).opacity(0.65))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                        )

                        // Quick-Insert Command Library Chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(appState.commandLibrary) { snippet in
                                    Button {
                                        appendLibraryCommand(snippet.command)
                                    } label: {
                                        Text(snippet.label)
                                            .lineLimit(1)
                                    }
                                    .font(.system(size: 10.5, weight: .medium))
                                    .buttonStyle(TesseraChipButtonStyle())
                                    .help("$ \(snippet.command)")
                                    .contextMenu {
                                        Button("Insert into Pane") {
                                            appendLibraryCommand(snippet.command)
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
                                    openQuickSavePopover(prefillCommand: pane.nonEmptyCommands.last ?? "")
                                } label: {
                                    Text("+ New")
                                }
                                .font(.system(size: 10.5, weight: .semibold))
                                .buttonStyle(TesseraChipButtonStyle(tint: Color(hex: layout.accentHex)))
                                .help("Add a new custom command to your library")
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Environment Variables
                InspectorSectionCard("Environment Variables") {
                    Button {
                        withAnimation(TesseraMotion.smooth) {
                            appState.updatePane(pane.id) { p in
                                p.environment.append(EnvEntry(key: "NODE_ENV", value: "development"))
                            }
                        }
                    } label: {
                        Text("+ Add")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .buttonStyle(TesseraSoftButtonStyle(cornerRadius: 7, horizontalPadding: 7, verticalPadding: 3.5))
                } content: {
                    VStack(alignment: .leading, spacing: 6) {
                        if pane.environment.isEmpty {
                            Text("No pane-specific environment variables.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(pane.environment) { entry in
                                HStack(spacing: 6) {
                                    TextField("KEY", text: envKeyBinding(id: entry.id))
                                        .font(.system(size: 11, design: .monospaced))
                                        .textFieldStyle(.roundedBorder)
                                        .controlSize(.small)
                                        .frame(width: 92)
                                    Text("=")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    TextField("value", text: envValueBinding(id: entry.id))
                                        .font(.system(size: 11, design: .monospaced))
                                        .textFieldStyle(.roundedBorder)
                                        .controlSize(.small)
                                    Button {
                                        withAnimation(TesseraMotion.smooth) {
                                            appState.updatePane(pane.id) { p in
                                                p.environment.removeAll(where: { $0.id == entry.id })
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9.5, weight: .bold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(TesseraIconButtonStyle(destructive: true, size: 20))
                                }
                            }
                        }
                    }
                }

                // Split Actions
                InspectorSectionCard("Split This Pane") {
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(TesseraMotion.smooth) {
                                appState.splitPane(pane.id, direction: .columns)
                            }
                        } label: {
                            Label("Left | Right", systemImage: "rectangle.split.2x1")
                                .font(.system(size: 11.5, weight: .medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TesseraSoftButtonStyle(cornerRadius: 8, horizontalPadding: 8, verticalPadding: 6))

                        Button {
                            withAnimation(TesseraMotion.smooth) {
                                appState.splitPane(pane.id, direction: .rows)
                            }
                        } label: {
                            Label("Top / Bottom", systemImage: "rectangle.split.1x2")
                                .font(.system(size: 11.5, weight: .medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TesseraSoftButtonStyle(cornerRadius: 8, horizontalPadding: 8, verticalPadding: 6))
                    }
                }
            }
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.32))
    }

    private var commandsBinding: Binding<[String]> {
        Binding(
            get: { pane.commands },
            set: { updated in
                appState.updatePane(pane.id) { $0.commands = updated }
            }
        )
    }

    private func appendLibraryCommand(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(TesseraMotion.smooth) {
            appState.updatePane(pane.id) { p in
                var cleaned = p.commands.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                cleaned.append(trimmed)
                p.commands = cleaned
            }
        }
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
