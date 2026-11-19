import Foundation

public enum CommandCategory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case custom
    case dev
    case git
    case containers
    case testing
    case monitoring

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .custom: return "Custom"
        case .dev: return "Dev"
        case .git: return "Git"
        case .containers: return "Containers"
        case .testing: return "Testing"
        case .monitoring: return "Monitoring"
        }
    }

    public var symbolName: String {
        switch self {
        case .custom: return "star.fill"
        case .dev: return "hammer.fill"
        case .git: return "arrow.triangle.branch"
        case .containers: return "shippingbox.fill"
        case .testing: return "checkmark.shield.fill"
        case .monitoring: return "waveform.path.ecg"
        }
    }

    public var accentHex: String {
        switch self {
        case .custom: return "#A855F7"
        case .dev: return "#6366F1"
        case .git: return "#F59E0B"
        case .containers: return "#0EA5E9"
        case .testing: return "#10B981"
        case .monitoring: return "#EC4899"
        }
    }
}

public struct CommandSnippet: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var label: String
    public var command: String
    public var category: CommandCategory
    public var isBuiltIn: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        label: String,
        command: String,
        category: CommandCategory = .custom,
        isBuiltIn: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.command = command
        self.category = category
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
    }

    public static func suggestedLabel(for command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Custom Command" }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        let short = words.prefix(2).joined(separator: " ")
        return short.count > 24 ? String(short.prefix(24)) : short
    }

    public static func builtInDefaults() -> [CommandSnippet] {
        [
            CommandSnippet(
                id: UUID(uuidString: "30000000-0000-4000-8000-000000000001")!,
                label: "git status",
                command: "git status -sb",
                category: .git,
                isBuiltIn: true
            ),
            CommandSnippet(
                id: UUID(uuidString: "30000000-0000-4000-8000-000000000002")!,
                label: "npm dev",
                command: "npm run dev",
                category: .dev,
                isBuiltIn: true
            ),
            CommandSnippet(
                id: UUID(uuidString: "30000000-0000-4000-8000-000000000003")!,
                label: "swift test",
                command: "swift test",
                category: .testing,
                isBuiltIn: true
            ),
            CommandSnippet(
                id: UUID(uuidString: "30000000-0000-4000-8000-000000000004")!,
                label: "docker ps",
                command: "docker ps",
                category: .containers,
                isBuiltIn: true
            ),
            CommandSnippet(
                id: UUID(uuidString: "30000000-0000-4000-8000-000000000005")!,
                label: "htop/top",
                command: "top -o cpu",
                category: .monitoring,
                isBuiltIn: true
            ),
            CommandSnippet(
                id: UUID(uuidString: "30000000-0000-4000-8000-000000000006")!,
                label: "git log",
                command: "git log -n 10 --oneline",
                category: .git,
                isBuiltIn: true
            ),
            CommandSnippet(
                id: UUID(uuidString: "30000000-0000-4000-8000-000000000007")!,
                label: "docker compose",
                command: "docker compose up",
                category: .containers,
                isBuiltIn: true
            )
        ]
    }
}
