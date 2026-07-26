import AuthenticationServices
import Foundation
import OSLog
import UIKit

private let oauthLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.bryan.hibro",
    category: "OAuth"
)

@MainActor
final class OAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var webSession: ASWebAuthenticationSession?

    func authenticate(baseURL: URL) async throws -> OAuthTokenSet {
        oauthLogger.notice("Starting OAuth discovery")
        let metadataURL = baseURL.appending(
            path: ".well-known/oauth-authorization-server"
        )
        let (metadataData, metadataResponse) = try await URLSession.shared.data(
            from: metadataURL
        )
        try CoreAPI.validate(metadataResponse, data: metadataData)
        let metadata = try JSONDecoder().decode(OAuthMetadata.self, from: metadataData)
        let authorizationEndpoint = try Self.validatedEndpoint(
            metadata.authorizationEndpoint,
            baseURL: baseURL
        )
        let tokenURL = try Self.validatedEndpoint(
            metadata.tokenEndpoint,
            baseURL: baseURL
        )
        _ = try Self.validatedEndpoint(metadata.issuer, baseURL: baseURL)

        let verifier = try PKCE.verifier()
        let state = try PKCE.verifier(byteCount: 24)
        guard var components = URLComponents(
            url: authorizationEndpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw OAuthError.invalidServerURL
        }
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: CoreAPI.clientID),
            URLQueryItem(name: "redirect_uri", value: CoreAPI.redirectURI),
            URLQueryItem(name: "scope", value: "hibro.read hibro.run"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let authorizationURL = components.url else {
            throw OAuthError.invalidServerURL
        }

        oauthLogger.notice("Presenting system authentication session")
        let callback = try await beginSession(url: authorizationURL)
        oauthLogger.notice("OAuth callback received")
        guard let callbackComponents = URLComponents(
            url: callback,
            resolvingAgainstBaseURL: false
        ) else {
            throw OAuthError.invalidCallback
        }
        guard callbackComponents.scheme?.lowercased() == "hibro",
              callbackComponents.host?.lowercased() == "oauth",
              callbackComponents.path == "/callback"
        else {
            throw OAuthError.invalidCallback
        }
        var values: [String: String] = [:]
        for item in callbackComponents.queryItems ?? [] where values[item.name] == nil {
            values[item.name] = item.value
        }
        if let error = values["error"] {
            throw OAuthError.authorizationDenied(error)
        }
        guard values["state"] == state else { throw OAuthError.stateMismatch }
        guard let code = values["code"] else { throw OAuthError.invalidCallback }

        var request = URLRequest(url: tokenURL)
        request.timeoutInterval = 30
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "content-type"
        )
        request.httpBody = FormEncoding.data([
            "grant_type": "authorization_code",
            "client_id": CoreAPI.clientID,
            "redirect_uri": CoreAPI.redirectURI,
            "code": code,
            "code_verifier": verifier
        ])
        oauthLogger.notice("Exchanging OAuth authorization code")
        let (data, response) = try await URLSession.shared.data(for: request)
        try CoreAPI.validate(response, data: data)
        let tokenSet = try JSONDecoder().decode(
            OAuthTokenResponse.self,
            from: data
        ).tokenSet
        oauthLogger.notice("OAuth sign-in completed")
        return tokenSet
    }

    func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap {
            $0 as? UIWindowScene
        }
        return scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private func beginSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let completion: (URL?, Error?) -> Void = {
                [weak self] callback, error in
                self?.webSession = nil
                if let error {
                    oauthLogger.error(
                        "OAuth session failed: \(error.localizedDescription, privacy: .public)"
                    )
                    continuation.resume(throwing: error)
                } else if let callback {
                    continuation.resume(returning: callback)
                } else {
                    oauthLogger.error("OAuth session ended without a callback")
                    continuation.resume(throwing: OAuthError.invalidCallback)
                }
            }
            let session: ASWebAuthenticationSession
            if #available(iOS 17.4, *) {
                session = ASWebAuthenticationSession(
                    url: url,
                    callback: .customScheme("hibro"),
                    completionHandler: completion
                )
            } else {
                session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: "hibro",
                    completionHandler: completion
                )
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webSession = session
            guard session.start() else {
                oauthLogger.error("Unable to start OAuth system session")
                webSession = nil
                continuation.resume(throwing: OAuthError.invalidCallback)
                return
            }
        }
    }

    nonisolated static func validatedEndpoint(
        _ value: String,
        baseURL: URL
    ) throws -> URL {
        guard let endpoint = URL(string: value),
              let endpointComponents = URLComponents(
                url: endpoint,
                resolvingAgainstBaseURL: false
              ),
              let baseComponents = URLComponents(
                url: baseURL,
                resolvingAgainstBaseURL: false
              ),
              endpointComponents.user == nil,
              endpointComponents.password == nil,
              endpointComponents.scheme?.lowercased()
                == baseComponents.scheme?.lowercased(),
              endpointComponents.host?.lowercased()
                == baseComponents.host?.lowercased(),
              normalizedPort(endpointComponents)
                == normalizedPort(baseComponents)
        else {
            throw OAuthError.invalidServerURL
        }
        return endpoint
    }

    nonisolated private static func normalizedPort(
        _ components: URLComponents
    ) -> Int? {
        if let port = components.port { return port }
        switch components.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}
