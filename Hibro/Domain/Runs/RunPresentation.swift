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

extension CoreRun {
    var isActive: Bool {
        ["requested", "accepted", "queued", "running", "cancelling"].contains(status)
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
}
