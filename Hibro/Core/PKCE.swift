import CryptoKit
import Foundation
import Security

enum PKCE {
    static func verifier(byteCount: Int = 32) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw OAuthError.randomGenerationFailed(status)
        }
        return Data(bytes).base64URLEncodedString()
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum OAuthError: LocalizedError {
    case invalidServerURL
    case invalidCallback
    case stateMismatch
    case authorizationDenied(String)
    case randomGenerationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL: "Core 地址无效"
        case .invalidCallback: "登录回调无效"
        case .stateMismatch: "登录状态校验失败，请重试"
        case .authorizationDenied(let message): message
        case .randomGenerationFailed: "无法生成安全随机数"
        }
    }
}
