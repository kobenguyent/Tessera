import AppKit
import SwiftUI
import TesseraCore

struct CommandLibraryManagerView: View {
    @EnvironmentObject private var appState: AppState
    var showInsertAction: Bool = true
    var onInsert: ((String) -> Void)? = nil

    @State private var searchText = ""
    @State private var selectedCategory: CommandCategory? = nil
    @State private var draftLabel = ""
    @State private var draftCommand = ""
    @State private var draftCategory: CommandCategory = .custom
    @State private var editingSnippet: CommandSnippet? = nil

    private var filteredCommands: [CommandSnippet] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return appState.commandLibrary.filter { item in
            if let selectedCategory, item.category != selectedCategory {
                return false
            }
            if query.isEmpty { return true }
            return item.label.lowercased().contains(query)
                || item.command.lowercased().contains(query)
                || item.category.displayName.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Quick Add Form
            GroupBox("Add Custom Command to Library") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Label (e.g. Start API)", text: $draftLabel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)

                        Picker("", selection: $draftCategory) {
                            ForEach(CommandCategory.allCases) { cat in
                                Label(cat.displayName, systemImage: cat.symbolName).tag(cat)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 135)

                        Spacer()

                        Button {
                            submitNewCommand(insertImmediately: false)
                        } label: {
                            Label("Add to Library", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(draftCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if showInsertAction && appState.selectedPane != nil {
                            Button {
                                submitNewCommand(insertImmediately: true)
                            } label: {
                                Text("Add & Insert")
                            }
                            .buttonStyle(.bordered)
                            .disabled(draftCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    HStack(spacing: 6) {
                        Text("$")
                            .font(.system(.callout, design: .monospaced).bold())
                            .foregroundStyle(Color(hex: draftCategory.accentHex))
                        TextField("Shell command (e.g. docker compose up -d && npm run dev)", text: $draftCommand)
                            .font(.system(.callout, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                submitNewCommand(insertImmediately: false)
                            }
                    }
                }
                .padding(4)
            }

            // Search & Category Filter Row
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Search saved commands…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.callout)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .frame(width: 200)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        categoryChip(title: "All (\(appState.commandLibrary.count))", isSelected: selectedCategory == nil, tint: Color(hex: "#6366F1")) {
                            selectedCategory = nil
                        }
                        ForEach(CommandCategory.allCases) { cat in
                            let count = appState.commandLibrary.filter { $0.category == cat }.count
                            categoryChip(
                                title: count > 0 ? "\(cat.displayName) (\(count))" : cat.displayName,
                                isSelected: selectedCategory == cat,
                                tint: Color(hex: cat.accentHex)
                            ) {
                                selectedCategory = (selectedCategory == cat) ? nil : cat
                            }
                        }
                    }
                }
            }

            // Library List
            if filteredCommands.isEmpty {
                ContentUnavailableView {
                    Label("No Matching Commands", systemImage: "terminal")
                } description: {
                    Text("Add a custom command above or adjust your filter.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredCommands) { item in
                        commandRow(item)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.separator.opacity(0.6), lineWidth: 1)
                )
            }
        }
        .sheet(item: $editingSnippet) { snippet in
            EditCommandSnippetSheet(snippet: snippet) { updated in
                appState.updateCommandInLibrary(updated)
            }
        }
    }

    private func commandRow(_ item: CommandSnippet) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.category.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: item.category.accentHex))
                .frame(width: 24, height: 24)
                .background(Color(hex: item.category.accentHex).opacity(0.15), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.label)
                        .font(.callout.weight(.semibold))
                    PillBadge(text: item.category.displayName, tint: Color(hex: item.category.accentHex))
                }
                Text("$ \(item.command)")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 6)

            if showInsertAction && appState.selectedPane != nil {
                Button {
                    if let onInsert {
                        onInsert(item.command)
                    } else {
                        appState.insertCommandIntoSelectedPane(item.command)
                    }
                } label: {
                    Label("Insert", systemImage: "plus")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Append to selected pane")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.command, forType: .string)
                appState.showToast("Copied command", subtitle: item.label)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Copy command")

            Button {
                editingSnippet = item
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Edit command")

            Button(role: .destructive) {
                appState.deleteCommandFromLibrary(item)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove from library")
        }
        .padding(.vertical, 3)
    }

    private func categoryChip(title: String, isSelected: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(isSelected ? .semibold : .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .foregroundStyle(isSelected ? .white : .secondary)
                .background(isSelected ? tint : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func submitNewCommand(insertImmediately: Bool) {
        guard let created = appState.addCommandToLibrary(
            label: draftLabel,
            command: draftCommand,
            category: draftCategory
        ) else { return }

        if insertImmediately {
            if let onInsert {
                onInsert(created.command)
            } else {
                appState.insertCommandIntoSelectedPane(created.command)
            }
        }
        draftLabel = ""
        draftCommand = ""
    }
}

struct CommandLibrarySheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "#6366F1").opacity(0.20))
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color(hex: "#6366F1").opacity(0.45), lineWidth: 1)
                        )
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: "#818CF8"))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Command Library")
                        .font(.title3.bold())
                    Text("Save reusable shell commands and insert them into any pane in 1 click.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            CommandLibraryManagerView(showInsertAction: true)

            Divider()

            HStack {
                Button("Restore Defaults") {
                    appState.restoreBuiltInCommands()
                }
                .buttonStyle(.bordered)

                Button("Import JSON…") {
                    appState.importCommandsWithPanel()
                }
                .buttonStyle(.bordered)

                Button("Export JSON…") {
                    appState.exportCommandsWithPanel()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 660, idealWidth: 720, minHeight: 500, idealHeight: 560)
    }
}

private struct EditCommandSnippetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var snippet: CommandSnippet
    let onSave: (CommandSnippet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Saved Command")
                .font(.headline)

            Form {
                TextField("Label", text: $snippet.label)
                TextField("Command", text: $snippet.command)
                    .font(.system(.body, design: .monospaced))
                Picker("Category", selection: $snippet.category) {
                    ForEach(CommandCategory.allCases) { cat in
                        Label(cat.displayName, systemImage: cat.symbolName).tag(cat)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Changes") {
                    let trimmedCmd = snippet.command.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedCmd.isEmpty else { return }
                    var updated = snippet
                    updated.command = trimmedCmd
                    let trimmedLabel = snippet.label.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.label = trimmedLabel.isEmpty ? CommandSnippet.suggestedLabel(for: trimmedCmd) : trimmedLabel
                    onSave(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(snippet.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 440)
    }
}
