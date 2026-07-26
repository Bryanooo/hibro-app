import Foundation

enum RunLifecycleState: Hashable {
    case pending
    case active
    case completed
    case failed
}

struct RunLifecycleStep: Identifiable, Hashable {
    let id: String
    let title: String
    let caption: String
    let state: RunLifecycleState
}

struct RunFailurePresentation: Hashable {
    let title: String
    let message: String
    let suggestion: String
    let technicalDetail: String?
}

extension CoreRun {
    var isActive: Bool {
        ["requested", "accepted", "queued", "running", "cancelling"].contains(status)
    }

    var canRetry: Bool {
        ["failed", "timed_out", "cancelled"].contains(status)
    }

    var failurePresentation: RunFailurePresentation? {
        guard canRetry else { return nil }
        let code = errorString("code")?.lowercased() ?? ""
        let rawMessage = errorString("message")?.nilIfBlank

        if status == "timed_out"
            || code.contains("timeout")
            || code.contains("timed_out") {
            return RunFailurePresentation(
                title: "执行超时",
                message: "Agent 没有在允许的时间内完成任务。",
                suggestion: "可以直接重试；如果任务较大，建议拆分目标或延长 Node 的执行时限。",
                technicalDetail: rawMessage
            )
        }
        if status == "cancelled" {
            return RunFailurePresentation(
                title: "运行已取消",
                message: "这次执行在完成前被停止。",
                suggestion: "如需继续，可以使用相同目标重新运行。",
                technicalDetail: rawMessage
            )
        }
        if code.contains("auth") || code.contains("credential") {
            return RunFailurePresentation(
                title: "Agent 登录失效",
                message: "执行引擎当前无法完成身份验证。",
                suggestion: "请在对应 Node 上重新登录 Agent，然后再重试。",
                technicalDetail: rawMessage
            )
        }
        if code.contains("approval") || code.contains("denied") {
            return RunFailurePresentation(
                title: "审批未通过",
                message: "Agent 请求的操作没有获得允许，因此运行已停止。",
                suggestion: "确认操作安全后重新运行，并及时处理新的审批请求。",
                technicalDetail: rawMessage
            )
        }
        if code.contains("workspace") || code.contains("permission") {
            return RunFailurePresentation(
                title: "工作空间不可用",
                message: "Agent 无法访问本次任务所需的工作目录或文件。",
                suggestion: "检查 Node 上的工作空间路径和文件权限后重试。",
                technicalDetail: rawMessage
            )
        }
        return RunFailurePresentation(
            title: "执行未完成",
            message: rawMessage ?? "Agent 在执行过程中遇到了问题。",
            suggestion: "可以先重试一次；若仍失败，请展开技术信息查看具体原因。",
            technicalDetail: rawMessage
        )
    }

    var lifecycle: [RunLifecycleStep] {
        let failed = ["failed", "timed_out", "cancelled"].contains(status)
        return [
            RunLifecycleStep(
                id: "created",
                title: "目标已创建",
                caption: DateText.full(createdAt),
                state: .completed
            ),
            RunLifecycleStep(
                id: "assigned",
                title: "已分配执行资源",
                caption: startedAt == nil ? "等待 Node 接受" : DateText.full(startedAt),
                state: startedAt == nil
                    ? (failed ? .failed : .active)
                    : .completed
            ),
            RunLifecycleStep(
                id: "executing",
                title: "Agent 执行",
                caption: executionCaption,
                state: executionState
            ),
            RunLifecycleStep(
                id: "delivered",
                title: "结果交付",
                caption: finishedAt == nil ? "等待执行完成" : DateText.full(finishedAt),
                state: status == "completed"
                    ? .completed
                    : (failed ? .failed : .pending)
            )
        ]
    }

    private var executionState: RunLifecycleState {
        if status == "completed" { return .completed }
        if ["failed", "timed_out", "cancelled"].contains(status) { return .failed }
        if ["running", "cancelling"].contains(status) { return .active }
        return .pending
    }

    private var executionCaption: String {
        switch status {
        case "requested", "accepted", "queued": "等待开始"
        case "running": "正在处理目标"
        case "cancelling": "正在停止"
        case "completed": "执行完成"
        case "failed": "执行失败"
        case "timed_out": "执行超时"
        case "cancelled": "已取消"
        default: status
        }
    }

    private func errorString(_ key: String) -> String? {
        error?[key]?.stringValue
    }
}
