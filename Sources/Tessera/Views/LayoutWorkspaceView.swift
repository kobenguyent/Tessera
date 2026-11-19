import SwiftUI
import TesseraCore

struct LayoutWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    let layout: TesseraLayout
    @Binding var showingSidebar: Bool

    @State private var showingStylePopover = false
    @State private var showingSplitRatiosPopover = false
    @State private var showingInspector = true
    @State private var hoveredTabID: UUID?
    @Namespace private var modeNamespace

    var body: some View {
        VStack(spacing: 0) {
            // Unified Top Window Header Bar (flush with top edge at y=0, zero empty titlebar space)
            HStack(spacing: 10) {
                if !showingSidebar {
                    // Reserve space for macOS traffic lights when sidebar is collapsed
                    Spacer().frame(width: 66)

                    Button {
                        withAnimation(TesseraMotion.smooth) {
                            showingSidebar = true
                        }
                    } label: {
                        Image(systemName: "sidebar.leading")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 13, height: 13)
                    }
                    .buttonStyle(TesseraSoftButtonStyle(cornerRadius: 7, horizontalPadding: 6, verticalPadding: 4.5))
                    .help("Show Sidebar")
                }

                titleHeaderItem
                Spacer(minLength: 10)
                headerControlsCluster
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider().opacity(0.55)

            // Single Ultra-Slim Workspace Strip: Tabs + Structure + Ratios + Root CWD
            subToolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.28))

            Divider().opacity(0.55)

            // Main Interactive Studio Area: Visual Mosaic OR Live Script Editor
            ZStack {
                if appState.workspaceMode == .mosaic {
                    HStack(spacing: 0) {
                        VStack(spacing: 8) {
                            if let tab = appState.selectedTab {
                                MosaicCanvasView(layout: layout, tab: tab)
                                    .frame(minWidth: 420, minHeight: 320)
                            }

                            // Bottom Capability & Hint Strip
                            capabilityBar
                        }
                        .padding(12)
                        .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)

                        if showingInspector, let pane = appState.selectedPane {
                            Divider().opacity(0.55)
                            PaneInspectorView(layout: layout, pane: pane)
                                .frame(width: 315)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.992)))
                } else {
                    ScriptEditorView(layout: layout)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity.combined(with: .scale(scale: 0.992)))
                }
            }
            .animation(TesseraMotion.smooth, value: appState.workspaceMode)
            .animation(TesseraMotion.smooth, value: showingInspector)
        }
    }

    // MARK: - Top Header Items

    private var titleHeaderItem: some View {
        HStack(spacing: 9) {
            // Compact Icon + Accent Picker Button
            Button {
                showingStylePopover.toggle()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .fill(Color(hex: layout.accentHex).opacity(0.18))
                        .frame(width: 26, height: 26)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                                .strokeBorder(Color(hex: layout.accentHex).opacity(0.38), lineWidth: 0.75)
                        )
                    Image(systemName: layout.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: layout.accentHex))
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingStylePopover) {
                stylePickerPopover
            }
            .help("Customize icon & accent color")

            // Clean, Simple Editable Layout Title (unclipped)
            TextField("Layout Name", text: nameBinding)
                .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .textFieldStyle(.plain)
                .frame(minWidth: 120, maxWidth: 260)
        }
    }

    private var headerControlsCluster: some View {
        HStack(spacing: 7) {
            // Pin Toggle
            Button {
                withAnimation(TesseraMotion.press) {
                    appState.togglePin(layout)
                }
            } label: {
                Image(systemName: layout.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(layout.isPinned ? Color(hex: layout.accentHex) : .secondary)
                    .frame(width: 13, height: 13)
            }
            .buttonStyle(
                TesseraSoftButtonStyle(
                    tint: Color(hex: layout.accentHex),
                    isActive: layout.isPinned,
                    cornerRadius: 7,
                    horizontalPadding: 7,
                    verticalPadding: 5
                )
            )
            .help(layout.isPinned ? "Pinned to Menu Bar" : "Pin to Menu Bar")

            // Terminal Picker (Soft Dropdown)
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
                HStack(spacing: 5.5) {
                    Circle()
                        .fill(appState.isTerminalInstalled(effective) ? Color(hex: "#10B981") : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(effective.displayName)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(TesseraSoftButtonStyle(cornerRadius: 7, horizontalPadding: 9, verticalPadding: 4.5))
            .fixedSize()
            .help("Select target terminal emulator")

            // Window Bounds Picker (Soft Dropdown)
            Menu {
                ForEach(WindowFramePreset.allCases, id: \.self) { preset in
                    Button {
                        appState.mutateSelectedLayout { $0.windowFrame = preset }
                    } label: {
                        HStack {
                            Label(preset.displayName, systemImage: preset.symbolName)
                            if layout.windowFrame == preset {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(layout.windowFrame.displayName)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(TesseraSoftButtonStyle(cornerRadius: 7, horizontalPadding: 9, verticalPadding: 4.5))
            .fixedSize()
            .help("Window placement preset")

            // Mosaic / Live Script Editor Sliding Switcher
            let activeTerminal = appState.resolvedTerminal(for: layout)
            let hasLiveDraft = appState.hasUnsavedScriptDraft(for: layout, terminal: activeTerminal)
            let hasSavedCustom = layout.hasCustomScript(for: activeTerminal)

            HStack(spacing: 2) {
                ForEach(WorkspaceMode.allCases) { mode in
                    let selected = appState.workspaceMode == mode
                    Button {
                        withAnimation(TesseraMotion.smooth) {
                            appState.workspaceMode = mode
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(mode.label)
                                .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                            if mode == .script && (hasLiveDraft || hasSavedCustom) {
                                Circle()
                                    .fill(hasLiveDraft ? Color.orange : Color(hex: "#10B981"))
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(hex: layout.accentHex).opacity(0.22))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(Color(hex: layout.accentHex).opacity(0.38), lineWidth: 0.75)
                                    )
                                    .matchedGeometryEffect(id: "workspaceModePill", in: modeNamespace)
                            }
                        }
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
            )
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
                            .font(.system(size: 9.5))
                    }
                    Text(launchTitle)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .buttonStyle(
                TesseraProminentButtonStyle(
                    tint: hasLiveDraft ? Color.orange : Color(hex: layout.accentHex),
                    cornerRadius: 7,
                    horizontalPadding: 11,
                    verticalPadding: 4.5
                )
            )
            .disabled(appState.isLaunching)
            .fixedSize()
            .keyboardShortcut(.return, modifiers: .command)
            .help("Launch in \(activeTerminal.displayName) (⌘↩)")

            if appState.workspaceMode == .mosaic {
                Button {
                    withAnimation(TesseraMotion.smooth) {
                        showingInspector.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.trailing")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(showingInspector ? Color(hex: layout.accentHex) : .secondary)
                        .frame(width: 13, height: 13)
                }
                .buttonStyle(
                    TesseraSoftButtonStyle(
                        tint: Color(hex: layout.accentHex),
                        isActive: showingInspector,
                        cornerRadius: 7,
                        horizontalPadding: 7,
                        verticalPadding: 5
                    )
                )
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
                        let isHovered = hoveredTabID == tab.id
                        HStack(spacing: 5) {
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
                                    withAnimation(TesseraMotion.smooth) {
                                        appState.deleteTab(tab.id)
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    isSelected
                                        ? Color(hex: layout.accentHex).opacity(0.18)
                                        : Color.primary.opacity(isHovered ? 0.09 : 0.05)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    isSelected
                                        ? Color(hex: layout.accentHex).opacity(0.45)
                                        : Color.primary.opacity(isHovered ? 0.14 : 0.07),
                                    lineWidth: 1
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .animation(TesseraMotion.hover, value: isHovered)
                        .animation(TesseraMotion.smooth, value: isSelected)
                        .onHover { hovering in
                            hoveredTabID = hovering ? tab.id : (hoveredTabID == tab.id ? nil : hoveredTabID)
                        }
                        .onTapGesture {
                            withAnimation(TesseraMotion.smooth) {
                                appState.selectTab(tab.id)
                            }
                        }
                    }

                    Button {
                        withAnimation(TesseraMotion.smooth) {
                            appState.addTab()
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10.5, weight: .semibold))
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(TesseraSoftButtonStyle(cornerRadius: 8, horizontalPadding: 6, verticalPadding: 5))
                    .help("Add a new tab to this mosaic")
                }
            }

            Divider().frame(height: 16).opacity(0.6)

            // Quick Structure Presets (Soft Dropdown)
            Menu {
                ForEach(MosaicStructureTemplate.allCases) { template in
                    Button {
                        withAnimation(TesseraMotion.smooth) {
                            appState.applyTemplate(template)
                        }
                    } label: {
                        Label(template.displayName, systemImage: template.symbolName)
                    }
                }
            } label: {
                HStack(spacing: 5.5) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Structure")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(TesseraSoftButtonStyle(cornerRadius: 8, horizontalPadding: 10, verticalPadding: 5))
            .fixedSize()
            .help("Apply a pre-defined pane grid template (preserves your pane commands)")

            // Fine-tune split ratios popover
            if let tab = appState.selectedTab, !tab.root.allSplits.isEmpty {
                Button {
                    showingSplitRatiosPopover.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.below.rectangle")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(showingSplitRatiosPopover ? Color(hex: layout.accentHex) : .secondary)
                        Text("Ratios")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(
                    TesseraSoftButtonStyle(
                        tint: Color(hex: layout.accentHex),
                        isActive: showingSplitRatiosPopover,
                        cornerRadius: 8,
                        horizontalPadding: 10,
                        verticalPadding: 5
                    )
                )
                .fixedSize()
                .popover(isPresented: $showingSplitRatiosPopover) {
                    splitRatiosPopover(splits: tab.root.allSplits)
                }
            }

            Spacer(minLength: 6)

            // Root Working Directory
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    TextField("~", text: rootDirectoryBinding)
                        .font(.system(size: 11.5, design: .monospaced))
                        .textFieldStyle(.plain)
                        .frame(minWidth: 100, idealWidth: 135, maxWidth: 165)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                )

                Button {
                    if let dir = appState.pickDirectory(initialPath: layout.workingDirectory) {
                        appState.mutateSelectedLayout { $0.workingDirectory = dir }
                    }
                } label: {
                    Text("Browse")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(TesseraSoftButtonStyle(cornerRadius: 8, horizontalPadding: 9, verticalPadding: 5))
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
                tint: Color(hex: layout.accentHex)
            )
            if caps.nativeSplits {
                PillBadge(text: "Native Splits", tint: Color(hex: "#10B981"))
            } else {
                PillBadge(text: "Geometric Tiling", tint: .orange)
            }
            if caps.nativeTabs {
                PillBadge(text: "Multi-Tab", tint: Color(hex: "#0EA5E9"))
            }
            if appState.hasUnsavedScriptDraft(for: layout, terminal: terminal) {
                Button {
                    appState.workspaceMode = .script
                } label: {
                    PillBadge(text: "Unsaved Draft", tint: .orange)
                }
                .buttonStyle(.plain)
            } else if layout.hasCustomScript(for: terminal) {
                Button {
                    appState.workspaceMode = .script
                } label: {
                    PillBadge(text: "Custom Script", tint: Color(hex: "#10B981"))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            Text("Type commands directly in any pane · ⌘↩ Launch")
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
