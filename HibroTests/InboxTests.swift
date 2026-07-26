import XCTest
@testable import Hibro

final class InboxTests: XCTestCase {
    func testInboxPrioritizesAttentionOverCompletedRuns() {
        let items = InboxBuilder.build(
            runs: DemoData.runs,
            conversationDetails: Array(DemoData.conversationDetails.values)
        )

        XCTAssertEqual(items.filter(\.requiresAttention).count, 2)
        XCTAssertTrue(items.prefix(2).allSatisfy(\.requiresAttention))
        XCTAssertTrue(items.contains { $0.kind == .approval })
        XCTAssertTrue(items.contains { $0.kind == .question })
        XCTAssertTrue(items.contains { $0.kind == .completed })
    }

    func testHandledActivityIsExcluded() {
        let items = InboxBuilder.build(
            runs: DemoData.runs,
            conversationDetails: Array(DemoData.conversationDetails.values),
            excludingActivityIDs: ["activity_demo_approval"]
        )

        XCTAssertFalse(items.contains { $0.id == "activity:activity_demo_approval" })
        XCTAssertTrue(items.contains { $0.id == "activity:activity_demo_question" })
    }

    func testRunLifecycleReflectsActiveExecution() throws {
        let run = try XCTUnwrap(
            DemoData.runs.first { $0.id == "run_demo_active" }
        )

        XCTAssertTrue(run.isActive)
        XCTAssertEqual(run.lifecycle.count, 4)
        XCTAssertEqual(run.lifecycle[2].state, .active)
        XCTAssertEqual(run.lifecycle[3].state, .pending)
    }

    func testApprovalDecisionMatchesCorePayload() {
        XCTAssertEqual(ApprovalDecision.allowOnce.rawValue, "allow_once")
        XCTAssertEqual(ApprovalDecision.allowAlways.rawValue, "allow_always")
        XCTAssertEqual(ApprovalDecision.deny.rawValue, "deny")
    }

    func testRunApprovalAppearsAndResolvedEventRemovesIt() throws {
        let run = try XCTUnwrap(
            DemoData.runs.first { $0.id == "run_demo_active" }
        )
        let requested = CoreRunEvent(
            coreRunId: run.id,
            localRunId: run.localRunId,
            sequence: 1,
            type: "engine.approval.requested",
            timestamp: "2026-07-25T16:00:00.000Z",
            payload: [
                "request": .object([
                    "externalId": .string("approval_external"),
                    "title": .string("允许执行部署命令"),
                    "command": .string("deploy production")
                ])
            ]
        )
        var items = InboxBuilder.build(
            runs: [run],
            conversationDetails: [],
            runEvents: [run.id: [requested]]
        )
        XCTAssertTrue(
            items.contains {
                $0.id == "run-approval:\(run.id):approval_external"
                    && $0.kind == .approval
            }
        )

        let resolved = CoreRunEvent(
            coreRunId: run.id,
            localRunId: run.localRunId,
            sequence: 2,
            type: "engine.approval.resolved",
            timestamp: "2026-07-25T16:01:00.000Z",
            payload: ["externalId": .string("approval_external")]
        )
        items = InboxBuilder.build(
            runs: [run],
            conversationDetails: [],
            runEvents: [run.id: [requested, resolved]]
        )
        XCTAssertFalse(
            items.contains {
                $0.id == "run-approval:\(run.id):approval_external"
            }
        )
    }
}
