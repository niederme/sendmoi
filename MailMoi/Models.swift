import Foundation

struct ShareDraft: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var toEmail: String = ""
    var title: String = ""
    var excerpt: String = ""
    var summary: String = ""
    var urlString: String = ""
    var previewImageURLString: String?

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedExcerpt: String { excerpt.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedSummary: String { summary.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedURLString: String { urlString.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasPreviewImage: Bool {
        guard let previewImageURLString else {
            return false
        }

        return URL(string: previewImageURLString) != nil
    }

    var queueTitle: String {
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        if let host = URL(string: trimmedURLString)?.host?.replacingOccurrences(of: "www.", with: ""),
           !host.isEmpty {
            return host
        }

        if let firstExcerptLine = trimmedExcerpt
            .components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return firstExcerptLine
        }

        if hasPreviewImage {
            return "Shared Photo"
        }

        if !trimmedSummary.isEmpty {
            return "Shared Item"
        }

        return ""
    }

    var hasQueueContent: Bool {
        !trimmedTitle.isEmpty ||
        !trimmedExcerpt.isEmpty ||
        !trimmedSummary.isEmpty ||
        !trimmedURLString.isEmpty ||
        hasPreviewImage
    }

    var isValidForQueue: Bool {
        !toEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        hasQueueContent &&
        !queueTitle.isEmpty
    }
}

struct ParsedSocialPostShare {
    let title: String
    let excerpt: String
    let url: String?
}

enum SharedPostTextParser {
    static func markdownLikeLink(in text: String) -> (text: String, url: String)? {
        let pattern = #"^\[([^\]]+)\]\s*\((https?://[^)\s]+)\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, options: [], range: range),
            match.range.location != NSNotFound,
            let titleRange = Range(match.range(at: 1), in: text),
            let urlRange = Range(match.range(at: 2), in: text)
        else {
            return nil
        }

        let title = collapseWhitespace(in: String(text[titleRange]))
        let url = String(text[urlRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !url.isEmpty else {
            return nil
        }

        return (title, url)
    }

    static func firstMarkdownLikeLinkURL(in text: String) -> String? {
        let pattern = #"\[[^\]]+\]\s*\((https?://[^)\s]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, options: [], range: range),
            let urlRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return String(text[urlRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func plainTextByRenderingMarkdownLikeLinks(in text: String) -> String {
        let pattern = #"\[([^\]]+)\]\s*\((https?://[^)\s]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1")
    }

    static func parseSocialPostShare(in text: String) -> ParsedSocialPostShare? {
        let extractedLink = markdownLikeLink(in: text)
        let candidateSource = collapseWhitespace(in: extractedLink?.text ?? text)
        guard !candidateSource.isEmpty else {
            return nil
        }

        let unwrappedCandidate = unwrapBracketPair(in: candidateSource)
        let patterns = [
            #"^(.+?)\s+on\s+(X|Twitter)\s*:\s*["“](.+?)["”]\s*/\s*(?:X|Twitter)\s*$"#,
            #"^(.+?)\s+on\s+(X|Twitter)\s*:\s*(.+?)\s*/\s*(?:X|Twitter)\s*$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) else {
                continue
            }

            let range = NSRange(unwrappedCandidate.startIndex..<unwrappedCandidate.endIndex, in: unwrappedCandidate)
            guard
                let match = regex.firstMatch(in: unwrappedCandidate, options: [], range: range),
                match.numberOfRanges >= 4,
                let authorRange = Range(match.range(at: 1), in: unwrappedCandidate),
                let networkRange = Range(match.range(at: 2), in: unwrappedCandidate),
                let bodyRange = Range(match.range(at: 3), in: unwrappedCandidate)
            else {
                continue
            }

            let author = collapseWhitespace(in: String(unwrappedCandidate[authorRange]))
            let networkToken = collapseWhitespace(in: String(unwrappedCandidate[networkRange])).lowercased()
            let body = collapseWhitespace(in: String(unwrappedCandidate[bodyRange]))
            guard !author.isEmpty, !body.isEmpty else {
                continue
            }

            let networkLabel = networkToken == "twitter" ? "Twitter" : "X"
            return ParsedSocialPostShare(
                title: "\(author) on \(networkLabel)",
                excerpt: body,
                url: extractedLink?.url
            )
        }

        if let derivedFromLink = derivedSocialPostShare(from: extractedLink?.url) {
            return derivedFromLink
        }

        return nil
    }

    static func derivedSocialPostShare(from urlString: String?) -> ParsedSocialPostShare? {
        guard
            let urlString = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
            !urlString.isEmpty,
            let url = URL(string: urlString),
            let host = url.host?.lowercased(),
            let networkLabel = socialNetworkLabel(for: host)
        else {
            return nil
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 3 else {
            return ParsedSocialPostShare(
                title: "Post on \(networkLabel)",
                excerpt: "",
                url: url.absoluteString
            )
        }

        let normalizedComponents = pathComponents.map { $0.lowercased() }
        guard let statusIndex = normalizedComponents.firstIndex(of: "status"),
              statusIndex > 0,
              statusIndex + 1 < pathComponents.count else {
            return nil
        }

        let handle = normalizedHandle(pathComponents[statusIndex - 1])
        let title: String
        if let handle {
            title = "Post on \(networkLabel) by @\(handle)"
        } else {
            title = "Post on \(networkLabel)"
        }

        return ParsedSocialPostShare(
            title: title,
            excerpt: "",
            url: url.absoluteString
        )
    }

    private static func unwrapBracketPair(in text: String) -> String {
        guard text.hasPrefix("["),
              text.hasSuffix("]"),
              text.count > 2 else {
            return text
        }

        return String(text.dropFirst().dropLast())
    }

    private static func collapseWhitespace(in text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func socialNetworkLabel(for host: String) -> String? {
        switch host {
        case "x.com", "www.x.com":
            return "X"
        case "twitter.com", "www.twitter.com":
            return "Twitter"
        default:
            return nil
        }
    }

    private static func normalizedHandle(_ candidate: String) -> String? {
        let trimmedCandidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "@/"))
        guard !trimmedCandidate.isEmpty else {
            return nil
        }

        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard trimmedCandidate.unicodeScalars.allSatisfy(allowedCharacters.contains) else {
            return nil
        }

        return trimmedCandidate
    }
}

enum SharedContentFormatter {
    static func normalizedTitle(_ title: String, urlString: String?) -> String {
        let collapsed = collapseWhitespace(in: title)
        guard !collapsed.isEmpty else {
            return collapsed
        }

        guard let host = URL(string: urlString ?? "")?.host?.lowercased() else {
            return collapsed
        }

        if host == "overcast.fm" || host == "www.overcast.fm" {
            let suffixes = [" — Overcast", " - Overcast", " | Overcast"]
            for suffix in suffixes {
                if collapsed.hasSuffix(suffix) {
                    let trimmed = String(collapsed.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }
        }

        return collapsed
    }

    private static func collapseWhitespace(in text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct QueuedEmail: Codable, Identifiable, Equatable {
    let id: UUID
    let toEmail: String
    let title: String
    let excerpt: String
    let summary: String?
    let urlString: String
    let previewImageURLString: String?
    let createdAt: Date
    var lastError: String?

    init(
        id: UUID = UUID(),
        toEmail: String,
        title: String,
        excerpt: String,
        summary: String? = nil,
        urlString: String,
        previewImageURLString: String? = nil,
        createdAt: Date = .now,
        lastError: String? = nil
    ) {
        self.id = id
        self.toEmail = toEmail
        self.title = title
        self.excerpt = excerpt
        self.summary = summary
        self.urlString = urlString
        self.previewImageURLString = previewImageURLString
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
