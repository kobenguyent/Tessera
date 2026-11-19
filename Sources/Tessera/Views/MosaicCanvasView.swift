import SwiftUI
import TesseraCore

struct MosaicCanvasView: View {
    @EnvironmentObject private var appState: AppState
    let layout: TesseraLayout
    let tab: TesseraTab

    var body: some View {
        // Pure, distraction-free interactive split-pane canvas (zero redundant mock traffic-light bar)
        GeometryReader { geo in
            PaneNodeRenderer(
                node: tab.root,
                layout: layout,
                accentColor: Color(hex: layout.accentHex),
                totalPaneCount: tab.root.leafCount,
                size: geo.size
            )
        }
        .coordinateSpace(name: "MosaicCanvasSpace")
        .padding(10)
        .background(Color(red: 0.068, green: 0.076, blue: 0.112))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color(hex: layout.accentHex).opacity(0.26), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.20), radius: 12, y: 5)
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
            .id(pane.id)
            .frame(width: max(40, size.width), height: max(40, size.height))

        case .split(let split):
            let dividerThickness: CGFloat = 12
            let ratio = CGFloat(SplitSpec.clampedRatio(split.ratio))

            if split.direction == .columns {
                let available = max(80, size.width - dividerThickness)
                let firstWidth = (available * ratio).rounded(.toNearestOrEven)
                let secondWidth = max(40, available - firstWidth)

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
                    .zIndex(2)
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
                let firstHeight = (available * ratio).rounded(.toNearestOrEven)
                let secondHeight = max(40, available - firstHeight)

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
                    .zIndex(2)
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

    private var isDragging: Bool {
        dragStartRatio != nil
    }

    var body: some View {
        ZStack {
            Color.clear

            // Subtle full-span guide line while hovering or dragging
            if isHovered || isDragging {
                Rectangle()
                    .fill(accentColor.opacity(isDragging ? 0.32 : 0.16))
                    .frame(
                        width: split.direction == .columns ? 1.5 : nil,
                        height: split.direction == .columns ? nil : 1.5
                    )
                    .transition(.opacity)
            }

            // Center grip pill
            Capsule()
                .fill(isDragging ? accentColor : (isHovered ? accentColor.opacity(0.92) : .white.opacity(0.18)))
                .shadow(
                    color: (isHovered || isDragging) ? accentColor.opacity(0.50) : .clear,
                    radius: isDragging ? 7 : 4
                )
                .frame(
                    width: split.direction == .columns ? (isHovered || isDragging ? 4.5 : 2.5) : (isHovered || isDragging ? 48 : 34),
                    height: split.direction == .columns ? (isHovered || isDragging ? 48 : 34) : (isHovered || isDragging ? 4.5 : 2.5)
                )

            // Live percentage HUD while dragging
            if isDragging {
                let firstPct = Int((split.ratio * 100).rounded())
                let secondPct = 100 - firstPct
                Text("\(firstPct)% · \(secondPct)%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.08, green: 0.09, blue: 0.14).opacity(0.94))
                            .overlay(
                                Capsule()
                                    .strokeBorder(accentColor.opacity(0.65), lineWidth: 1)
                            )
                    )
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                    .offset(
                        x: split.direction == .columns ? 0 : 0,
                        y: split.direction == .columns ? -34 : -22
                    )
                    .fixedSize()
            }
        }
        .contentShape(Rectangle())
        .animation(TesseraMotion.hover, value: isHovered)
        .animation(TesseraMotion.hover, value: isDragging)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                if split.direction == .columns {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.resizeUpDown.set()
                }
            } else if !isDragging {
                NSCursor.arrow.set()
            }
        }
        .onTapGesture(count: 2) {
            withAnimation(TesseraMotion.smooth) {
                appState.updateSplitRatio(splitID: split.id, ratio: 0.5, persistImmediately: true)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("MosaicCanvasSpace"))
                .onChanged { value in
                    if dragStartRatio == nil {
                        dragStartRatio = split.ratio
                    }
                    guard let base = dragStartRatio, totalSpan > 0 else { return }
                    let delta = split.direction == .columns ? value.translation.width : value.translation.height
                    var candidate = SplitSpec.clampedRatio(base + Double(delta / totalSpan))
                    // Subtle magnetic snap at 50/50 center
                    if abs(candidate - 0.5) < 0.012 {
                        candidate = 0.5
                    }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        appState.updateSplitRatio(splitID: split.id, ratio: candidate, persistImmediately: false)
                    }
                }
                .onEnded { _ in
                    dragStartRatio = nil
                    appState.saveLayouts()
                    if !isHovered {
                        NSCursor.arrow.set()
                    }
                }
        )
        .help("Drag to resize (\(Int((split.ratio * 100).rounded()))% / \(Int(((1 - split.ratio) * 100).rounded()))%) · Double-click to reset 50/50")
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
        VStack(alignment: .leading, spacing: 0) {
            // Compact Terminal Pane Header Strip (fixed 34pt height so sibling pane dividers align pixel-perfectly)
            HStack(spacing: 7) {
                Text(pane.title.isEmpty ? "Untitled Pane" : pane.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(isSelected ? 0.96 : 0.86))
                    .lineLimit(1)

                Text(layout.effectiveWorkingDirectory(for: pane))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if pane.focus {
                    Text("FOCUS")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .tracking(0.45)
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(accentColor.opacity(0.16), in: Capsule())
                        .help("Initial keyboard focus on launch")
                }

                if pane.delaySeconds > 0 {
                    Text("+\(String(format: "%.1fs", pane.delaySeconds))")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.orange.opacity(0.16), in: Capsule())
                }

                Spacer(minLength: 4)

                ZStack(alignment: .trailing) {
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
                    } else {
                        let count = pane.nonEmptyCommands.count
                        Text(count == 0 ? "shell" : "\(count) cmd\(count == 1 ? "" : "s")")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.28))
                    }
                }
                .frame(height: 22)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(.white.opacity(isSelected ? 0.032 : 0.018))

            Rectangle()
                .fill(.white.opacity(isSelected ? 0.085 : 0.055))
                .frame(height: 0.75)

            VStack(alignment: .leading, spacing: 6) {
                if !pane.environment.isEmpty {
                    Text(pane.environment.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(hex: "#38BDF8").opacity(0.85))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                }

                // Native Multi-Line Terminal Command Editor (zero SwiftUI layout animation for crisp instant typing)
                PaneCommandEditorView(
                    commands: commandsBinding,
                    accentHex: layout.accentHex,
                    placeholder: "Type command…",
                    fontSize: 12.0,
                    darkSurface: true,
                    onFocus: {
                        if appState.selectedPaneID != pane.id {
                            appState.selectedPaneID = pane.id
                        }
                    }
                )
                .transaction { $0.animation = nil }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isSelected
                            ? [Color(red: 0.132, green: 0.150, blue: 0.218), Color(red: 0.108, green: 0.122, blue: 0.180)]
                            : (isHovered
                                ? [Color(red: 0.114, green: 0.128, blue: 0.184), Color(red: 0.096, green: 0.106, blue: 0.156)]
                                : [Color(red: 0.100, green: 0.110, blue: 0.160), Color(red: 0.086, green: 0.095, blue: 0.140)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .animation(TesseraMotion.hover, value: isSelected)
                .animation(TesseraMotion.hover, value: isHovered)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    isSelected ? accentColor.opacity(0.88) : .white.opacity(isHovered ? 0.20 : 0.085),
                    lineWidth: isSelected ? 1.5 : 1
                )
                .animation(TesseraMotion.hover, value: isSelected)
                .animation(TesseraMotion.hover, value: isHovered)
        )
        .shadow(
            color: isSelected ? accentColor.opacity(0.16) : .black.opacity(0.14),
            radius: isSelected ? 9 : 4,
            y: 2
        )
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onTapGesture {
            if appState.selectedPaneID != pane.id {
                appState.selectedPaneID = pane.id
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var commandsBinding: Binding<[String]> {
        Binding(
            get: { pane.commands },
            set: { updated in
                appState.updatePane(pane.id) { $0.commands = updated }
            }
        )
    }

    private func tileActionButton(
        symbol: String,
        help: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(TesseraMotion.smooth) {
                action()
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(destructive ? Color.red.opacity(0.92) : .white.opacity(0.86))
                .frame(width: 23, height: 21)
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 0.75)
                )
        }
        .buttonStyle(TesseraIconButtonStyle(destructive: destructive, size: 23))
        .help(help)
    }
}
