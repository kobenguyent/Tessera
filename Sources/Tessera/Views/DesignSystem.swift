import SwiftUI

enum TesseraMotion {
    static let hover = Animation.easeOut(duration: 0.14)
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.78)
    static let smooth = Animation.spring(response: 0.28, dampingFraction: 0.84)
    static let gentle = Animation.easeInOut(duration: 0.20)
}

public enum TesseraPalette {
    public static let accents: [(name: String, hex: String)] = [
        ("Indigo", "#6366F1"),
        ("Emerald", "#10B981"),
        ("Amethyst", "#A855F7"),
        ("Amber", "#F59E0B"),
        ("Cerulean", "#0EA5E9"),
        ("Rose", "#EC4899"),
        ("Teal", "#14B8A6"),
        ("Crimson", "#EF4444")
    ]

    public static let icons: [String] = [
        "square.grid.2x2.fill",
        "hammer.fill",
        "server.rack",
        "terminal.fill",
        "rectangle.split.2x1.fill",
        "rectangle.split.3x1.fill",
        "macwindow.on.rectangle",
        "cpu.fill",
        "bolt.fill",
        "ladybug.fill",
        "shippingbox.fill",
        "network",
        "waveform.path.ecg"
    ]
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: Double
        switch cleaned.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 0.39; g = 0.40; b = 0.95
        }
        self.init(red: r, green: g, blue: b)
    }
}

struct PillBadge: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .foregroundStyle(tint)
        .background(tint.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 0.75))
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct InspectorSectionCard<HeaderAccessory: View, Content: View>: View {
    let title: String
    var systemImage: String? = nil
    @ViewBuilder var accessory: () -> HeaderAccessory
    @ViewBuilder var content: () -> Content

    init(
        _ title: String,
        systemImage: String? = nil,
        @ViewBuilder accessory: @escaping () -> HeaderAccessory = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .tracking(0.55)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                accessory()
            }

            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.075), lineWidth: 1)
        )
    }
}

/// Soft, continuous-corner secondary button & dropdown style with smooth hover and spring press.
struct TesseraSoftButtonStyle: ButtonStyle {
    var tint: Color? = nil
    var isActive: Bool = false
    var cornerRadius: CGFloat = 8
    var horizontalPadding: CGFloat = 9
    var verticalPadding: CGFloat = 5

    func makeBody(configuration: Configuration) -> some View {
        TesseraSoftButtonBody(
            configuration: configuration,
            tint: tint,
            isActive: isActive,
            cornerRadius: cornerRadius,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        )
    }

    private struct TesseraSoftButtonBody: View {
        let configuration: Configuration
        let tint: Color?
        let isActive: Bool
        let cornerRadius: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat

        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        private var fillColor: Color {
            if let tint, isActive {
                return tint.opacity(configuration.isPressed ? 0.26 : (isHovered ? 0.22 : 0.16))
            }
            if configuration.isPressed {
                return Color.primary.opacity(0.13)
            }
            if isHovered {
                return Color.primary.opacity(0.095)
            }
            return Color.primary.opacity(0.055)
        }

        private var borderColor: Color {
            if let tint, isActive {
                return tint.opacity(isHovered ? 0.55 : 0.38)
            }
            return Color.primary.opacity(isHovered ? 0.18 : 0.10)
        }

        var body: some View {
            configuration.label
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fillColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.965 : 1.0)
                .opacity(isEnabled ? 1.0 : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .animation(TesseraMotion.hover, value: isHovered)
                .animation(TesseraMotion.press, value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }
    }
}

/// Tactile primary CTA button with top-lit sheen, soft hover glow, and spring press.
struct TesseraProminentButtonStyle: ButtonStyle {
    var tint: Color = Color(hex: "#6366F1")
    var cornerRadius: CGFloat = 8
    var horizontalPadding: CGFloat = 11
    var verticalPadding: CGFloat = 5.5

    func makeBody(configuration: Configuration) -> some View {
        TesseraProminentButtonBody(
            configuration: configuration,
            tint: tint,
            cornerRadius: cornerRadius,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        )
    }

    private struct TesseraProminentButtonBody: View {
        let configuration: Configuration
        let tint: Color
        let cornerRadius: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat

        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(.white)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint.opacity(configuration.isPressed ? 0.84 : (isHovered ? 1.0 : 0.92)))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [.white.opacity(isHovered ? 0.22 : 0.14), .clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(isHovered ? 0.30 : 0.18), lineWidth: 0.75)
                )
                .shadow(
                    color: isEnabled ? tint.opacity(isHovered ? 0.36 : 0.18) : .clear,
                    radius: isHovered ? 8 : 4,
                    y: 2
                )
                .scaleEffect(configuration.isPressed ? 0.965 : 1.0)
                .opacity(isEnabled ? 1.0 : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .animation(TesseraMotion.hover, value: isHovered)
                .animation(TesseraMotion.press, value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }
    }
}

/// Soft pill chip button for quick-insert commands and compact controls.
struct TesseraChipButtonStyle: ButtonStyle {
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        TesseraChipBody(configuration: configuration, tint: tint)
    }

    private struct TesseraChipBody: View {
        let configuration: Configuration
        let tint: Color?
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(
                            tint != nil
                                ? tint!.opacity(configuration.isPressed ? 0.82 : (isHovered ? 1.0 : 0.90))
                                : Color.primary.opacity(configuration.isPressed ? 0.14 : (isHovered ? 0.10 : 0.055))
                        )
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            tint != nil ? .white.opacity(0.22) : Color.primary.opacity(isHovered ? 0.18 : 0.09),
                            lineWidth: 0.85
                        )
                )
                .foregroundStyle(tint != nil ? Color.white : Color.primary)
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                .contentShape(Capsule())
                .animation(TesseraMotion.hover, value: isHovered)
                .animation(TesseraMotion.press, value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }
    }
}

/// Soft translucent icon-only button for subtle chrome actions.
struct TesseraIconButtonStyle: ButtonStyle {
    var destructive: Bool = false
    var size: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        TesseraIconBody(configuration: configuration, destructive: destructive, size: size)
    }

    private struct TesseraIconBody: View {
        let configuration: Configuration
        let destructive: Bool
        let size: CGFloat
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        .fill(
                            isHovered
                                ? (destructive ? Color.red.opacity(0.16) : Color.primary.opacity(0.09))
                                : Color.clear
                        )
                )
                .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
                .opacity(isEnabled ? 1.0 : 0.4)
                .contentShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                .animation(TesseraMotion.hover, value: isHovered)
                .animation(TesseraMotion.press, value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let isError: Bool

    init(title: String, subtitle: String? = nil, isError: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.isError = isError
    }
}
