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

struct ApprovalDecisionPanel: View {
    enum Style {
        case detailed
        case compact
    }

    @Environment(AppModel.self) private var model
    let title: String
    let detail: String?
    let decisions: [ApprovalDecision]
    let style: Style
    let onDecision: (ApprovalDecision) async -> Bool
    let onCompleted: () -> Void
    @State private var pendingDecision: ApprovalDecision?
    @State private var authorizationError: String?

    init(
        title: String,
        detail: String? = nil,
        decisions: [ApprovalDecision],
        style: Style = .detailed,
        onDecision: @escaping (ApprovalDecision) async -> Bool,
        onCompleted: @escaping () -> Void = {}
    ) {
        self.title = title
        self.detail = detail
        self.decisions = decisions
        self.style = style
        self.onDecision = onDecision
        self.onCompleted = onCompleted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style == .compact ? 9 : 12) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(HibroTheme.orange)
                Text(style == .compact ? "Agent 正在等待你的决定" : "做出决定")
                    .font(style == .compact ? .subheadline.weight(.semibold) : .headline)
                Spacer()
                Text("待审批")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(HibroTheme.orange)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(style == .compact ? 1 : 3)
            if let detail = detail?.nilIfBlank {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(style == .compact ? 2 : nil)
                    .textSelection(.enabled)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { decisionButtons }
                VStack(spacing: 8) { decisionButtons }
            }
        }
        .padding(style == .compact ? 12 : 18)
        .background(
            style == .compact
                ? AnyShapeStyle(.regularMaterial)
                : AnyShapeStyle(HibroTheme.panelStrong),
            in: RoundedRectangle(cornerRadius: style == .compact ? 0 : 16)
        )
        .overlay {
            if style == .detailed {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(HibroTheme.border)
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingDecision != nil },
                set: { if !$0 { pendingDecision = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingDecision {
                Button(
                    pendingDecision.title,
                    role: pendingDecision == .deny ? .destructive : nil
                ) {
                    Task { await submit(pendingDecision) }
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert(
            "无法确认审批",
            isPresented: Binding(
                get: { authorizationError != nil },
                set: { if !$0 { authorizationError = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(authorizationError ?? "")
        }
    }

    @ViewBuilder
    private var decisionButtons: some View {
        ForEach(decisions, id: \.self) { decision in
            Button {
                pendingDecision = decision
            } label: {
                Label(
                    style == .compact ? decision.shortTitle : decision.title,
                    systemImage: decision == .deny
                        ? "xmark.circle"
                        : "checkmark.shield"
                )
                .font(style == .compact ? .caption.weight(.semibold) : .body)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(decision == .deny ? HibroTheme.danger : HibroTheme.accent)
            .foregroundStyle(decision == .deny ? Color.white : Color.black)
            .disabled(model.isWorking)
        }
    }

    private func submit(_ decision: ApprovalDecision) async {
        pendingDecision = nil
        if !model.isDemoMode {
            do {
                try await ApprovalAuthorizer.authorize()
            } catch {
                authorizationError = error.localizedDescription
                return
            }
        }
        if await onDecision(decision) {
            onCompleted()
        }
    }

    private var confirmationTitle: String {
        guard let pendingDecision else { return "确认审批决定" }
        return "确认“\(pendingDecision.title)”？"
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
