import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

final class GmailDeliveryService {
    private let decoder = JSONDecoder()

    init() {
        decoder.dateDecodingStrategy = .iso8601
    }

    func ensureValidSession(_ session: GmailSession) async throws -> GmailSession {
        if !session.isExpired {
            return session
        }
        return try await refreshSession(session)
    }

    func refreshSession(_ session: GmailSession) async throws -> GmailSession {
        let refreshed = try await refreshAccessToken(refreshToken: session.refreshToken)
        var updated = GmailSession(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken ?? session.refreshToken,
            expiryDate: Date().addingTimeInterval(refreshed.expiresIn),
            emailAddress: session.emailAddress
        )

        if updated.emailAddress == nil {
            let userInfo = try await fetchUserInfo(accessToken: updated.accessToken)
            updated.emailAddress = userInfo.email
        }

        return updated
    }

    func fetchUserInfo(accessToken: String) async throws -> GoogleUserInfo {
        var request = URLRequest(url: GoogleOAuthConfig.userInfoEndpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let data = try await send(request)
        return try decoder.decode(GoogleUserInfo.self, from: data)
    }

    func sendEmail(using session: GmailSession, item: QueuedEmail) async throws {
        let preparedItem = await enrich(item: item)
        let subject = "[Mail Moi] \(preparedItem.title)"
        let raw = try Self.makeRawMimeMessage(
            from: session.emailAddress ?? "me",
            to: preparedItem.toEmail,
            subject: subject,
            title: preparedItem.title,
            excerpt: preparedItem.excerpt,
            urlString: preparedItem.urlString
        )

        var request = URLRequest(url: GoogleOAuthConfig.gmailSendEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GmailSendRequest(raw: raw))
        _ = try await send(request)
    }

    private func refreshAccessToken(refreshToken: String) async throws -> TokenResponse {
        var request = URLRequest(url: GoogleOAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let bodyItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuthConfig.clientID),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]
        request.httpBody = bodyItems.percentEncodedQuery?.data(using: .utf8)
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

    private func enrich(item: QueuedEmail) async -> QueuedEmail {
        guard item.excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: item.urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let excerpt = await fetchExcerpt(for: url, title: item.title) else {
            return item
        }

        return QueuedEmail(
            id: item.id,
            toEmail: item.toEmail,
            title: item.title,
            excerpt: excerpt,
            urlString: item.urlString,
            createdAt: item.createdAt,
            lastError: item.lastError
        )
    }

    private func fetchExcerpt(for url: URL, title: String) async -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(Locale.preferredLanguages.prefix(2).joined(separator: ", "), forHTTPHeaderField: "Accept-Language")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 6

        do {
            let (data, response) = try await URLSession.mailMoiMetadata.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let html = decodeHTML(data: data) else {
                return nil
            }

            let metaTags = Self.extractMetaTags(from: html)
            if let excerpt = Self.extractExcerpt(fromMetaTags: metaTags) {
                return excerpt
            }

            return await Self.generateExcerpt(fromHTML: html, title: title)
        } catch {
            return nil
        }
    }

    private func decodeHTML(data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }

        if let unicode = String(data: data, encoding: .unicode) {
            return unicode
        }

        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }

        return nil
    }

    private static func makeRawMimeMessage(from: String, to: String, subject: String, title: String, excerpt: String, urlString: String) throws -> String {
        let boundary = "MailMoi-\(UUID().uuidString)"
        let subjectHeader = "=?UTF-8?B?\(Data(subject.utf8).base64EncodedString())?="
        let footer = "Sent with Mail Moi by nieder.me"
        let textBody = [
            title,
            "",
            excerpt,
            "",
            urlString,
            "",
            footer
        ].joined(separator: "\r\n")

        let htmlBody = """
        <h2 style="margin-bottom: 0;">\(escapeHTML(title))</h2>
        <p style="margin-bottom: 10px;">\(escapeHTML(excerpt))</p>
        <p style="margin-bottom: 50px;"><a href="\(escapeHTMLAttribute(urlString))">\(escapeHTML(urlString))</a></p>
        <p style="margin-bottom: 10px;">\(escapeHTML(footer))</p>
        """

        let message = """
        From: \(from)
        To: \(to)
        Subject: \(subjectHeader)
        MIME-Version: 1.0
        Content-Type: multipart/alternative; boundary="\(boundary)"

        --\(boundary)
        Content-Type: text/plain; charset="UTF-8"
        Content-Transfer-Encoding: 8bit

        \(textBody)
        --\(boundary)
        Content-Type: text/html; charset="UTF-8"
        Content-Transfer-Encoding: 8bit

        \(htmlBody)
        --\(boundary)--
        """

        guard let data = message.data(using: .utf8) else {
            throw GmailAPIError.invalidResponse
        }
        return data.base64URLEncodedString()
    }

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeHTMLAttribute(_ string: String) -> String {
        escapeHTML(string)
    }

    private static func extractMetaTags(from html: String) -> [[String: String]] {
        let pattern = "<meta\\b[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsHTML = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)).compactMap { match in
            let tag = nsHTML.substring(with: match.range)
            let attributes = parseAttributes(from: tag)
            return attributes.isEmpty ? nil : attributes
        }
    }

    private static func extractExcerpt(fromMetaTags tags: [[String: String]]) -> String? {
        let candidates = [
            ("property", "og:description"),
            ("name", "description"),
            ("name", "twitter:description")
        ]

        for (attribute, value) in candidates {
            if let content = tags.first(where: { $0[attribute]?.lowercased() == value })?["content"],
               let normalized = normalizedMetaContent(content) {
                return normalized
            }
        }

        return nil
    }

    private static func parseAttributes(from tag: String) -> [String: String] {
        let pattern = #"([a-zA-Z_:.-]+)\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [:]
        }

        let nsTag = tag as NSString
        var attributes: [String: String] = [:]

        for match in regex.matches(in: tag, range: NSRange(location: 0, length: nsTag.length)) {
            let key = nsTag.substring(with: match.range(at: 1)).lowercased()
            let valueRange: NSRange

            if match.range(at: 3).location != NSNotFound {
                valueRange = match.range(at: 3)
            } else if match.range(at: 4).location != NSNotFound {
                valueRange = match.range(at: 4)
            } else {
                valueRange = match.range(at: 5)
            }

            let value = nsTag.substring(with: valueRange)
            attributes[key] = value
        }

        return attributes
    }

    private static func normalizedMetaContent(_ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let wrapped = "<span>\(trimmed)</span>"
        guard let data = wrapped.data(using: .utf8) else {
            return trimmed
        }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            let normalized = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? nil : normalized
        }

        return trimmed
    }

    private static func generateExcerpt(fromHTML html: String, title: String) async -> String? {
        let preferredSection = extractPreferredSection(from: html) ?? html
        let strippedSection = stripNonContentTags(from: preferredSection)
        guard let plainText = plainText(fromHTMLForSummary: strippedSection) else {
            return nil
        }

        let cleanedText = normalizeArticleText(plainText, title: title)
        guard !cleanedText.isEmpty else {
            return nil
        }

        if let aiSummary = await summarizeWithFoundationModels(cleanedText, title: title) {
            return aiSummary
        }

        return summarize(cleanedText, maxWords: 160)
    }

    private static func extractPreferredSection(from html: String) -> String? {
        let patterns = [
            #"<article\b[^>]*>(.*?)</article>"#,
            #"<main\b[^>]*>(.*?)</main>"#,
            #"<body\b[^>]*>(.*?)</body>"#
        ]

        for pattern in patterns {
            if let section = firstMatch(in: html, pattern: pattern) {
                return section
            }
        }

        return nil
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges > 1,
              match.range(at: 1).location != NSNotFound else {
            return nil
        }

        return nsText.substring(with: match.range(at: 1))
    }

    private static func stripNonContentTags(from html: String) -> String {
        let patterns = [
            #"<script\b[^>]*>.*?</script>"#,
            #"<style\b[^>]*>.*?</style>"#,
            #"<noscript\b[^>]*>.*?</noscript>"#,
            #"<svg\b[^>]*>.*?</svg>"#,
            #"<header\b[^>]*>.*?</header>"#,
            #"<footer\b[^>]*>.*?</footer>"#,
            #"<nav\b[^>]*>.*?</nav>"#,
            #"<form\b[^>]*>.*?</form>"#
        ]

        return patterns.reduce(html) { partial, pattern in
            replaceMatches(in: partial, pattern: pattern, with: " ")
        }
    }

    private static func replaceMatches(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return text
        }

        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    private static func plainText(fromHTMLForSummary html: String) -> String? {
        let wrapped = """
        <html><body>\(html)</body></html>
        """

        guard let data = wrapped.data(using: .utf8) else {
            return nil
        }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed.string
        }

        return nil
    }

    private static func normalizeArticleText(_ text: String, title: String) -> String {
        let titleLower = title.lowercased()
        var seen = Set<String>()

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\u{00A0}", with: " ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { line -> String? in
                let collapsed = collapseWhitespace(in: line)
                guard !collapsed.isEmpty else {
                    return nil
                }

                let lowered = collapsed.lowercased()
                if lowered == titleLower || lowered.hasPrefix(titleLower + " |") || lowered.hasPrefix(titleLower + " -") {
                    return nil
                }

                guard !seen.contains(lowered) else {
                    return nil
                }
                seen.insert(lowered)
                return collapsed
            }

        return lines.joined(separator: "\n")
    }

    private static func summarize(_ text: String, maxWords: Int) -> String? {
        let paragraphs = text
            .components(separatedBy: .newlines)
            .map(collapseWhitespace(in:))
            .filter { !$0.isEmpty }

        var selectedSentences: [String] = []
        var wordCount = 0

        for paragraph in paragraphs {
            let sentences = splitIntoSentences(paragraph)
            let units = sentences.isEmpty ? [paragraph] : sentences

            for unit in units {
                let words = unit.split(whereSeparator: \.isWhitespace)
                guard !words.isEmpty else {
                    continue
                }

                if wordCount > 0 && wordCount + words.count > maxWords {
                    return selectedSentences.isEmpty ? truncate(unit, to: maxWords) : selectedSentences.joined(separator: " ")
                }

                selectedSentences.append(unit)
                wordCount += words.count

                if wordCount >= maxWords {
                    return selectedSentences.joined(separator: " ")
                }
            }
        }

        guard !selectedSentences.isEmpty else {
            return nil
        }

        return selectedSentences.joined(separator: " ")
    }

    private static func splitIntoSentences(_ text: String) -> [String] {
        let pattern = #"(?<=[.!?])\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }

        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        var parts: [String] = []
        var start = text.startIndex

        for match in regex.matches(in: text, range: fullRange) {
            guard let range = Range(match.range, in: text) else {
                continue
            }
            let sentence = text[start..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                parts.append(sentence)
            }
            start = range.upperBound
        }

        let remainder = text[start...].trimmingCharacters(in: .whitespacesAndNewlines)
        if !remainder.isEmpty {
            parts.append(String(remainder))
        }

        return parts
    }

    private static func truncate(_ text: String, to maxWords: Int) -> String {
        let words = text.split(whereSeparator: \.isWhitespace).prefix(maxWords)
        return words.joined(separator: " ")
    }

    private static func collapseWhitespace(in text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func summarizeWithFoundationModels(_ text: String, title: String) async -> String? {
#if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) else {
            return nil
        }

        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            return nil
        }

        let excerptSource = truncate(text, to: 700)
        let session = LanguageModelSession(model: model) {
            """
            You write short, factual summaries for saved links.
            Return plain text only.
            Use no more than 160 words.
            Do not repeat the title verbatim.
            Focus on the main point of the page.
            """
        }

        let prompt = """
        Title: \(title)

        Page content:
        \(excerptSource)
        """

        do {
            let response = try await session.respond(
                to: prompt,
                options: GenerationOptions(maximumResponseTokens: 220)
            )
            let normalized = collapseWhitespace(in: response.content)
            guard !normalized.isEmpty else {
                return nil
            }
            return truncate(normalized, to: 160)
        } catch {
            return nil
        }
#else
        return nil
#endif
    }
}

private extension URLSession {
    static let mailMoiMetadata: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 8
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()
}
