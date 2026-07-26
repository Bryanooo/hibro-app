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

    func testCoreInboxResponseMapsRunApproval() throws {
        let data = Data(
            """
            {
              "items": [{
                "id": "run-approval:run_1:approval_1",
                "kind": "approval",
                "title": "允许执行命令",
                "summary": "npm test",
                "createdAt": "2026-07-26T12:00:00.000Z",
                "requiresAttention": true,
                "runId": "run_1",
                "conversationId": null,
                "approval": {
                  "source": "run",
                  "activityId": null,
                  "externalId": "approval_1",
                  "decisions": ["allow_once", "deny"],
                  "resolvable": true,
                  "reason": null
                }
              }],
              "serverTime": "2026-07-26T12:00:01.000Z"
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(
            CoreInboxResponse.self,
            from: data
        )
        let item = try XCTUnwrap(
            response.items.first.flatMap(InboxItem.init(coreItem:))
        )

        XCTAssertEqual(item.kind, .approval)
        XCTAssertEqual(item.runID, "run_1")
        XCTAssertEqual(
            item.approvalSource,
            .run(externalID: "approval_1")
        )
    }

    func testTimedOutRunHasFriendlyRetryPresentation() {
        let run = CoreRun(
            id: "run_timeout",
            commandId: "command_timeout",
            nodeId: "node_1",
            agentId: "agent_1",
            localAgentId: "local_1",
            localRunId: "local_run_1",
            status: "timed_out",
            prompt: "执行耗时任务",
            sessionKey: nil,
            result: nil,
            error: [
                "code": .string("execution_timeout"),
                "message": .string("Execution timed out after 60 seconds")
            ],
            requestedBy: "user_1",
            createdAt: "2026-07-26T12:00:00.000Z",
            updatedAt: "2026-07-26T12:01:00.000Z",
            startedAt: "2026-07-26T12:00:01.000Z",
            finishedAt: "2026-07-26T12:01:00.000Z"
        )

        XCTAssertTrue(run.canRetry)
        XCTAssertEqual(run.failurePresentation?.title, "执行超时")
        XCTAssertTrue(
            run.failurePresentation?.suggestion.contains("重试") == true
        )
    }
}
