import Foundation

enum ApprovalDecision: String, CaseIterable, Codable, Hashable, Sendable {
    case allowOnce = "allow_once"
    case allowAlways = "allow_always"
    case deny

    var title: String {
        switch self {
        case .allowOnce: "仅本次允许"
        case .allowAlways: "本会话允许"
        case .deny: "拒绝"
        }
    }

    var shortTitle: String {
        switch self {
        case .allowOnce: "仅本次"
        case .allowAlways: "本会话"
        case .deny: "拒绝"
        }
    }
}

enum InboxItemKind: String, CaseIterable, Codable, Hashable, Sendable {
    case approval
    case question
    case runFailed
    case completed

    var title: String {
        switch self {
        case .approval: "待审批"
        case .question: "Agent 提问"
        case .runFailed: "任务失败"
        case .completed: "已完成"
        }
    }

    var symbol: String {
        switch self {
        case .approval: "hand.raised.fill"
        case .question: "questionmark.bubble.fill"
        case .runFailed: "exclamationmark.triangle.fill"
        case .completed: "checkmark.circle.fill"
        }
    }

    var requiresAttention: Bool {
        self != .completed
    }
}

struct InboxItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let kind: InboxItemKind
    let title: String
    let summary: String
    let createdAt: String
    let runID: String?
    let conversationID: String?
    let approvalSource: InboxApprovalSource?
    var approvalExternalID: String? = nil

    var requiresAttention: Bool { kind.requiresAttention }
}

extension InboxItem {
    init?(coreItem: CoreInboxItem) {
        let kind: InboxItemKind
        switch coreItem.kind {
        case "approval": kind = .approval
        case "question": kind = .question
        case "run_failed": kind = .runFailed
        case "completed": kind = .completed
        default: return nil
        }

        let approvalSource: InboxApprovalSource?
        switch coreItem.approval?.source {
        case "conversation":
            if let activityID = coreItem.approval?.activityId {
                approvalSource = .conversation(activityID: activityID)
            } else {
                approvalSource = nil
            }
        case "run":
            if let externalID = coreItem.approval?.externalId {
                approvalSource = .run(externalID: externalID)
            } else {
                approvalSource = nil
            }
        default:
            approvalSource = nil
        }

        self.init(
            id: coreItem.id,
            kind: kind,
            title: coreItem.title,
            summary: coreItem.summary,
            createdAt: coreItem.createdAt,
            runID: coreItem.runId,
            conversationID: coreItem.conversationId,
            approvalSource: approvalSource,
            approvalExternalID: coreItem.approval?.externalId
        )
    }
}

enum InboxApprovalSource: Codable, Hashable, Sendable {
    case conversation(activityID: String)
    case run(externalID: String)
}

enum InboxBuilder {
    static func build(
        runs: [CoreRun],
        conversationDetails: [ConversationDetail],
        runEvents: [String: [CoreRunEvent]] = [:],
        excludingRunApprovalIDs: Set<String> = [],
        excludingActivityIDs: Set<String> = []
    ) -> [InboxItem] {
        var items: [InboxItem] = []

        for detail in conversationDetails {
            for activity in detail.activities {
                guard !excludingActivityIDs.contains(activity.id) else {
                    continue
                }
                guard let kind = kind(for: activity), isPending(activity, kind: kind) else {
                    continue
                }
                items.append(
                    InboxItem(
                        id: "activity:\(activity.id)",
                        kind: kind,
                        title: activity.title,
                        summary: activity.detail
                            ?? activity.approval?.reason
                            ?? detail.conversation.title,
                        createdAt: activity.createdAt,
                        runID: activity.runId,
                        conversationID: detail.conversation.id,
                        approvalSource: kind == .approval
                            ? .conversation(activityID: activity.id)
                            : nil,
                        approvalExternalID: kind == .approval
                            ? activity.approval?.externalId
                            : nil
                    )
                )
            }
        }

        for run in runs {
            let events = runEvents[run.id] ?? []
            for event in events {
                guard let approval = event.approvalRequest else { continue }
                let isResolved = events.contains {
                    $0.sequence > event.sequence
                        && $0.type == "engine.approval.resolved"
                        && $0.approvalExternalID == approval.externalID
                }
                let approvalID = "\(run.id):\(approval.externalID)"
                guard !isResolved,
                      !excludingRunApprovalIDs.contains(approvalID)
                else {
                    continue
                }
                items.append(
                    InboxItem(
                        id: "run-approval:\(run.id):\(approval.externalID)",
                        kind: .approval,
                        title: approval.title,
                        summary: approval.detail ?? run.prompt,
                        createdAt: approval.timestamp,
                        runID: run.id,
                        conversationID: nil,
                        approvalSource: .run(externalID: approval.externalID),
                        approvalExternalID: approval.externalID
                    )
                )
            }

            let kind: InboxItemKind?
            if ["failed", "timed_out"].contains(run.status) {
                kind = .runFailed
            } else if run.status == "completed" {
                kind = .completed
            } else {
                kind = nil
            }
            guard let kind else { continue }
            items.append(
                InboxItem(
                    id: "run:\(run.id):\(run.status)",
                    kind: kind,
                    title: run.prompt,
                    summary: runSummary(run, kind: kind),
                    createdAt: run.finishedAt ?? run.updatedAt,
                    runID: run.id,
                    conversationID: nil,
                    approvalSource: nil
                )
            )
        }

        return Dictionary(grouping: items, by: \.id)
            .compactMap { $0.value.first }
            .sorted { lhs, rhs in
                if lhs.requiresAttention != rhs.requiresAttention {
                    return lhs.requiresAttention
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    private static func kind(for activity: CoreActivity) -> InboxItemKind? {
        switch activity.type {
        case "approval", "approval_request", "approval.request":
            .approval
        case "question", "agent_question", "agent.question":
            .question
        default:
            nil
        }
    }

    private static func isPending(
        _ activity: CoreActivity,
        kind: InboxItemKind
    ) -> Bool {
        switch kind {
        case .approval:
            activity.approval?.decision == nil
                && !["completed", "resolved", "rejected"].contains(activity.status)
        case .question:
            !["completed", "answered", "resolved"].contains(activity.status)
        default:
            true
        }
    }

    private static func runSummary(
        _ run: CoreRun,
        kind: InboxItemKind
    ) -> String {
        switch kind {
        case .runFailed:
            if let error = run.error,
               case .string(let message)? = error["message"] {
                return message
            }
            return run.status == "timed_out" ? "执行超时，需要检查或重试。" : "执行未完成，需要检查。"
        case .completed:
            return run.result?.nilIfBlank ?? "任务已经完成，可以查看结果与产出。"
        default:
            return run.prompt
        }
    }
}
