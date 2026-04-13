import AuthenticationServices
import CryptoKit
import SwiftUI

#if os(iOS)
import UIKit
typealias PlatformViewController = UIViewController
typealias PlatformHostingController<Content: View> = UIHostingController<Content>
#elseif os(macOS)
import AppKit
typealias PlatformViewController = NSViewController
typealias PlatformHostingController<Content: View> = NSHostingController<Content>
#endif

final class ShareViewController: PlatformViewController {
    private let model = ShareExtensionModel()
    private lazy var gmailAuthenticator = ShareExtensionGoogleAuthenticator(presentingViewController: self)

    #if os(macOS)
    private let preferredExtensionSize = NSSize(width: 520, height: 620)
    #endif

    #if os(macOS)
    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: preferredExtensionSize))
    }

    override func keyDown(with event: NSEvent) {
        // Escape
        if event.keyCode == 53 {
            model.cancel()
            return
        }
        // ⌘W
        if event.modifierFlags.contains(.command) && event.characters == "w" {
            model.cancel()
            return
        }
        super.keyDown(with: event)
    }
    #endif

    override func viewDidLoad() {
        super.viewDidLoad()

        model.attach(extensionContext: extensionContext)
        model.requestGmailConnection = { [weak self] in
            guard let self else {
                throw GmailAPIError.authorizationFailed("Google sign-in is no longer available.")
            }

            return try await self.gmailAuthenticator.signIn()
        }
        let hostingController = PlatformHostingController(rootView: ShareView(model: model))

        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        #if os(iOS)
        hostingController.didMove(toParent: self)
        #elseif os(macOS)
        preferredContentSize = preferredExtensionSize
        #endif
        model.loadInitialContent()
    }
}

private struct OAuthAuthorizationRequest {
    let url: URL
    let codeVerifier: String
    let state: String
}

@MainActor
private final class ShareExtensionGoogleAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private weak var presentingViewController: PlatformViewController?
    private let decoder = JSONDecoder()
    private let deliveryService = GmailDeliveryService()
    private var webAuthenticationSession: ASWebAuthenticationSession?

    init(presentingViewController: PlatformViewController) {
        self.presentingViewController = presentingViewController
        decoder.dateDecodingStrategy = .iso8601
    }

    func signIn() async throws -> GmailSession {
        guard GoogleOAuthConfig.isConfigured else {
            throw GmailAPIError.notConfigured
        }

        guard presentationAnchor != nil else {
            throw GmailAPIError.authorizationFailed("Google sign-in could not be presented from the share sheet.")
        }

        let request = try makeAuthorizationRequest()
        let callbackURL = try await authenticateWithGoogle(
            url: request.url,
            callbackScheme: GoogleOAuthConfig.redirectScheme
        )
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
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
        let userInfo = try await deliveryService.fetchUserInfo(accessToken: session.accessToken)
        session.emailAddress = userInfo.email
        return session
    }

    private func authenticateWithGoogle(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                self?.webAuthenticationSession = nil

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
            self.webAuthenticationSession = session

            guard session.start() else {
                self.webAuthenticationSession = nil
                continuation.resume(
                    throwing: GmailAPIError.authorizationFailed("Google sign-in could not start from the share sheet.")
                )
                return
            }
        }
    }

    private func exchangeCodeForTokens(code: String, codeVerifier: String) async throws -> TokenResponse {
        var request = URLRequest(url: GoogleOAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            URLQueryItem(name: "client_id", value: GoogleOAuthConfig.clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: GoogleOAuthConfig.redirectURI)
        ].percentEncodedQuery?.data(using: .utf8)

        let data = try await send(request)
        return try decoder.decode(TokenResponse.self, from: data)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GmailAPIError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                if let message = Self.extractErrorMessage(from: data) {
                    throw GmailAPIError.api(message)
                }
                throw GmailAPIError.api("Google API returned status \(httpResponse.statusCode).")
            }

            return data
        } catch let error as GmailAPIError {
            throw error
        } catch {
            throw GmailAPIError.transport(error)
        }
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

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let presentationAnchor else {
            preconditionFailure("No presentation anchor available for share-sheet Google sign-in.")
        }

        return presentationAnchor
    }

    private var presentationAnchor: ASPresentationAnchor? {
        #if os(iOS)
        return presentingViewController?.view.window
        #elseif os(macOS)
        return presentingViewController?.view.window
        #else
        return nil
        #endif
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
