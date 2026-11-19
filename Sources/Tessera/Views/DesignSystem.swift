import SwiftUI

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
        "sparkles",
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
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                accessory()
            }

            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
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
