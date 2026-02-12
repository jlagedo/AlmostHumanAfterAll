import Foundation

enum AIEngine: String, CaseIterable, Identifiable {
    case claude = "Claude"
    case appleIntelligence = "Apple Intelligence"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .claude: return "cloud.fill"
        case .appleIntelligence: return "apple.intelligence"
        }
    }
}
