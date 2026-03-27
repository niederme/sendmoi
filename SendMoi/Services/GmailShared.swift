import Foundation

enum GmailAPIError: LocalizedError {
    case notConfigured
    case invalidResponse
    case missingRefreshToken
    case invalidRedirect
    case invalidState
    case signInCanceled
    case insufficientAuthenticationScopes
    case authorizationFailed(String)
    case rateLimitExceeded(String)
    case transport(Error)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add your Google OAuth client ID in GoogleOAuthConfig.swift before signing in."
        case .invalidResponse:
            return "Google returned an unexpected response."
        case .missingRefreshToken:
            return "Google did not return a refresh token. Re-authenticate and keep prompt=consent enabled."
        case .invalidRedirect:
            return "The OAuth redirect could not be parsed."
        case .invalidState:
            return "The OAuth redirect did not match the original sign-in request."
        case .signInCanceled:
            return "Google sign-in was canceled."
        case .insufficientAuthenticationScopes:
            return "Reconnect Gmail to grant send permission."
        case .authorizationFailed(let message):
            return message
        case .rateLimitExceeded(let message):
            return message
        case .transport(let error):
            return error.localizedDescription
        case .api(let message):
            return message
        }
    }

    var requiresReconnect: Bool {
        switch self {
        case .insufficientAuthenticationScopes:
            return true
        default:
            return false
        }
    }

    static func indicatesInsufficientAuthenticationScopes(_ message: String) -> Bool {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized.localizedCaseInsensitiveContains("insufficient authentication scopes")
            || normalized.localizedCaseInsensitiveContains("grant send permission")
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

extension Array where Element == URLQueryItem {
    var percentEncodedQuery: String? {
        var components = URLComponents()
        components.queryItems = self
        return components.percentEncodedQuery
    }
}
