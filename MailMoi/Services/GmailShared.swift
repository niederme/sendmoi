import Foundation

enum GmailAPIError: LocalizedError {
    case notConfigured
    case invalidResponse
    case missingRefreshToken
    case invalidRedirect
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
        case .transport(let error):
            return error.localizedDescription
        case .api(let message):
            return message
        }
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
