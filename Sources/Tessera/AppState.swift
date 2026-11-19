import AppKit
import Foundation
import SwiftUI
import TesseraCore
import UniformTypeIdentifiers

enum UpdateUIState: Equatable {
    case idle
    case checking
    case upToDate(current: SemanticVersion, latest: SemanticVersion?, checkedAt: Date)
    case updateAvailable(UpdateRelease)
    case downloading(progress: Double, assetName: String, release: UpdateRelease)
    case installing(DownloadedUpdate)
    case readyToInstall(DownloadedUpdate)
    case failed(String)

    var availableRelease: UpdateRelease? {
        switch self {
        case .updateAvailable(let release): return release
        case .downloading(_, _, let release): return release
        case .installing(let downloaded): return downloaded.release
        case .readyToInstall(let downloaded): return downloaded.release
        default: return nil
        }
    }

    var hasActionableUpdate: Bool {
        switch self {
        case .updateAvailable, .downloading, .installing, .readyToInstall:
            return true
        default:
            return false
        }
    }
}

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case mosaic
    case script

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mosaic: return "Mosaic"
        case .script: return "Script"
        }
    }

    var symbolName: String {
        switch self {
        case .mosaic: return "square.grid.2x2"
        case .script: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct ScriptDraftKey: Hashable {
    let layoutID: UUID
    let terminal: TerminalKind
}

@MainActor
final class AppState: ObservableObject {
    @Published var layouts: [TesseraLayout] = []
    @Published var selectedLayoutID: UUID?
    @Published var selectedTabID: UUID?
    @Published var selectedPaneID: UUID?
    @Published var workspaceMode: WorkspaceMode = .mosaic
    @Published var liveScriptDrafts: [ScriptDraftKey: String] = [:]

    @Published var settings: AppSettings
    @Published var detectedTerminals: [DetectedTerminal] = []
    @Published var menuBarTerminalOverride: TerminalKind?

    @Published var isLaunching = false
    @Published var toast: ToastMessage?

    @Published var updateState: UpdateUIState = .idle
    @Published var showingUpdateSheet = false
    @Published var cliInstallStatus: String?

    private let layoutStore: LayoutStore
    private let settingsStore: SettingsStore
    private let detector: TerminalDetector
    private let launcher: TerminalLauncher
    private let updateService: UpdateService
    private var periodicUpdateTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?

    init(
        layoutStore: LayoutStore = LayoutStore(),
        settingsStore: SettingsStore = SettingsStore(),
        detector: TerminalDetector = TerminalDetector(),
        launcher: TerminalLauncher = TerminalLauncher(),
        updateService: UpdateService = UpdateService()
    ) {
        self.layoutStore = layoutStore
        self.settingsStore = settingsStore
        self.detector = detector
        self.launcher = launcher
        self.updateService = updateService
        self.settings = settingsStore.load(detector: detector)

        refreshTerminals()
        loadLayouts()
        startAutoUpdateScheduler()
    }

    deinit {
        periodicUpdateTask?.cancel()
        toastDismissTask?.cancel()
    }

    // MARK: - Derived Selections

    var selectedLayoutIndex: Int? {
        guard let selectedLayoutID else { return nil }
        return layouts.firstIndex(where: { $0.id == selectedLayoutID })
    }

    var selectedLayout: TesseraLayout? {
        guard let idx = selectedLayoutIndex else { return nil }
        return layouts[idx]
    }

    var selectedTabIndex: Int? {
        guard let layout = selectedLayout else { return nil }
        if let selectedTabID, let idx = layout.tabs.firstIndex(where: { $0.id == selectedTabID }) {
            return idx
        }
        return layout.tabs.isEmpty ? nil : 0
    }

    var selectedTab: TesseraTab? {
        guard let layout = selectedLayout, let tabIdx = selectedTabIndex else { return nil }
        return layout.tabs[tabIdx]
    }

    var selectedPane: PaneSpec? {
        guard let tab = selectedTab else { return nil }
        if let selectedPaneID, let found = tab.root.leaf(withID: selectedPaneID) {
            return found
        }
        return tab.root.firstLeaf
    }

    var pinnedLayouts: [TesseraLayout] {
        layouts.filter(\.isPinned)
    }

    var installedTerminals: [DetectedTerminal] {
        detectedTerminals.filter(\.isInstalled)
    }

    // MARK: - Persistence & Initialization

    func loadLayouts() {
        do {
            layouts = try layoutStore.loadLayouts()
        } catch {
            layouts = BuiltInPresets.makeDefaultLayouts()
            showToast("Loaded built-in presets", subtitle: error.localizedDescription, isError: true)
        }
        selectLayout(layouts.first?.id)
    }

    func saveLayouts() {
        do {
            try layoutStore.saveLayouts(layouts)
        } catch {
            showToast("Failed to save layouts", subtitle: error.localizedDescription, isError: true)
        }
    }

    func saveSettings() {
        do {
            try settingsStore.save(settings)
        } catch {
            showToast("Failed to save settings", subtitle: error.localizedDescription, isError: true)
        }
    }

    func refreshTerminals() {
        detectedTerminals = detector.detectAll()
    }

    func isTerminalInstalled(_ kind: TerminalKind) -> Bool {
        detectedTerminals.first(where: { $0.kind == kind })?.isInstalled ?? false
    }

    // MARK: - Selection Helpers

    func selectLayout(_ id: UUID?) {
        selectedLayoutID = id
        if let layout = selectedLayout {
            selectedTabID = layout.tabs.first?.id
            selectedPaneID = layout.tabs.first?.root.focusedLeafID ?? layout.tabs.first?.root.firstLeaf.id
        } else {
            selectedTabID = nil
            selectedPaneID = nil
        }
    }

    func selectTab(_ id: UUID) {
        selectedTabID = id
        if let tab = selectedTab {
            selectedPaneID = tab.root.focusedLeafID ?? tab.root.firstLeaf.id
        }
    }

    // MARK: - Layout Mutations

    func createNewLayout(template: MosaicStructureTemplate = .mainAndStackedSide) {
        let count = layouts.count + 1
        let color = TesseraPalette.accents[count % TesseraPalette.accents.count].hex
        let newLayout = TesseraLayout(
            name: "Custom Mosaic \(count)",
            subtitle: "Pre-defined split-pane terminal workflow",
            icon: "square.grid.2x2.fill",
            accentHex: color,
            workingDirectory: "~",
            windowFrame: .centeredLarge,
            tabs: [TesseraTab(title: "Workspace", root: template.makeTree())],
            tags: ["custom"],
            isPinned: false,
            isBuiltIn: false
        )
        layouts.insert(newLayout, at: 0)
        saveLayouts()
        selectLayout(newLayout.id)
    }

    func duplicateLayout(_ layout: TesseraLayout) {
        let copy = layout.duplicated()
        if let idx = layouts.firstIndex(where: { $0.id == layout.id }) {
            layouts.insert(copy, at: idx + 1)
        } else {
            layouts.append(copy)
        }
        saveLayouts()
        selectLayout(copy.id)
        showToast("Duplicated \"\(layout.name)\"")
    }

    func deleteLayout(_ layout: TesseraLayout) {
        layouts.removeAll(where: { $0.id == layout.id })
        liveScriptDrafts = liveScriptDrafts.filter { $0.key.layoutID != layout.id }
        saveLayouts()
        if selectedLayoutID == layout.id {
            selectLayout(layouts.first?.id)
        }
        showToast("Deleted \"\(layout.name)\"")
    }

    func togglePin(_ layout: TesseraLayout) {
        guard let idx = layouts.firstIndex(where: { $0.id == layout.id }) else { return }
        layouts[idx].isPinned.toggle()
        layouts[idx].updatedAt = Date()
        saveLayouts()
    }

    func restoreBuiltInPresets() {
        let defaults = BuiltInPresets.makeDefaultLayouts()
        for preset in defaults {
            if !layouts.contains(where: { $0.id == preset.id }) {
                layouts.append(preset)
            }
        }
        saveLayouts()
        if selectedLayoutID == nil {
            selectLayout(layouts.first?.id)
        }
        showToast("Restored built-in presets")
    }

    func mutateSelectedLayout(_ transform: (inout TesseraLayout) -> Void) {
        guard let idx = selectedLayoutIndex else { return }
        transform(&layouts[idx])
        layouts[idx].updatedAt = Date()
        saveLayouts()
    }

    func mutateSelectedTab(_ transform: (inout TesseraTab) -> Void) {
        guard let layoutIdx = selectedLayoutIndex,
              let tabIdx = selectedTabIndex else { return }
        transform(&layouts[layoutIdx].tabs[tabIdx])
        layouts[layoutIdx].updatedAt = Date()
        saveLayouts()
    }

    // MARK: - Tab & Pane Operations

    func addTab() {
        let newPane = PaneSpec(title: "Shell", focus: true)
        let tabNumber = (selectedLayout?.tabs.count ?? 0) + 1
        let newTab = TesseraTab(title: "Tab \(tabNumber)", root: .leaf(newPane))
        mutateSelectedLayout { layout in
            layout.tabs.append(newTab)
        }
        selectedTabID = newTab.id
        selectedPaneID = newPane.id
    }

    func deleteTab(_ tabID: UUID) {
        guard let layout = selectedLayout, layout.tabs.count > 1 else { return }
        mutateSelectedLayout { layout in
            layout.tabs.removeAll(where: { $0.id == tabID })
        }
        if selectedTabID == tabID {
            selectedTabID = selectedLayout?.tabs.first?.id
            selectedPaneID = selectedTab?.root.firstLeaf.id
        }
    }

    func applyTemplate(_ template: MosaicStructureTemplate) {
        let existingPanes = selectedTab?.root.allLeaves ?? []
        let newTree = template.makeTree(preserving: existingPanes)
        mutateSelectedTab { tab in
            tab.root = newTree
        }
        selectedPaneID = newTree.focusedLeafID ?? newTree.firstLeaf.id
    }

    func splitPane(_ paneID: UUID, direction: SplitDirection) {
        let nextNumber = (selectedTab?.root.leafCount ?? 1) + 1
        let newPane = PaneSpec(title: "Pane \(nextNumber)")
        mutateSelectedTab { tab in
            tab.root = tab.root.splitting(leafID: paneID, direction: direction, ratio: 0.5, newPane: newPane)
        }
        selectedPaneID = newPane.id
    }

    func removePane(_ paneID: UUID) {
        guard let tab = selectedTab, tab.root.leafCount > 1 else { return }
        mutateSelectedTab { tab in
            if let collapsed = tab.root.removing(leafID: paneID) {
                tab.root = collapsed
            }
        }
        if selectedPaneID == paneID {
            selectedPaneID = selectedTab?.root.firstLeaf.id
        }
    }

    func updatePane(_ paneID: UUID, transform: (inout PaneSpec) -> Void) {
        mutateSelectedTab { tab in
            tab.root = tab.root.updating(leafID: paneID, transform: transform)
        }
    }

    func setFocusedPane(_ paneID: UUID) {
        mutateSelectedTab { tab in
            tab.root = tab.root.settingFocus(leafID: paneID)
        }
    }

    func updateSplitRatio(splitID: UUID, ratio: Double) {
        mutateSelectedTab { tab in
            tab.root = tab.root.updatingRatio(splitID: splitID, ratio: ratio)
        }
    }

    func toggleSplitDirection(splitID: UUID) {
        mutateSelectedTab { tab in
            tab.root = tab.root.togglingSplitDirection(splitID: splitID)
        }
    }

    // MARK: - Launching & Live Script Editor

    func resolvedTerminal(for layout: TesseraLayout, override: TerminalKind? = nil) -> TerminalKind {
        override ?? layout.preferredTerminal ?? settings.defaultTerminal
    }

    func makeLaunchPlan(
        for layout: TesseraLayout,
        terminalOverride: TerminalKind? = nil,
        includeLiveDraft: Bool = true,
        ignoreCustomScript: Bool = false
    ) -> LaunchPlan {
        let terminal = resolvedTerminal(for: layout, override: terminalOverride)
        let hostForTmux: TerminalKind = isTerminalInstalled(.iterm2) ? .iterm2 : .appleTerminal
        let context = LaunchContext(
            screenBounds: currentVisibleScreenBounds(),
            homeDirectory: NSHomeDirectory(),
            hostTerminalForTmux: hostForTmux
        )
        let basePlan = LaunchPlanBuilder.build(
            layout: layout,
            terminal: terminal,
            context: context,
            ignoreCustomScript: ignoreCustomScript
        )

        if includeLiveDraft, !ignoreCustomScript,
           let draft = liveScriptDrafts[ScriptDraftKey(layoutID: layout.id, terminal: terminal)] {
            return basePlan.withCustomContent(draft, isCustomScript: true)
        }
        return basePlan
    }

    func effectiveScriptText(for layout: TesseraLayout, terminal: TerminalKind) -> String {
        let key = ScriptDraftKey(layoutID: layout.id, terminal: terminal)
        if let draft = liveScriptDrafts[key] {
            return draft
        }
        return makeLaunchPlan(for: layout, terminalOverride: terminal, includeLiveDraft: false).previewContent
    }

    func hasUnsavedScriptDraft(for layout: TesseraLayout, terminal: TerminalKind) -> Bool {
        liveScriptDrafts[ScriptDraftKey(layoutID: layout.id, terminal: terminal)] != nil
    }

    func setLiveScriptDraft(_ text: String, for layout: TesseraLayout, terminal: TerminalKind) {
        let key = ScriptDraftKey(layoutID: layout.id, terminal: terminal)
        let persistedBaseline = makeLaunchPlan(
            for: layout,
            terminalOverride: terminal,
            includeLiveDraft: false
        ).previewContent

        if text == persistedBaseline {
            liveScriptDrafts.removeValue(forKey: key)
        } else {
            liveScriptDrafts[key] = text
        }
    }

    func saveLiveScriptOverride(for layout: TesseraLayout, terminal: TerminalKind) {
        let key = ScriptDraftKey(layoutID: layout.id, terminal: terminal)
        let currentText = effectiveScriptText(for: layout, terminal: terminal)
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showToast("Cannot Save Empty Script", subtitle: "Add script content or reset to generated.", isError: true)
            return
        }

        let generatedText = makeLaunchPlan(
            for: layout,
            terminalOverride: terminal,
            includeLiveDraft: false,
            ignoreCustomScript: true
        ).previewContent

        guard let idx = layouts.firstIndex(where: { $0.id == layout.id }) else { return }
        if currentText == generatedText {
            layouts[idx].setCustomScript(nil, for: terminal)
            liveScriptDrafts.removeValue(forKey: key)
            layouts[idx].updatedAt = Date()
            saveLayouts()
            showToast("Using Auto-Generated Script", subtitle: "\(terminal.displayName) matches visual mosaic")
        } else {
            layouts[idx].setCustomScript(currentText, for: terminal)
            liveScriptDrafts.removeValue(forKey: key)
            layouts[idx].updatedAt = Date()
            saveLayouts()
            showToast("Saved Custom Script", subtitle: "\(layout.name) · \(terminal.displayName)")
        }
    }

    func resetScriptToGenerated(for layout: TesseraLayout, terminal: TerminalKind) {
        let key = ScriptDraftKey(layoutID: layout.id, terminal: terminal)
        liveScriptDrafts.removeValue(forKey: key)
        if let idx = layouts.firstIndex(where: { $0.id == layout.id }),
           layouts[idx].hasCustomScript(for: terminal) {
            layouts[idx].setCustomScript(nil, for: terminal)
            layouts[idx].updatedAt = Date()
            saveLayouts()
        }
        showToast("Regenerated from Mosaic", subtitle: "\(terminal.displayName) reset to auto-generated script")
    }

    func discardLiveScriptDraft(for layout: TesseraLayout, terminal: TerminalKind) {
        liveScriptDrafts.removeValue(forKey: ScriptDraftKey(layoutID: layout.id, terminal: terminal))
    }

    func openScriptEditor(for layout: TesseraLayout) {
        if selectedLayoutID != layout.id {
            selectLayout(layout.id)
        }
        workspaceMode = .script
    }

    func launch(layout: TesseraLayout, terminalOverride: TerminalKind? = nil) {
        let plan = makeLaunchPlan(for: layout, terminalOverride: terminalOverride, includeLiveDraft: true)
        launch(plan: plan, paneCount: layout.totalPaneCount)
    }

    func launch(plan: LaunchPlan, paneCount: Int? = nil) {
        guard !plan.previewContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showToast("Script is Empty", subtitle: "Add commands or reset to generated before launching.", isError: true)
            return
        }
        isLaunching = true
        Task {
            let result = await launcher.execute(plan)
            isLaunching = false
            if result.succeeded {
                let detail: String
                if plan.isCustomScript {
                    detail = "in \(plan.terminal.displayName) · custom script"
                } else if let paneCount {
                    detail = "in \(plan.terminal.displayName) · \(paneCount) pane(s)"
                } else {
                    detail = "in \(plan.terminal.displayName)"
                }
                showToast("Launched \"\(plan.layoutName)\"", subtitle: detail)
            } else {
                showToast(
                    "Launch Failed (\(plan.terminal.displayName))",
                    subtitle: result.message,
                    isError: true
                )
            }
        }
    }

    private func currentVisibleScreenBounds() -> TesseraRect {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return TesseraRect(x: 0, y: 25, width: 1512, height: 957)
        }
        let fullHeight = screen.frame.height
        let visible = screen.visibleFrame
        // Convert AppKit bottom-left origin to AppleScript/Quartz top-left origin
        let topY = fullHeight - (visible.origin.y + visible.height)
        return TesseraRect(
            x: Double(visible.origin.x),
            y: Double(max(25, topY)),
            width: Double(visible.width),
            height: Double(visible.height)
        )
    }

    // MARK: - Import / Export

    func exportLayoutsWithPanel() {
        let panel = NSSavePanel()
        panel.title = "Export Tessera Layouts"
        panel.nameFieldStringValue = "tessera-layouts.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try layoutStore.exportJSON(layouts: layouts)
            try data.write(to: url, options: .atomic)
            showToast("Exported \(layouts.count) layouts", subtitle: url.lastPathComponent)
        } catch {
            showToast("Export Failed", subtitle: error.localizedDescription, isError: true)
        }
    }

    func importLayoutsWithPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Tessera Layouts"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let imported = try layoutStore.importJSON(from: data)
            for item in imported {
                if let idx = layouts.firstIndex(where: { $0.id == item.id }) {
                    layouts[idx] = item
                } else {
                    layouts.insert(item, at: 0)
                }
            }
            saveLayouts()
            if let first = imported.first {
                selectLayout(first.id)
            }
            showToast("Imported \(imported.count) layout(s)")
        } catch {
            showToast("Import Failed", subtitle: error.localizedDescription, isError: true)
        }
    }

    func pickDirectory(initialPath: String?) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Directory"
        if let initialPath {
            let expanded = CommandFormatter.expandTilde(initialPath)
            panel.directoryURL = URL(fileURLWithPath: expanded)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let home = NSHomeDirectory()
        if url.path == home { return "~" }
        if url.path.hasPrefix(home + "/") {
            return "~" + url.path.dropFirst(home.count)
        }
        return url.path
    }

    // MARK: - Auto-Update Checking (GitHub Releases)

    private func startAutoUpdateScheduler() {
        periodicUpdateTask?.cancel()
        periodicUpdateTask = Task { [weak self] in
            guard let self else { return }
            // Initial gentle delay on launch so UI settles immediately
            try? await Task.sleep(for: .seconds(3))
            if self.settings.shouldRunScheduledUpdateCheck() {
                await self.checkForUpdates(userInitiated: false)
            }
            // Periodic check while app lives in Menu Bar
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6 * 3600))
                if self.settings.shouldRunScheduledUpdateCheck() {
                    await self.checkForUpdates(userInitiated: false)
                }
            }
        }
    }

    func checkForUpdates(userInitiated: Bool) async {
        updateState = .checking
        let repo = settings.githubRepository
        let current = TesseraMetadata.currentVersion

        do {
            let outcome = try await updateService.checkForUpdates(
                repository: repo,
                currentVersion: current,
                includePrereleases: settings.includePrereleases,
                skippedVersion: settings.skippedVersion,
                ignoreSkipped: userInitiated
            )

            settings.lastUpdateCheckDate = Date()
            saveSettings()

            switch outcome {
            case .upToDate(let cur, let latest):
                updateState = .upToDate(current: cur, latest: latest, checkedAt: Date())
                if userInitiated {
                    showToast("Tessera is up to date", subtitle: "Version \(cur.tagString)")
                }
            case .skipped(let release):
                updateState = .upToDate(current: current, latest: release.version, checkedAt: Date())
            case .updateAvailable(let release):
                updateState = .updateAvailable(release)
                if userInitiated {
                    showingUpdateSheet = true
                }
            }
        } catch {
            updateState = .failed(error.localizedDescription)
            if userInitiated {
                showToast("Update Check Failed", subtitle: error.localizedDescription, isError: true)
            }
        }
    }

    func downloadAvailableUpdate() {
        guard let release = updateState.availableRelease else { return }
        let assetName = release.preferredAsset?.name ?? "Tessera.dmg"
        updateState = .downloading(progress: 0.0, assetName: assetName, release: release)

        Task { [weak self] in
            guard let self else { return }
            do {
                let downloaded = try await self.updateService.downloadUpdate(release) { [weak self] fraction in
                    Task { @MainActor in
                        self?.updateState = .downloading(progress: fraction, assetName: assetName, release: release)
                    }
                }

                // Persist state cleanly before closing the app for streamlined replacement.
                self.saveLayouts()
                self.saveSettings()
                self.updateState = .installing(downloaded)
                self.showToast(
                    "Updating to \(downloaded.release.version.tagString)…",
                    subtitle: downloaded.checksumVerified
                        ? "SHA-256 verified · Closing Tessera to apply update"
                        : "Closing Tessera to apply update"
                )

                // Brief beat so the user sees download/verification confirmation before app exits.
                try? await Task.sleep(for: .milliseconds(750))
                self.installUpdateAndTerminate(downloaded)
            } catch {
                self.updateState = .failed(error.localizedDescription)
                self.showToast("Download Failed", subtitle: error.localizedDescription, isError: true)
            }
        }
    }

    func installUpdateAndTerminate(_ downloaded: DownloadedUpdate) {
        saveLayouts()
        saveSettings()

        let plan = UpdateInstallPlan(downloadedAssetURL: downloaded.fileURL)
        do {
            try UpdateInstaller.launchDetachedInstaller(plan: plan)
            NSApplication.shared.terminate(nil)
        } catch {
            updateState = .readyToInstall(downloaded)
            showToast("Manual Install Needed", subtitle: error.localizedDescription, isError: true)
        }
    }

    func openDownloadedInstaller(_ downloaded: DownloadedUpdate) {
        NSWorkspace.shared.open(downloaded.fileURL)
        NSWorkspace.shared.activateFileViewerSelecting([downloaded.fileURL])
    }

    func skipUpdate(_ release: UpdateRelease) {
        settings.skippedVersion = release.version.description
        saveSettings()
        showingUpdateSheet = false
        updateState = .upToDate(
            current: TesseraMetadata.currentVersion,
            latest: release.version,
            checkedAt: Date()
        )
        showToast("Skipped \(release.version.tagString)")
    }

    // MARK: - Bundled CLI Helper Installer

    func installBundledCLI() {
        let fm = FileManager.default
        let bundledCLI = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/tessera")

        guard fm.isExecutableFile(atPath: bundledCLI.path) else {
            cliInstallStatus = "Run from packaged Tessera.app (or copy `.build/release/tessera-cli` to `/usr/local/bin/tessera`)."
            showToast("CLI Binary Not Bundled", subtitle: cliInstallStatus, isError: true)
            return
        }
        let sourceURL = bundledCLI

        let candidates = [
            URL(fileURLWithPath: "/usr/local/bin/tessera"),
            URL(fileURLWithPath: "\(NSHomeDirectory())/.local/bin/tessera")
        ]

        for target in candidates {
            do {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: target.path) {
                    try fm.removeItem(at: target)
                }
                try fm.createSymbolicLink(at: target, withDestinationURL: sourceURL)
                cliInstallStatus = "Linked `tessera` at \(target.path)"
                showToast("Installed `tessera` CLI", subtitle: target.path)
                return
            } catch {
                continue
            }
        }

        cliInstallStatus = "Could not link CLI automatically. Run: ln -sf \"\(sourceURL.path)\" /usr/local/bin/tessera"
        showToast("Manual Link Needed", subtitle: cliInstallStatus, isError: true)
    }

    // MARK: - Toast Helper

    func showToast(_ title: String, subtitle: String? = nil, isError: Bool = false) {
        toastDismissTask?.cancel()
        toast = ToastMessage(title: title, subtitle: subtitle, isError: isError)
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(isError ? 5.0 : 3.2))
            if !Task.isCancelled {
                self?.toast = nil
            }
        }
    }
}
