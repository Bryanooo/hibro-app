import SwiftUI

struct HibroMark: View {
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(
                    LinearGradient(
                        colors: [HibroTheme.accent, HibroTheme.cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(.black.opacity(0.8))
        }
        .frame(width: size, height: size)
        .shadow(color: HibroTheme.accent.opacity(0.2), radius: 16)
    }
}

struct StatusPill: View {
    let status: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(HibroTheme.statusColor(status))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                HibroTheme.statusColor(status).opacity(0.12),
                in: Capsule()
            )
    }

    private var label: String {
        switch status {
        case "online": "在线"
        case "offline": "离线"
        case "registered": "已注册"
        case "running": "运行中"
        case "responding": "响应中"
        case "completed": "已完成"
        case "failed": "失败"
        case "cancelled": "已取消"
        case "cancelling": "取消中"
        case "timed_out": "已超时"
        case "idle": "空闲"
        case "error": "异常"
        case "queued": "排队中"
        case "accepted": "已接受"
        default: status
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let caption: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            Text(value)
                .font(.system(.title, design: .rounded, weight: .bold))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .hibroPanel()
    }
}

struct SectionHeader: View {
    let title: String
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.bold())
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EngineBadge: View {
    let engine: String

    var body: some View {
        Label(label, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(HibroTheme.engineColor(engine))
    }

    private var label: String {
        switch engine {
        case "claude-code": "CLAUDE"
        case "codex": "CODEX"
        case "openclaw": "OPENCLAW"
        default: engine.uppercased()
        }
    }

    private var symbol: String {
        switch engine {
        case "claude-code": "sparkles"
        case "codex": "chevron.left.forwardslash.chevron.right"
        case "openclaw": "network"
        default: "cpu"
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: symbol,
            description: Text(message)
        )
    }
}

enum DateText {
    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }

    static func relative(_ value: String?) -> String {
        guard let date = date(from: value) else {
            return "—"
        }
        return date.formatted(.relative(presentation: .named))
    }

    static func full(_ value: String?) -> String {
        guard let date = date(from: value) else {
            return "—"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
