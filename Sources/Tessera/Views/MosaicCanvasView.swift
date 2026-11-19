import SwiftUI
import TesseraCore

struct MosaicCanvasView: View {
    @EnvironmentObject private var appState: AppState
    let layout: TesseraLayout
    let tab: TesseraTab

    var body: some View {
        VStack(spacing: 0) {
            // Mock macOS terminal chrome header
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: "#FF5F56")).frame(width: 10, height: 10)
                    Circle().fill(Color(hex: "#FFBD2E")).frame(width: 10, height: 10)
                    Circle().fill(Color(hex: "#27C93F")).frame(width: 10, height: 10)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: appState.resolvedTerminal(for: layout).symbolName)
                        .font(.system(size: 11))
                    Text("\(appState.resolvedTerminal(for: layout).displayName) — \(tab.title)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(.white.opacity(0.65))

                Spacer()

                Text("\(tab.root.leafCount) pane\(tab.root.leafCount == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.08), in: Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(red: 0.11, green: 0.12, blue: 0.16))

            Divider().overlay(.white.opacity(0.08))

            // Interactive recursive split-pane canvas
            GeometryReader { geo in
                PaneNodeRenderer(
                    node: tab.root,
                    layout: layout,
                    accentColor: Color(hex: layout.accentHex),
                    totalPaneCount: tab.root.leafCount,
                    size: geo.size
                )
            }
            .padding(10)
            .background(Color(red: 0.07, green: 0.08, blue: 0.11))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(hex: layout.accentHex).opacity(0.32), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
    }
}

private struct PaneNodeRenderer: View {
    @EnvironmentObject private var appState: AppState
    let node: PaneNode
    let layout: TesseraLayout
    let accentColor: Color
    let totalPaneCount: Int
    let size: CGSize

    var body: some View {
        switch node {
        case .leaf(let pane):
            PaneTileView(
                pane: pane,
                layout: layout,
                accentColor: accentColor,
                isSelected: appState.selectedPaneID == pane.id,
                canDelete: totalPaneCount > 1
            )
            .frame(width: max(40, size.width), height: max(40, size.height))

        case .split(let split):
            let dividerThickness: CGFloat = 10
            let ratio = CGFloat(SplitSpec.clampedRatio(split.ratio))

            if split.direction == .columns {
                let available = max(80, size.width - dividerThickness)
                let firstWidth = available * ratio
                let secondWidth = available - firstWidth

                HStack(spacing: 0) {
                    PaneNodeRenderer(
                        node: split.first,
                        layout: layout,
                        accentColor: accentColor,
                        totalPaneCount: totalPaneCount,
                        size: CGSize(width: firstWidth, height: size.height)
                    )
                    SplitDividerHandle(
                        split: split,
                        totalSpan: available,
                        accentColor: accentColor
                    )
                    .frame(width: dividerThickness, height: size.height)
                    PaneNodeRenderer(
                        node: split.second,
                        layout: layout,
                        accentColor: accentColor,
                        totalPaneCount: totalPaneCount,
                        size: CGSize(width: secondWidth, height: size.height)
                    )
                }
            } else {
                let available = max(80, size.height - dividerThickness)
                let firstHeight = available * ratio
                let secondHeight = available - firstHeight

                VStack(spacing: 0) {
                    PaneNodeRenderer(
                        node: split.first,
                        layout: layout,
                        accentColor: accentColor,
                        totalPaneCount: totalPaneCount,
                        size: CGSize(width: size.width, height: firstHeight)
                    )
                    SplitDividerHandle(
                        split: split,
                        totalSpan: available,
                        accentColor: accentColor
                    )
                    .frame(width: size.width, height: dividerThickness)
                    PaneNodeRenderer(
                        node: split.second,
                        layout: layout,
                        accentColor: accentColor,
                        totalPaneCount: totalPaneCount,
                        size: CGSize(width: size.width, height: secondHeight)
                    )
                }
            }
        }
    }
}

private struct SplitDividerHandle: View {
    @EnvironmentObject private var appState: AppState
    let split: SplitSpec
    let totalSpan: CGFloat
    let accentColor: Color

    @State private var isHovered = false
    @State private var dragStartRatio: Double?

    var body: some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(isHovered || dragStartRatio != nil ? accentColor : .white.opacity(0.18))
                .frame(
                    width: split.direction == .columns ? (isHovered ? 4 : 2) : 34,
                    height: split.direction == .columns ? 34 : (isHovered ? 4 : 2)
                )
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                if split.direction == .columns {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.resizeUpDown.push()
                }
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStartRatio == nil {
                        dragStartRatio = split.ratio
                    }
                    let base = dragStartRatio ?? split.ratio
                    let delta = split.direction == .columns ? value.translation.width : value.translation.height
                    guard totalSpan > 0 else { return }
                    let updated = SplitSpec.clampedRatio(base + Double(delta / totalSpan))
                    appState.updateSplitRatio(splitID: split.id, ratio: updated)
                }
                .onEnded { _ in
                    dragStartRatio = nil
                }
        )
        .help("Drag to resize split (\(Int((split.ratio * 100).rounded()))% / \(Int(((1 - split.ratio) * 100).rounded()))%)")
    }
}

private struct PaneTileView: View {
    @EnvironmentObject private var appState: AppState
    let pane: PaneSpec
    let layout: TesseraLayout
    let accentColor: Color
    let isSelected: Bool
    let canDelete: Bool

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Pane Header
            HStack(spacing: 6) {
                if pane.focus {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                        .help("Initial keyboard focus")
                }

                Text(pane.title.isEmpty ? "Untitled Pane" : pane.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)

                if pane.delaySeconds > 0 {
                    Text("+\(String(format: "%.1fs", pane.delaySeconds))")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.orange.opacity(0.18), in: Capsule())
                }

                Spacer(minLength: 4)

                if isHovered || isSelected {
                    HStack(spacing: 4) {
                        tileActionButton(
                            symbol: "rectangle.split.2x1",
                            help: "Split Side-by-Side (Columns)"
                        ) {
                            appState.splitPane(pane.id, direction: .columns)
                        }
                        tileActionButton(
                            symbol: "rectangle.split.1x2",
                            help: "Split Top / Bottom (Rows)"
                        ) {
                            appState.splitPane(pane.id, direction: .rows)
                        }
                        if canDelete {
                            tileActionButton(
                                symbol: "xmark",
                                help: "Remove Pane",
                                destructive: true
                            ) {
                                appState.removePane(pane.id)
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }

            // Working Directory Pill
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 9))
                Text(layout.effectiveWorkingDirectory(for: pane))
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.white.opacity(0.48))

            // Commands Preview
            VStack(alignment: .leading, spacing: 3) {
                if !pane.environment.isEmpty {
                    Text(pane.environment.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(hex: "#38BDF8").opacity(0.85))
                        .lineLimit(1)
                }

                if pane.nonEmptyCommands.isEmpty {
                    Text("$ (interactive shell)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.32))
                        .italic()
                } else {
                    ForEach(Array(pane.nonEmptyCommands.prefix(4).enumerated()), id: \.offset) { _, cmd in
                        HStack(alignment: .top, spacing: 5) {
                            Text("$")
                                .foregroundStyle(accentColor)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            Text(cmd)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.88))
                                .lineLimit(2)
                        }
                    }
                    if pane.nonEmptyCommands.count > 4 {
                        Text("… +\(pane.nonEmptyCommands.count - 4) more command(s)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color(red: 0.14, green: 0.16, blue: 0.23) : Color(red: 0.10, green: 0.11, blue: 0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected ? accentColor : .white.opacity(isHovered ? 0.24 : 0.10),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            appState.selectedPaneID = pane.id
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private func tileActionButton(
        symbol: String,
        help: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(destructive ? Color.red.opacity(0.9) : .white.opacity(0.85))
                .frame(width: 22, height: 20)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
