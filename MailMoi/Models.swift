import Foundation

struct ShareDraft: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var toEmail: String = ""
    var title: String = ""
    var excerpt: String = ""
    var urlString: String = ""

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedExcerpt: String { excerpt.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedURLString: String { urlString.trimmingCharacters(in: .whitespacesAndNewlines) }

    var isValidForQueue: Bool {
        !toEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !trimmedTitle.isEmpty &&
        URL(string: trimmedURLString) != nil
    }
}

struct QueuedEmail: Codable, Identifiable, Equatable {
    let id: UUID
    let toEmail: String
    let title: String
    let excerpt: String
    let urlString: String
    let createdAt: Date
    var lastError: String?

    init(id: UUID = UUID(), toEmail: String, title: String, excerpt: String, urlString: String, createdAt: Date = .now, lastError: String? = nil) {
        self.id = id
        self.toEmail = toEmail
        self.title = title
        self.excerpt = excerpt
        self.urlString = urlString
        self.createdAt = createdAt
        self.lastError = lastError
    }
}

struct GmailSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiryDate: Date
    var emailAddress: String?

    var isExpired: Bool {
        expiryDate <= Date().addingTimeInterval(60)
    }
}

struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: TimeInterval
    let refreshToken: String?
    let scope: String?
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
    }
}

struct GmailProfile: Decodable {
    let emailAddress: String
    let messagesTotal: Int?
    let threadsTotal: Int?
}

struct GoogleUserInfo: Decodable {
    let email: String
    let verifiedEmail: Bool?

    enum CodingKeys: String, CodingKey {
        case email
        case verifiedEmail = "verified_email"
    }
}

struct GmailSendRequest: Encodable {
    let raw: String
}
