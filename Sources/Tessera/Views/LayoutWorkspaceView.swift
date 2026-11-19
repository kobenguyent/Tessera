import SwiftUI
import TesseraCore

struct LayoutWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    let layout: TesseraLayout

    @State private var showingStylePopover = false
    @State private var showingSplitRatiosPopover = false
    @State private var showingInspector = true

    var body: some View {
        VStack(spacing: 0) {
            // Top Studio Header
            headerBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Secondary Bar: Tabs + Structure Templates + Working Directory
            subToolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))

            Divider()

            // Main Interactive Studio Area: Visual Mosaic OR Live Script Editor
            if appState.workspaceMode == .mosaic {
                HStack(spacing: 0) {
                    VStack(spacing: 10) {
                        if let tab = appState.selectedTab {
                            MosaicCanvasView(layout: layout, tab: tab)
                                .frame(minWidth: 420, minHeight: 320)
                        }

                        // Bottom Capability & Hint Strip
                        capabilityBar
                    }
                    .padding(16)
                    .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)

                    if showingInspector, let pane = appState.selectedPane {
                        Divider()
                        PaneInspectorView(layout: layout, pane: pane)
                            .frame(width: 325)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            } else {
                ScriptEditorView(layout: layout)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 10) {
            // Icon + Accent Picker Button
            Button {
                showingStylePopover.toggle()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: layout.accentHex).opacity(0.18))
                        .frame(width: 38, height: 38)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color(hex: layout.accentHex).opacity(0.38), lineWidth: 1)
                        )
                    Image(systemName: layout.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: layout.accentHex))
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingStylePopover) {
                stylePickerPopover
            }
            .help("Customize icon & accent color")

            // Inline Editable Title + Subtitle
            VStack(alignment: .leading, spacing: 2) {
                TextField("Layout Name", text: nameBinding)
                    .font(.system(size: 16.5, weight: .bold, design: .rounded))
                    .textFieldStyle(.plain)
                TextField("Add a short description…", text: subtitleBinding)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textFieldStyle(.plain)
            }
            .frame(minWidth: 130, maxWidth: 280, alignment: .leading)

            Spacer(minLength: 6)

            // Pin Toggle
            Button {
                appState.togglePin(layout)
            } label: {
                Image(systemName: layout.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(layout.isPinned ? Color(hex: layout.accentHex) : .secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(layout.isPinned ? "Pinned to Menu Bar" : "Pin to Menu Bar")

            // Terminal Picker
            Menu {
                Button {
                    appState.mutateSelectedLayout { $0.preferredTerminal = nil }
                } label: {
                    Label(
                        "App Default (\(appState.settings.defaultTerminal.displayName))",
                        systemImage: layout.preferredTerminal == nil ? "checkmark" : "circle"
                    )
                }
                Divider()
                ForEach(TerminalKind.allCases) { kind in
                    let installed = appState.isTerminalInstalled(kind)
                    Button {
                        appState.mutateSelectedLayout { $0.preferredTerminal = kind }
                    } label: {
                        HStack {
                            Text(installed ? "\(kind.displayName)" : "\(kind.displayName) (Not installed)")
                            if layout.preferredTerminal == kind {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let effective = appState.resolvedTerminal(for: layout)
                HStack(spacing: 5) {
                    Circle()
                        .fill(appState.isTerminalInstalled(effective) ? Color(hex: "#10B981") : Color.orange)
                        .frame(width: 6.5, height: 6.5)
                    Text(effective.displayName)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
            }
            .menuStyle(.borderedButton)
            .controlSize(.small)
            .fixedSize()
            .help("Select target terminal emulator")

            // Window Bounds Picker
            Picker("", selection: windowFrameBinding) {
                ForEach(WindowFramePreset.allCases, id: \.self) { preset in
                    Label(preset.displayName, systemImage: preset.symbolName).tag(preset)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 126)
            .help("Window placement preset")

            // Mosaic / Live Script Editor Switcher
            let activeTerminal = appState.resolvedTerminal(for: layout)
            let hasLiveDraft = appState.hasUnsavedScriptDraft(for: layout, terminal: activeTerminal)
            let hasSavedCustom = layout.hasCustomScript(for: activeTerminal)

            HStack(spacing: 2) {
                ForEach(WorkspaceMode.allCases) { mode in
                    let selected = appState.workspaceMode == mode
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            appState.workspaceMode = mode
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.symbolName)
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(mode.label)
                                .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                            if mode == .script && (hasLiveDraft || hasSavedCustom) {
                                Circle()
                                    .fill(hasLiveDraft ? Color.orange : Color(hex: "#10B981"))
                                    .frame(width: 5.5, height: 5.5)
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            selected ? Color(hex: layout.accentHex).opacity(0.22) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2.5)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .fixedSize()
            .help("Switch between Visual Mosaic and Live Script Editor (⇧⌘I)")

            // Primary Launch Button
            let launchTitle: String = {
                if hasLiveDraft { return "Run Script" }
                if hasSavedCustom { return "Run Custom" }
                return "Launch"
            }()

            Button {
                appState.launch(layout: layout)
            } label: {
                HStack(spacing: 5) {
                    if appState.isLaunching {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10.5))
                    }
                    Text(launchTitle)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 5)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(hasLiveDraft ? Color.orange : Color(hex: layout.accentHex))
            .disabled(appState.isLaunching)
            .fixedSize()
            .keyboardShortcut(.return, modifiers: .command)
            .help("Launch in \(activeTerminal.displayName) (⌘↩)")

            if appState.workspaceMode == .mosaic {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showingInspector.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.trailing")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(showingInspector ? Color(hex: layout.accentHex) : .secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(showingInspector ? "Hide Pane Inspector" : "Show Pane Inspector")
            }
        }
    }

    // MARK: - Sub-Toolbar (Tabs, Templates, Root CWD)

    private var subToolbar: some View {
        HStack(spacing: 10) {
            // Tabs Strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(layout.tabs) { tab in
                        let isSelected = appState.selectedTab?.id == tab.id
                        HStack(spacing: 5) {
                            Image(systemName: "macwindow")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(isSelected ? Color(hex: layout.accentHex) : .secondary)
                            if isSelected {
                                TextField("Tab", text: tabTitleBinding(tabID: tab.id))
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(minWidth: 44, maxWidth: 105)
                            } else {
                                Text(tab.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                            }
                            if layout.tabs.count > 1 && isSelected {
                                Button {
                                    appState.deleteTab(tab.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4.5)
                        .background(
                            isSelected ? Color(hex: layout.accentHex).opacity(0.18) : Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(isSelected ? Color(hex: layout.accentHex).opacity(0.45) : .clear, lineWidth: 1)
                        )
                        .onTapGesture {
                            appState.selectTab(tab.id)
                        }
                    }

                    Button {
                        appState.addTab()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10.5, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Add a new tab to this mosaic")
                }
            }

            Divider().frame(height: 16)

            // Quick Structure Presets
            Menu {
                ForEach(MosaicStructureTemplate.allCases) { template in
                    Button {
                        appState.applyTemplate(template)
                    } label: {
                        Label(template.displayName, systemImage: template.symbolName)
                    }
                }
            } label: {
                Label("Structure", systemImage: "square.grid.2x2")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderedButton)
            .controlSize(.small)
            .fixedSize()
            .help("Apply a pre-defined pane grid template (preserves your pane commands)")

            // Fine-tune split ratios popover
            if let tab = appState.selectedTab, !tab.root.allSplits.isEmpty {
                Button {
                    showingSplitRatiosPopover.toggle()
                } label: {
                    Label("Ratios", systemImage: "slider.horizontal.below.rectangle")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                .popover(isPresented: $showingSplitRatiosPopover) {
                    splitRatiosPopover(splits: tab.root.allSplits)
                }
            }

            Spacer(minLength: 6)

            // Root Working Directory
            HStack(spacing: 5) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("~", text: rootDirectoryBinding)
                    .font(.system(size: 11.5, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(minWidth: 110, idealWidth: 145, maxWidth: 170)
                Button {
                    if let dir = appState.pickDirectory(initialPath: layout.workingDirectory) {
                        appState.mutateSelectedLayout { $0.workingDirectory = dir }
                    }
                } label: {
                    Text("Browse")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
            }
        }
    }

    // MARK: - Bottom Capability Strip

    private var capabilityBar: some View {
        let terminal = appState.resolvedTerminal(for: layout)
        let caps = terminal.capabilities
        return HStack(spacing: 8) {
            PillBadge(
                text: caps.orchestrationMethod,
                systemImage: terminal.symbolName,
                tint: Color(hex: layout.accentHex)
            )
            if caps.nativeSplits {
                PillBadge(text: "Native Splits", systemImage: "checkmark.circle.fill", tint: Color(hex: "#10B981"))
            } else {
                PillBadge(text: "Geometric Tiling", systemImage: "rectangle.3.group", tint: .orange)
            }
            if caps.nativeTabs {
                PillBadge(text: "Multi-Tab", systemImage: "macwindow.on.rectangle", tint: Color(hex: "#0EA5E9"))
            }
            if appState.hasUnsavedScriptDraft(for: layout, terminal: terminal) {
                Button {
                    appState.workspaceMode = .script
                } label: {
                    PillBadge(text: "Unsaved Draft", systemImage: "pencil.circle.fill", tint: .orange)
                }
                .buttonStyle(.plain)
            } else if layout.hasCustomScript(for: terminal) {
                Button {
                    appState.workspaceMode = .script
                } label: {
                    PillBadge(text: "Custom Script", systemImage: "chevron.left.forwardslash.chevron.right", tint: Color(hex: "#10B981"))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            Text("Click any pane to configure · Switch to Script to edit code live")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - Popovers

    private var stylePickerPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Accent Color")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(TesseraPalette.accents, id: \.hex) { accent in
                    Button {
                        appState.mutateSelectedLayout { $0.accentHex = accent.hex }
                    } label: {
                        Circle()
                            .fill(Color(hex: accent.hex))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .strokeBorder(.white, lineWidth: layout.accentHex == accent.hex ? 2.5 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(accent.name)
                }
            }

            Divider()

            Text("Mosaic Icon")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 6), count: 7), spacing: 6) {
                ForEach(TesseraPalette.icons, id: \.self) { symbol in
                    Button {
                        appState.mutateSelectedLayout { $0.icon = symbol }
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 14))
                            .frame(width: 30, height: 30)
                            .background(
                                layout.icon == symbol ? Color(hex: layout.accentHex).opacity(0.22) : Color.secondary.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .foregroundStyle(layout.icon == symbol ? Color(hex: layout.accentHex) : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
    }

    private func splitRatiosPopover(splits: [SplitSpec]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Split Proportions")
                .font(.headline)
            ForEach(Array(splits.enumerated()), id: \.element.id) { idx, split in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Split \(idx + 1) · \(split.direction.shortLabel)", systemImage: split.direction.symbolName)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text("\(Int((split.ratio * 100).rounded()))% / \(Int(((1 - split.ratio) * 100).rounded()))%")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Button {
                            appState.toggleSplitDirection(splitID: split.id)
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Flip split orientation")
                    }
                    Slider(
                        value: Binding(
                            get: { split.ratio },
                            set: { appState.updateSplitRatio(splitID: split.id, ratio: $0) }
                        ),
                        in: 0.15...0.85,
                        step: 0.01
                    )
                }
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: - Bindings

    private var nameBinding: Binding<String> {
        Binding(
            get: { layout.name },
            set: { val in appState.mutateSelectedLayout { $0.name = val } }
        )
    }

    private var subtitleBinding: Binding<String> {
        Binding(
            get: { layout.subtitle },
            set: { val in appState.mutateSelectedLayout { $0.subtitle = val } }
        )
    }

    private var rootDirectoryBinding: Binding<String> {
        Binding(
            get: { layout.workingDirectory },
            set: { val in appState.mutateSelectedLayout { $0.workingDirectory = val } }
        )
    }

    private var windowFrameBinding: Binding<WindowFramePreset> {
        Binding(
            get: { layout.windowFrame },
            set: { val in appState.mutateSelectedLayout { $0.windowFrame = val } }
        )
    }

    private func tabTitleBinding(tabID: UUID) -> Binding<String> {
        Binding(
            get: { layout.tabs.first(where: { $0.id == tabID })?.title ?? "" },
            set: { val in
                appState.mutateSelectedLayout { layout in
                    if let idx = layout.tabs.firstIndex(where: { $0.id == tabID }) {
                        layout.tabs[idx].title = val
                    }
                }
            }
        )
    }
}
