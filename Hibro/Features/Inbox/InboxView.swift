import SwiftUI

struct InboxView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = InboxFilter.attention

    var body: some View {
        Group {
            if filteredItems.isEmpty {
                EmptyStateView(
                    symbol: filter == .outcomes ? "checkmark.circle" : "tray",
                    title: emptyTitle,
                    message: emptyMessage
                )
            } else {
                List(filteredItems) { item in
                    NavigationLink {
                        InboxItemDetailView(itemID: item.id)
                    } label: {
                        InboxItemRow(item: item)
                            .padding(.vertical, 6)
                    }
                    .listRowBackground(
                        model.selectedInboxItemID == item.id
                            ? HibroTheme.orange.opacity(0.08)
                            : Color.clear
                    )
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("收件箱")
        .task {
            guard !model.isWorking else { return }
            await model.refreshFromUser()
        }
        .safeAreaInset(edge: .top) {
            Picker("收件箱筛选", selection: $filter) {
                ForEach(InboxFilter.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .refreshable { await model.refreshFromUser() }
    }

    private var filteredItems: [InboxItem] {
        switch filter {
        case .attention:
            model.inboxItems.filter(\.requiresAttention)
        case .outcomes:
            model.inboxItems.filter { !$0.requiresAttention }
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .attention: "没有待处理事项"
        case .outcomes: "还没有完成记录"
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .attention: "Agent 暂时不需要你的决定。"
        case .outcomes: "完成的任务会自动汇总到这里。"
        }
    }
}

private enum InboxFilter: String, CaseIterable, Identifiable {
    case attention
    case outcomes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .attention: "待处理"
        case .outcomes: "已完成"
        }
    }
}

struct InboxItemRow: View {
    let item: InboxItem

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: item.kind.symbol)
                .foregroundStyle(item.kind.color)
                .frame(width: 40, height: 40)
                .background(
                    item.kind.color.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 11)
                )
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(item.kind.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.kind.color)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(DateText.relative(item.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(item.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct InboxItemDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let itemID: String

    private var item: InboxItem? {
        model.inboxItems.first(where: { $0.id == itemID })
    }

    private var activity: CoreActivity? {
        guard itemID.hasPrefix("activity:") else { return nil }
        let activityID = String(itemID.dropFirst("activity:".count))
        return model.conversationDetailsByID.values
            .lazy
            .flatMap(\.activities)
            .first(where: { $0.id == activityID })
    }

    private var runApproval: RunApprovalRequest? {
        guard let item,
              case .run(let externalID)? = item.approvalSource,
              let runID = item.runID
        else {
            return nil
        }
        return model.runEventsByID[runID]?
            .compactMap(\.approvalRequest)
            .first(where: { $0.externalID == externalID })
    }

    var body: some View {
        ScrollView {
            if let item {
                VStack(alignment: .leading, spacing: 18) {
                    identity(item)
                    context(item)
                    if item.kind == .approval {
                        approvalActions(item)
                    } else {
                        relatedActions(item)
                    }
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            } else {
                EmptyStateView(
                    symbol: "checkmark.circle",
                    title: "事项已处理",
                    message: "这个事项已经完成或不再需要你的操作。"
                )
            }
        }
        .navigationTitle("事项详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func identity(_ item: InboxItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(item.kind.title, systemImage: item.kind.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.kind.color)
                Spacer()
                Text(DateText.relative(item.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(item.title)
                .font(.title2.bold())
            Text(item.summary)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hibroPanel()
    }

    private func context(_ item: InboxItem) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("上下文", systemImage: "scope")
                .font(.headline)
            if let conversationID = item.conversationID,
               let detail = model.conversationDetailsByID[conversationID] {
                LabeledContent("对话", value: detail.conversation.title)
                LabeledContent(
                    "Agent",
                    value: model.agentName(detail.conversation.agentId)
                )
            }
            if let runID = item.runID,
               let run = model.runs.first(where: { $0.id == runID }) {
                LabeledContent("目标", value: run.prompt)
                LabeledContent("状态", value: run.status)
            }
            if let reason = activity?.approval?.reason {
                LabeledContent("原因", value: reason)
            } else if let detail = runApproval?.detail {
                LabeledContent("操作", value: detail)
            }
        }
        .padding(18)
        .hibroPanel()
    }

    @ViewBuilder
    private func approvalActions(_ item: InboxItem) -> some View {
        if let approval = activity?.approval, approval.resolvable {
            ApprovalDecisionPanel(
                title: item.title,
                detail: activity?.detail ?? approval.reason,
                decisions: supportedDecisions(approval),
                onDecision: submit,
                onCompleted: { dismiss() }
            )
        } else if let approval = runApproval {
            ApprovalDecisionPanel(
                title: approval.title,
                detail: approval.detail,
                decisions: approval.decisions,
                onDecision: submit,
                onCompleted: { dismiss() }
            )
        } else {
            relatedActions(item)
        }
    }

    @ViewBuilder
    private func relatedActions(_ item: InboxItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("继续处理")
                .font(.headline)
            if let runID = item.runID {
                NavigationLink {
                    RunDetailView(runID: runID)
                } label: {
                    Label("查看运行详情", systemImage: "play.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(HibroTheme.accent)
                .foregroundStyle(.black)
            }
            if let conversationID = item.conversationID {
                NavigationLink {
                    ConversationDetailView(conversationID: conversationID)
                } label: {
                    Label("在对话中回复", systemImage: "bubble.left.and.bubble.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .hibroPanel()
    }

    private func supportedDecisions(
        _ approval: CoreApproval
    ) -> [ApprovalDecision] {
        ApprovalDecision.allCases.filter {
            approval.decisions.contains($0.rawValue)
        }
    }

    private func submit(_ decision: ApprovalDecision) async -> Bool {
        if let activity,
           let conversationID = item?.conversationID {
            return await model.decideApproval(
                conversationID: conversationID,
                activityID: activity.id,
                decision: decision
            )
        }
        if let runApproval {
            return await model.decideRunApproval(
                runID: runApproval.runID,
                externalID: runApproval.externalID,
                decision: decision
            )
        }
        return false
    }
}

private extension InboxItemKind {
    var color: Color {
        switch self {
        case .approval: HibroTheme.orange
        case .question: HibroTheme.violet
        case .runFailed: HibroTheme.danger
        case .completed: HibroTheme.accent
        }
    }
}
