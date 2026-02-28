import Foundation

enum GoogleOAuthConfig {
    static let clientID = "958893096854-nioq7ak84uq1vfs1ouh0uv5t2g3tksn6.apps.googleusercontent.com"
    static var redirectScheme: String {
        "com.googleusercontent.apps.\(clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: ""))"
    }
    static var redirectURI: String {
        "\(redirectScheme):/oauth2redirect/google"
    }
    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let userInfoEndpoint = URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!
    static let gmailProfileEndpoint = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!
    static let gmailSendEndpoint = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send")!
    static let scopes = [
        "https://www.googleapis.com/auth/gmail.send",
        "email",
        "openid"
    ]

    static var isConfigured: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

