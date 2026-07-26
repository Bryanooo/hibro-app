import SwiftUI

enum HibroTheme {
    static let accent = Color(red: 0.65, green: 0.91, blue: 0.31)
    static let cyan = Color(red: 0.29, green: 0.78, blue: 0.92)
    static let violet = Color(red: 0.63, green: 0.52, blue: 0.94)
    static let orange = Color(red: 0.95, green: 0.66, blue: 0.27)
    static let danger = Color(red: 0.95, green: 0.36, blue: 0.38)
    static let panel = Color.white.opacity(0.055)
    static let panelStrong = Color.white.opacity(0.09)
    static let border = Color.white.opacity(0.10)
    static let background = Color(
        red: 0.035,
        green: 0.047,
        blue: 0.055
    )

    static func engineColor(_ engine: String) -> Color {
        switch engine {
        case "codex": accent
        case "claude-code": orange
        case "openclaw": cyan
        default: .secondary
        }
    }

    static func statusColor(_ status: String) -> Color {
        switch status {
        case "online", "registered", "completed", "idle": accent
        case "running", "responding", "accepted", "queued": cyan
        case "failed", "error", "rejected", "timed_out": danger
        case "cancelled", "cancelling", "offline": .secondary
        default: orange
        }
    }
}

struct PanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(HibroTheme.panel, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(HibroTheme.border, lineWidth: 1)
            }
    }
}

extension View {
    func hibroPanel() -> some View {
        modifier(PanelModifier())
    }
}
