import CryptoKit
import Foundation
import AuthenticationServices

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct OAuthAuthorizationRequest {
    let url: URL
    let codeVerifier: String
    let state: String
}

final class GmailAPIClient {
    private let decoder = JSONDecoder()
    private let deliveryService = GmailDeliveryService()

    init() {
        decoder.dateDecodingStrategy = .iso8601
    }

    func signIn() async throws -> GmailSession {
        guard GoogleOAuthConfig.isConfigured else {
            throw GmailAPIError.notConfigured
        }

        let request = try makeAuthorizationRequest()
        let callbackURL = try await authenticateWithGoogle(
            url: request.url,
            callbackScheme: GoogleOAuthConfig.redirectScheme
        )
        guard
            let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        else {
            throw GmailAPIError.invalidRedirect
        }

        guard components.queryItems?.first(where: { $0.name == "state" })?.value == request.state else {
            throw GmailAPIError.invalidState
        }

        if let authorizationError = Self.authorizationError(from: components.queryItems ?? []) {
            throw authorizationError
        }

        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GmailAPIError.invalidRedirect
        }

        let tokenResponse = try await exchangeCodeForTokens(code: code, codeVerifier: request.codeVerifier)
        guard let refreshToken = tokenResponse.refreshToken else {
            throw GmailAPIError.missingRefreshToken
        }

        var session = GmailSession(
            accessToken: tokenResponse.accessToken,
            refreshToken: refreshToken,
            expiryDate: Date().addingTimeInterval(tokenResponse.expiresIn)
        )
        let userInfo = try await fetchUserInfo(accessToken: session.accessToken)
        session.emailAddress = userInfo.email
        return session
    }

    func ensureValidSession(_ session: GmailSession) async throws -> GmailSession {
        try await deliveryService.ensureValidSession(session)
    }

    func refreshSession(_ session: GmailSession) async throws -> GmailSession {
        try await deliveryService.refreshSession(session)
    }

    func fetchUserInfo(accessToken: String) async throws -> GoogleUserInfo {
        try await deliveryService.fetchUserInfo(accessToken: accessToken)
    }

    func fetchProfile(accessToken: String) async throws -> GmailProfile {
        var request = URLRequest(url: GoogleOAuthConfig.gmailProfileEndpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let data = try await send(request)
        return try decoder.decode(GmailProfile.self, from: data)
    }

    func sendEmail(using session: GmailSession, item: QueuedEmail) async throws {
        try await deliveryService.sendEmail(using: session, item: item)
    }

    private func exchangeCodeForTokens(code: String, codeVerifier: String) async throws -> TokenResponse {
        var request = URLRequest(url: GoogleOAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let bodyItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuthConfig.clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: GoogleOAuthConfig.redirectURI)
        ]
        request.httpBody = bodyItems.percentEncodedQuery?.data(using: .utf8)
        let data = try await send(request)
        return try decoder.decode(TokenResponse.self, from: data)
    }

    @MainActor
    private func authenticateWithGoogle(url: URL, callbackScheme: String) async throws -> URL {
        let coordinator = OAuthCoordinator()
        return try await coordinator.authenticate(url: url, callbackScheme: callbackScheme)
    }

    private func makeAuthorizationRequest() throws -> OAuthAuthorizationRequest {
        let codeVerifier = Self.randomVerifier()
        let challenge = Self.codeChallenge(for: codeVerifier)
        let state = Self.randomState()
        var components = URLComponents(url: GoogleOAuthConfig.authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: GoogleOAuthConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleOAuthConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let url = components?.url else {
            throw GmailAPIError.invalidResponse
        }
        return OAuthAuthorizationRequest(url: url, codeVerifier: codeVerifier, state: state)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GmailAPIError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw Self.apiError(from: data, statusCode: httpResponse.statusCode)
            }

            return data
        } catch let error as GmailAPIError {
            throw error
        } catch {
            throw GmailAPIError.transport(error)
        }
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? [String: Any]
        else {
            return nil
        }

        if let message = error["message"] as? String {
            return message
        }

        if let details = error["errors"] as? [[String: Any]],
           let first = details.first,
           let message = first["message"] as? String {
            return message
        }

        return nil
    }

    private static func apiError(from data: Data, statusCode: Int) -> GmailAPIError {
        if let message = extractErrorMessage(from: data) {
            if GmailAPIError.indicatesInsufficientAuthenticationScopes(message) {
                return .insufficientAuthenticationScopes
            }

            return .api(message)
        }

        return .api("Google API returned status \(statusCode).")
    }

    private static func authorizationError(from queryItems: [URLQueryItem]) -> GmailAPIError? {
        guard let code = queryItems.first(where: { $0.name == "error" })?.value else {
            return nil
        }

        let description = queryItems
            .first(where: { $0.name == "error_description" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if code == "access_denied" {
            return .signInCanceled
        }

        if let description, !description.isEmpty {
            return .authorizationFailed("Google sign-in failed: \(description)")
        }

        return .authorizationFailed("Google sign-in failed (\(code)).")
    }

    private static func randomVerifier() -> String {
        let charset = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<64).compactMap { _ in charset.randomElement() })
    }

    private static func randomState() -> String {
        let charset = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<32).compactMap { _ in charset.randomElement() })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

}

@MainActor
private final class OAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                self.session = nil

                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: GmailAPIError.signInCanceled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(throwing: GmailAPIError.invalidRedirect)
                }
            }

            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = self
            self.session = session

            guard session.start() else {
                self.session = nil
                continuation.resume(
                    throwing: GmailAPIError.authorizationFailed("Google sign-in could not start.")
                )
                return
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        if let window = windowScenes.lazy.compactMap(\.keyWindow).first {
            return window
        }

        if let windowScene = windowScenes.first {
            return ASPresentationAnchor(windowScene: windowScene)
        }

        preconditionFailure("No UIWindowScene available for OAuth presentation.")
        #elseif os(macOS)
        return NSApp.keyWindow ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

#if os(iOS)
private extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first(where: \.isKeyWindow)
    }
}
#endif
