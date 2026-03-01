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
        let content = await buildEmailContent(from: item)
        let subject = "\(content.title) (Sent via MailMoi)"
        let raw = try Self.makeRawMimeMessage(
            from: session.emailAddress ?? "me",
            to: item.toEmail,
            subject: subject,
            content: content
        )

        var request = URLRequest(url: GoogleOAuthConfig.gmailSendEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GmailSendRequest(raw: raw))
        _ = try await send(request)
    }

    func fetchDraftPreview(urlString: String, fallbackTitle: String) async -> DraftPreviewMetadata? {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        guard let metadata = await fetchArticleMetadata(for: url, fallbackTitle: fallbackTitle) else {
            return nil
        }

        return DraftPreviewMetadata(
            title: metadata.title,
            description: metadata.excerpt,
            summary: metadata.summary,
            imageURLString: metadata.imageURLString
        )
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

    private func buildEmailContent(from item: QueuedEmail) async -> EmailContent {
        let fallbackTitle = Self.renderMarkdownLinksAsPlainText(in: item.title)
        let fallbackExcerpt = Self.renderMarkdownLinksAsPlainText(in: item.excerpt)
        let fallbackSummary = item.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackImageURLString = item.previewImageURLString
        let fallbackURLString = Self.preferredURLString(
            from: item.urlString,
            title: item.title,
            excerpt: item.excerpt
        )

        guard let url = URL(string: fallbackURLString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return EmailContent(
                title: fallbackTitle,
                excerpt: fallbackExcerpt,
                summary: fallbackSummary,
                urlString: fallbackURLString,
                imageURLString: fallbackImageURLString,
                inlineImage: await fetchInlineImage(from: fallbackImageURLString)
            )
        }

        guard let metadata = await fetchArticleMetadata(for: url, fallbackTitle: fallbackTitle) else {
            return EmailContent(
                title: fallbackTitle,
                excerpt: fallbackExcerpt,
                summary: fallbackSummary,
                urlString: fallbackURLString,
                imageURLString: fallbackImageURLString,
                inlineImage: await fetchInlineImage(from: fallbackImageURLString)
            )
        }

        let resolvedURLString = metadata.urlString ?? fallbackURLString
        let resolvedImageURLString = metadata.imageURLString ?? fallbackImageURLString
        let inlineImage = await fetchInlineImage(from: resolvedImageURLString)

        return EmailContent(
            title: metadata.title ?? fallbackTitle,
            excerpt: metadata.excerpt ?? fallbackExcerpt,
            summary: metadata.summary ?? fallbackSummary,
            urlString: resolvedURLString,
            imageURLString: inlineImage == nil ? nil : resolvedImageURLString,
            inlineImage: inlineImage
        )
    }

    private func fetchArticleMetadata(for url: URL, fallbackTitle: String) async -> FetchedArticleMetadata? {
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
            let title = Self.extractPreferredTitle(fromHTML: html, metaTags: metaTags) ?? fallbackTitle
            let excerpt = Self.extractExcerpt(fromMetaTags: metaTags)
            let summary = await Self.generateSummary(fromHTML: html, title: title, excerpt: excerpt)

            return FetchedArticleMetadata(
                title: title,
                excerpt: excerpt,
                summary: summary,
                urlString: Self.extractPreferredURLString(fromHTML: html, metaTags: metaTags, baseURL: url),
                imageURLString: Self.extractPreferredImageURLString(fromHTML: html, metaTags: metaTags, baseURL: url)
            )
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

    private func fetchInlineImage(from urlString: String?) async -> InlineImage? {
        guard let urlString,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        do {
            let (data, response) = try await URLSession.mailMoiMetadata.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  !data.isEmpty,
                  let mimeType = Self.supportedImageMimeType(
                    responseMimeType: httpResponse.mimeType,
                    urlString: urlString
                  ) else {
                return nil
            }

            return InlineImage(
                contentID: "mailmoi-inline-image-\(UUID().uuidString)",
                mimeType: mimeType,
                filename: "mailmoi-image.\(Self.fileExtension(forMimeType: mimeType))",
                data: data
            )
        } catch {
            return nil
        }
    }

    private static func makeRawMimeMessage(from: String, to: String, subject: String, content: EmailContent) throws -> String {
        let boundary = "MailMoi-\(UUID().uuidString)"
        let subjectHeader = "=?UTF-8?B?\(Data(subject.utf8).base64EncodedString())?="
        let footer = "Sent with MailMoi"
        let textBody = makePlainTextBody(content: content, footer: footer)
        let htmlBody = makeHTMLBody(content: content, footer: footer)
        let message: String

        if let inlineImage = content.inlineImage {
            let alternativeBoundary = "MailMoiAlt-\(UUID().uuidString)"
            let imageData = wrappedBase64(inlineImage.data.base64EncodedString())

            message = """
            From: \(from)
            To: \(to)
            Subject: \(subjectHeader)
            MIME-Version: 1.0
            Content-Type: multipart/related; boundary="\(boundary)"

            --\(boundary)
            Content-Type: multipart/alternative; boundary="\(alternativeBoundary)"

            --\(alternativeBoundary)
            Content-Type: text/plain; charset="UTF-8"
            Content-Transfer-Encoding: 8bit

            \(textBody)
            --\(alternativeBoundary)
            Content-Type: text/html; charset="UTF-8"
            Content-Transfer-Encoding: 8bit

            \(htmlBody)
            --\(alternativeBoundary)--
            --\(boundary)
            Content-Type: \(inlineImage.mimeType); name="\(inlineImage.filename)"
            Content-Transfer-Encoding: base64
            Content-ID: <\(inlineImage.contentID)>
            X-Attachment-Id: \(inlineImage.contentID)
            Content-Location: \(content.imageURLString ?? inlineImage.filename)
            Content-Disposition: inline; filename="\(inlineImage.filename)"

            \(imageData)
            --\(boundary)--
            """
        } else {
            message = """
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
        }

        guard let data = message.data(using: .utf8) else {
            throw GmailAPIError.invalidResponse
        }
        return data.base64URLEncodedString()
    }

    private static func makePlainTextBody(content: EmailContent, footer: String) -> String {
        var lines = [content.title]

        if !content.excerpt.isEmpty {
            lines.append("")
            lines.append(content.excerpt)
        }

        if let summary = content.summary, !summary.isEmpty {
            lines.append("")
            lines.append("SUMMARY")
            lines.append(summary)
        }

        lines.append("")
        lines.append("Source: \(content.urlString)")
        lines.append("")
        lines.append(footer)

        return lines.joined(separator: "\r\n")
    }

    private static func makeHTMLBody(content: EmailContent, footer: String) -> String {
        let fontFamily = "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'SF Pro Display', 'Helvetica Neue', Arial, sans-serif"
        let hasImage = content.inlineImage != nil
        let titleTopPadding = hasImage ? "20px" : "50px"
        let imageBlock = makeImageBlock(content: content)
        let excerptBlock = content.excerpt.isEmpty ? "" : """
                            <tr>
                              <td class="mm-card-pad mm-excerpt" style="padding: 15px 50px 20px 50px; font-family: \(fontFamily); font-size: 26px; line-height: 31px; color: #111111;">
                                \(escapeHTML(content.excerpt))
                              </td>
                            </tr>
                            """
        let summaryBlock = makeSummaryBlock(content: content, fontFamily: fontFamily)

        return """
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
            <style>
              .mm-title-link, .mm-title-link:visited { color: #111111 !important; text-decoration: none !important; }
              .mm-title-link:hover { text-decoration: underline !important; }
              @media only screen and (max-width: 620px) {
                .mm-shell { padding-top: 25px !important; padding-right: 0 !important; padding-bottom: 25px !important; padding-left: 0 !important; background-color: #f9f8f5 !important; }
                .mm-card { border-left: 0 !important; border-right: 0 !important; border-radius: 0 !important; }
                .mm-card-pad { padding-left: 15px !important; padding-right: 15px !important; }
                .mm-image-pad { padding-top: 15px !important; }
                .mm-title-pad { padding-top: 15px !important; }
                .mm-card-bottom { padding-bottom: 50px !important; }
                .mm-title { font-size: 26px !important; line-height: 31px !important; }
                .mm-excerpt { font-size: 20px !important; line-height: 24px !important; padding-top: 15px !important; padding-bottom: 20px !important; }
                .mm-summary-label { font-size: 14px !important; line-height: 20px !important; color: #111111 !important; }
                .mm-summary-copy { font-size: 16px !important; line-height: 22px !important; }
                .mm-attribution { padding-top: 25px !important; padding-bottom: 25px !important; background-color: #f9f8f5 !important; }
              }
            </style>
          </head>
          <body style="margin: 0; padding: 0; background-color: #f9f8f5;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse: collapse; width: 100%; background-color: #f9f8f5;">
              <tr>
                <td class="mm-shell" align="center" style="padding: 50px 24px 24px 24px; background-color: #f9f8f5;">
                  <div style="margin: 0 auto; max-width: 850px;">
                    <table class="mm-card" role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse: separate; width: 100%; background-color: #ffffff; border: 1px solid #eaeaea; border-radius: 25px;">
                      \(imageBlock)
                      <tr>
                        <td class="mm-card-pad mm-title-pad" style="padding: \(titleTopPadding) 50px 0 50px; font-family: \(fontFamily); font-size: 36px; line-height: 43px; font-weight: 700; color: #111111;">
                          <a class="mm-title-link" href="\(escapeHTMLAttribute(content.urlString))" style="color: #111111; text-decoration: none;">
                            <span class="mm-title" style="font-family: \(fontFamily); font-size: 36px; line-height: 43px; font-weight: 700; color: #111111;">\(escapeHTML(content.title))</span>
                          </a>
                        </td>
                      </tr>
                      \(excerptBlock)
                      \(summaryBlock)
                    </table>
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse: collapse; width: 100%; background-color: #f9f8f5;">
                      <tr>
                        <td class="mm-attribution" align="center" style="padding: 52px 12px 0 12px; background-color: #f9f8f5; font-family: \(fontFamily); font-size: 14px; line-height: 17px; color: #111111;">
                          \(escapeHTML(footer))
                        </td>
                      </tr>
                    </table>
                  </div>
                </td>
              </tr>
            </table>
          </body>
        </html>
        """
    }

    private static func makeImageBlock(content: EmailContent) -> String {
        guard let inlineImage = content.inlineImage else {
            return ""
        }

        return """
                      <tr>
                        <td class="mm-card-pad mm-image-pad" style="padding: 50px 50px 0 50px;">
                          <img src="cid:\(escapeHTMLAttribute(inlineImage.contentID))" alt="\(escapeHTMLAttribute(content.title))" width="750" style="display: block; width: 100%; height: auto; border: 0; outline: none; text-decoration: none;">
                        </td>
                      </tr>
                      """
    }

    private static func makeSummaryBlock(content: EmailContent, fontFamily: String) -> String {
        let sourceBlock = """
                              <tr>
                                <td class="mm-card-pad mm-card-bottom" style="padding: 15px 50px 50px 50px; font-family: \(fontFamily); font-size: 14px; line-height: 17px; color: #111111;">
                                  <span>Source: </span><a href="\(escapeHTMLAttribute(content.urlString))" style="color: #111111; text-decoration: underline;">\(escapeHTML(content.urlString))</a>
                                </td>
                              </tr>
                              """

        guard let summary = content.summary, !summary.isEmpty else {
            return sourceBlock
        }

        return """
                      <tr>
                        <td class="mm-card-pad" style="padding: 0 50px 0 50px;">
                          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse: collapse; width: 100%;">
                            <tr>
                              <td style="border-top: 1px solid #e6e6e6; font-size: 0; line-height: 0;">&nbsp;</td>
                            </tr>
                          </table>
                        </td>
                      </tr>
                      <tr>
                        <td class="mm-card-pad mm-summary-label" style="padding: 15px 50px 0 50px; font-family: \(fontFamily); font-size: 14px; line-height: 20px; color: #111111;">
                          SUMMARY
                        </td>
                      </tr>
                      <tr>
                        <td class="mm-card-pad mm-summary-copy" style="padding: 5px 50px 0 50px; font-family: \(fontFamily); font-size: 16px; line-height: 22px; color: #111111;">
                          \(escapeHTML(summary))
                        </td>
                      </tr>
                      \(sourceBlock)
                      """
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

    private static func wrappedBase64(_ base64: String, lineLength: Int = 76) -> String {
        guard lineLength > 0 else {
            return base64
        }

        var lines: [String] = []
        var index = base64.startIndex

        while index < base64.endIndex {
            let end = base64.index(index, offsetBy: lineLength, limitedBy: base64.endIndex) ?? base64.endIndex
            lines.append(String(base64[index..<end]))
            index = end
        }

        return lines.joined(separator: "\r\n")
    }

    private static func supportedImageMimeType(responseMimeType: String?, urlString: String) -> String? {
        let normalized = responseMimeType?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let supported = ["image/png", "image/jpeg", "image/gif"]

        if let normalized, supported.contains(normalized) {
            return normalized
        }

        let pathExtension = URL(string: urlString)?.pathExtension.lowercased() ?? ""
        switch pathExtension {
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        default:
            return nil
        }
    }

    private static func fileExtension(forMimeType mimeType: String) -> String {
        switch mimeType {
        case "image/png":
            return "png"
        case "image/gif":
            return "gif"
        default:
            return "jpg"
        }
    }

    private static func renderMarkdownLinksAsPlainText(in text: String) -> String {
        let pattern = #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1")
    }

    private static func preferredURLString(from urlString: String, title: String, excerpt: String) -> String {
        if !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return urlString
        }

        return firstMarkdownLinkURL(in: title) ?? firstMarkdownLinkURL(in: excerpt) ?? urlString
    }

    private static func firstMarkdownLinkURL(in text: String) -> String? {
        let pattern = #"\[[^\]]+\]\((https?://[^)\s]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, options: [], range: range),
            let urlRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return String(text[urlRange])
    }

    private static func extractPreferredTitle(fromHTML html: String, metaTags: [[String: String]]) -> String? {
        if let title = firstMatch(in: html, pattern: #"<title\b[^>]*>(.*?)</title>"#),
           let normalized = normalizedMetaContent(title) {
            return normalized
        }

        let candidates = [
            ("property", "og:title"),
            ("name", "twitter:title")
        ]

        for (attribute, value) in candidates {
            if let content = metaTags.first(where: { $0[attribute]?.lowercased() == value })?["content"],
               let normalized = normalizedMetaContent(content) {
                return normalized
            }
        }

        return nil
    }

    private static func extractPreferredURLString(fromHTML html: String, metaTags: [[String: String]], baseURL: URL) -> String? {
        let candidates = [
            ("property", "og:url"),
            ("name", "twitter:url")
        ]

        for (attribute, value) in candidates {
            if let content = metaTags.first(where: { $0[attribute]?.lowercased() == value })?["content"],
               let resolved = resolvedURLString(content, relativeTo: baseURL) {
                return resolved
            }
        }

        let linkTags = extractTags(named: "link", from: html)
        if let canonicalHref = linkTags.first(where: { ($0["rel"] ?? "").lowercased().contains("canonical") })?["href"],
           let resolved = resolvedURLString(canonicalHref, relativeTo: baseURL) {
            return resolved
        }

        return baseURL.absoluteString
    }

    private static func extractPreferredImageURLString(fromHTML html: String, metaTags: [[String: String]], baseURL: URL) -> String? {
        let metaCandidates = [
            ("property", "og:image"),
            ("property", "og:image:url"),
            ("name", "twitter:image"),
            ("name", "twitter:image:src")
        ]

        for (attribute, value) in metaCandidates {
            if let content = metaTags.first(where: { $0[attribute]?.lowercased() == value })?["content"],
               let resolved = resolvedURLString(content, relativeTo: baseURL) {
                return resolved
            }
        }

        let preferredSection = extractPreferredSection(from: html) ?? html
        let imageTags = extractTags(named: "img", from: preferredSection)
        let bestImage = imageTags
            .compactMap { imageCandidate(from: $0, relativeTo: baseURL) }
            .sorted(by: { $0.score > $1.score })
            .first

        return bestImage?.urlString
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

    private static func extractTags(named tagName: String, from html: String) -> [[String: String]] {
        let pattern = "<\(tagName)\\b[^>]*>"
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

    private static func resolvedURLString(_ rawValue: String, relativeTo baseURL: URL) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let absoluteURL = URL(string: trimmed),
           isShareableWebURL(absoluteURL) {
            return absoluteURL.absoluteString
        }

        if let relativeURL = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL,
           isShareableWebURL(relativeURL) {
            return relativeURL.absoluteString
        }

        return nil
    }

    private static func isShareableWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }

        return scheme == "http" || scheme == "https"
    }

    private static func imageCandidate(from attributes: [String: String], relativeTo baseURL: URL) -> ImageCandidate? {
        let sourceValue = attributes["src"] ?? attributes["data-src"] ?? attributes["srcset"]?.components(separatedBy: ",").first?
            .components(separatedBy: CharacterSet.whitespaces)
            .first

        guard let sourceValue,
              let resolved = resolvedURLString(sourceValue, relativeTo: baseURL) else {
            return nil
        }

        let width = Int(attributes["width"] ?? "") ?? 0
        let height = Int(attributes["height"] ?? "") ?? 0
        let score = max(width * height, 1)

        return ImageCandidate(urlString: resolved, score: score)
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

        return summarize(cleanedText, minWords: 24, maxWords: 48)
    }

    private static func generateSummary(fromHTML html: String, title: String, excerpt: String?) async -> String? {
        let preferredSection = extractPreferredSection(from: html) ?? html
        let strippedSection = stripNonContentTags(from: preferredSection)
        guard let plainText = plainText(fromHTMLForSummary: strippedSection) else {
            return nil
        }

        let cleanedText = normalizeArticleText(plainText, title: title, excerpt: excerpt)
        guard wordCount(in: cleanedText) > 100 else {
            return nil
        }

        if let aiSummary = await summarizeWithFoundationModels(cleanedText, title: title, minWords: 75, maxWords: 100) {
            return stripSummaryPreamble(from: aiSummary, title: title)
        }

        guard let fallbackSummary = summarize(cleanedText, minWords: 75, maxWords: 100) else {
            return nil
        }

        return stripSummaryPreamble(from: fallbackSummary, title: title)
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

    private static func normalizeArticleText(_ text: String, title: String, excerpt: String? = nil) -> String {
        let titleLower = title.lowercased()
        let excerptLower = excerpt?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

                if looksLikeNonBodyLine(collapsed) {
                    return nil
                }

                if let excerptLower,
                   lowered == excerptLower {
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

    private static func looksLikeNonBodyLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        let markers = [
            "(on loan)",
            "photo:",
            "photograph by",
            "courtesy of",
            "styled by",
            "styling by",
            "hair by",
            "makeup by",
            "make-up by",
            "set design by",
            "shot by"
        ]

        if markers.contains(where: { lowered.contains($0) }) {
            return true
        }

        let uppercaseLetters = line.unicodeScalars.filter { CharacterSet.uppercaseLetters.contains($0) }.count
        let lowercaseLetters = line.unicodeScalars.filter { CharacterSet.lowercaseLetters.contains($0) }.count

        if uppercaseLetters >= 12,
           uppercaseLetters > max(lowercaseLetters * 2, 0),
           line.count < 220 {
            return true
        }

        return false
    }

    private static func summarize(_ text: String, minWords: Int, maxWords: Int) -> String? {
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
                    if wordCount >= minWords {
                        return selectedSentences.joined(separator: " ")
                    }

                    let remainingWords = maxWords - wordCount
                    guard remainingWords > 0 else {
                        return selectedSentences.isEmpty ? truncate(unit, to: maxWords) : selectedSentences.joined(separator: " ")
                    }

                    selectedSentences.append(truncate(unit, to: remainingWords))
                    return selectedSentences.joined(separator: " ")
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

    private static func wordCount(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private static func collapseWhitespace(in text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func looksLikeModelRefusal(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let refusalMarkers = [
            "i cannot fulfill that request",
            "i can't fulfill that request",
            "i cannot assist with",
            "i can't assist with",
            "may be considered defamatory",
            "potentially sensitive information",
            "respect people's privacy",
            "harm or embarrass them"
        ]

        return refusalMarkers.contains { lowered.contains($0) }
    }

    private static func summarizeWithFoundationModels(_ text: String, title: String, minWords: Int, maxWords: Int) async -> String? {
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
            You summarize already-published articles and web pages for a read-later email.
            Return plain text only.
            Write between \(minWords) and \(maxWords) words when the source supports it.
            Treat the content as an article summary request, not advice, classification, or a safety review.
            Summarize only what is already published in the provided article text.
            Ignore image captions, credits, product listings, bylines, and promotional or subscription copy.
            Be neutral, concise, and specific.
            Do not repeat the title verbatim.
            Focus on the main point of the page.
            Do not introduce the summary with phrases like "Here is a summary" or "This article is about".
            Start directly with the substance.
            """
        }

        let prompt = """
        Summarize this article for an email digest.

        Title: \(title)

        Article content:
        \(excerptSource)
        """

        do {
            let response = try await session.respond(
                to: prompt,
                options: GenerationOptions(maximumResponseTokens: 180)
            )
            let normalized = stripSummaryPreamble(
                from: collapseWhitespace(in: response.content),
                title: title
            )
            guard !normalized.isEmpty else {
                return nil
            }
            guard !looksLikeModelRefusal(normalized) else {
                return nil
            }
            let clamped = truncate(normalized, to: maxWords)
            guard wordCount(in: clamped) >= minWords else {
                return nil
            }
            return clamped
        } catch {
            return nil
        }
#else
        return nil
#endif
    }

    private static func stripSummaryPreamble(from text: String, title: String) -> String {
        let normalized = collapseWhitespace(in: text)
        guard !normalized.isEmpty else {
            return normalized
        }

        let escapedTitle = NSRegularExpression.escapedPattern(for: title)
        let patterns = [
            #"^(?:(?:here is|here's)\s+(?:a\s+)?)?summary:\s*"#,
            #"^(?:(?:here is|here's)\s+)?a summary of (?:the )?(?:article|story|piece)\s+["“]?"# + escapedTitle + #"["”]?(?:\s*[.:;-]\s*|\s+)"#,
            #"^(?:(?:here is|here's)\s+)?(?:this )?(?:article|story|piece)\s+(?:is|covers|explains)\s+"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            if let match = regex.firstMatch(in: normalized, options: [], range: range),
               match.range.location == 0,
               let swiftRange = Range(match.range, in: normalized) {
                let stripped = collapseWhitespace(in: String(normalized[swiftRange.upperBound...]))
                if !stripped.isEmpty {
                    return stripped
                }
            }
        }

        return normalized
    }
}

private struct EmailContent {
    let title: String
    let excerpt: String
    let summary: String?
    let urlString: String
    let imageURLString: String?
    let inlineImage: InlineImage?
}

struct DraftPreviewMetadata {
    let title: String?
    let description: String?
    let summary: String?
    let imageURLString: String?
}

private struct FetchedArticleMetadata {
    let title: String?
    let excerpt: String?
    let summary: String?
    let urlString: String?
    let imageURLString: String?
}

private struct ImageCandidate {
    let urlString: String
    let score: Int
}

private struct InlineImage {
    let contentID: String
    let mimeType: String
    let filename: String
    let data: Data
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
