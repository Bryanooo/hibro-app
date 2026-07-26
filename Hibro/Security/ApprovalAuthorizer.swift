import LocalAuthentication

enum ApprovalAuthorizer {
    static func authorize() async throws {
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        var error: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &error
        ) else {
            throw ApprovalAuthorizationError.unavailable(
                error?.localizedDescription
            )
        }
        let allowed = try await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "确认这是你本人做出的 Agent 审批决定"
        )
        if !allowed {
            throw ApprovalAuthorizationError.denied
        }
    }
}

enum ApprovalAuthorizationError: LocalizedError {
    case unavailable(String?)
    case denied

    var errorDescription: String? {
        switch self {
        case .unavailable(let detail):
            detail ?? "设备未启用 Face ID、Touch ID 或锁屏密码。"
        case .denied:
            "身份验证未通过，审批决定没有提交。"
        }
    }
}
