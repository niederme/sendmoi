import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ShareExtensionModel: ObservableObject {
    enum PresentationMode: Equatable {
        case processing
        case editing
    }

    @Published var toEmail = ""
    @Published var title = ""
    @Published var excerpt = ""
    @Published var summary = ""
    @Published var urlString = ""
    @Published var previewImageURLString: String?
    @Published var statusMessage = "Preparing your email..."
    @Published private(set) var autoSendEnabled = true
    @Published var isSaving = false
    @Published var isRefreshingPreview = false
    @Published var savedRecipients: [String] = []
    @Published var presentationMode: PresentationMode = .processing

    private weak var extensionContextRef: NSExtensionContext?
    private let deliveryService = GmailDeliveryService()
    private var previewTask: Task<Void, Never>?

    func attach(extensionContext: NSExtensionContext?) {
        extensionContextRef = extensionContext
        savedRecipients = RecipientStore.load()
        toEmail = RecipientStore.loadDefault()
        autoSendEnabled = RecipientStore.loadShareSheetAutoSendEnabled()
    }

    func loadInitialContent() {
        guard let inputItems = extensionContextRef?.inputItems else {
            statusMessage = "The share sheet did not provide anything to queue."
            presentationMode = .editing
            return
        }

        Task {
            let content = await SharedItemExtractor.extract(from: inputItems)
            apply(content)
            if !autoSendEnabled || presentationMode == .editing {
                schedulePreviewRefresh()
            }
            autoSendIfPossible()
        }
    }

    func useSavedRecipient(_ recipient: String) {
        toEmail = recipient
    }

    func cancel() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSUserCancelledError,
            userInfo: [NSLocalizedDescriptionKey: "The user canceled the share."]
        )
        extensionContextRef?.cancelRequest(withError: error)
    }

    func queueAndComplete() {
        guard !isSaving else { return }

        let draft = ShareDraft(
            toEmail: toEmail,
            title: title,
            excerpt: excerpt,
            summary: summary,
            urlString: urlString,
            previewImageURLString: previewImageURLString
        )

        guard draft.isValidForQueue else {
            statusMessage = "Enter a recipient, title, and valid URL before saving."
            presentationMode = .editing
            return
        }

        let item = QueuedEmail(
            toEmail: draft.toEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            title: draft.trimmedTitle,
            excerpt: draft.trimmedExcerpt,
            summary: draft.trimmedSummary.isEmpty ? nil : draft.trimmedSummary,
            urlString: draft.trimmedURLString,
            previewImageURLString: draft.previewImageURLString
        )

        isSaving = true

        Task {
            do {
                try await sendImmediatelyOrQueue(item)
                RecipientStore.record(item.toEmail)
                extensionContextRef?.completeRequest(returningItems: nil, completionHandler: nil)
            } catch {
                statusMessage = "Could not send or save this share item: \(error.localizedDescription)"
                presentationMode = .editing
            }
            isSaving = false
        }
    }

    private func apply(_ content: SharedItemContent) {
        if title.isEmpty {
            title = content.title
        }

        if excerpt.isEmpty {
            excerpt = content.excerpt
        }

        if urlString.isEmpty {
            urlString = content.urlString
        }

        if title.isEmpty && excerpt.isEmpty && urlString.isEmpty {
            statusMessage = "Nothing was extracted automatically. You can still fill it in manually."
            presentationMode = .editing
        } else if toEmail.isEmpty {
            statusMessage = "Set a default recipient in the MailMoi app, or enter one here."
            presentationMode = .editing
        } else if autoSendEnabled {
            statusMessage = "Sending..."
        } else {
            statusMessage = "Review and tap Send when ready."
            presentationMode = .editing
        }
    }

    private func autoSendIfPossible() {
        let draft = ShareDraft(
            toEmail: toEmail,
            title: title,
            excerpt: excerpt,
            summary: summary,
            urlString: urlString,
            previewImageURLString: previewImageURLString
        )

        guard draft.isValidForQueue else {
            presentationMode = .editing
            return
        }

        guard autoSendEnabled else {
            statusMessage = "Review and tap Send when ready."
            presentationMode = .editing
            return
        }

        presentationMode = .processing
        queueAndComplete()
    }

    func schedulePreviewRefresh() {
        previewTask?.cancel()

        let normalizedURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalizedURLString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            isRefreshingPreview = false
            summary = ""
            previewImageURLString = nil
            return
        }

        let titleSnapshot = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let excerptSnapshot = excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        isRefreshingPreview = true

        previewTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }

            guard let self else { return }
            let metadata = await self.deliveryService.fetchDraftPreview(
                urlString: normalizedURLString,
                fallbackTitle: titleSnapshot
            )

            await MainActor.run {
                guard self.urlString.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedURLString else {
                    return
                }

                self.isRefreshingPreview = false

                if titleSnapshot.isEmpty,
                   let previewTitle = metadata?.title,
                   !previewTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.title = previewTitle
                }

                if excerptSnapshot.isEmpty,
                   let previewDescription = metadata?.description,
                   !previewDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.excerpt = previewDescription
                }

                self.summary = metadata?.summary ?? ""
                self.previewImageURLString = metadata?.imageURLString
            }
        }
    }

    private func sendImmediatelyOrQueue(_ item: QueuedEmail) async throws {
        do {
            if let session = try SharedSessionStore.load() {
                let validSession = try await deliveryService.ensureValidSession(session)
                try await flushQueuedEmails(using: validSession)
                try await deliveryService.sendEmail(using: validSession, item: item)
                try SharedSessionStore.save(validSession)
                statusMessage = "Sent."
                return
            }
        } catch {
            statusMessage = "Send failed. Saving offline instead."
        }

        try QueueStore.append(item)
        statusMessage = "Saved offline."
    }

    private func flushQueuedEmails(using session: GmailSession) async throws {
        var queue = try QueueStore.load()

        while let next = queue.last {
            do {
                try await deliveryService.sendEmail(using: session, item: next)
                queue.removeLast()
                try QueueStore.save(queue)
            } catch {
                if let index = queue.indices.last {
                    queue[index].lastError = error.localizedDescription
                    try QueueStore.save(queue)
                }
                throw error
            }
        }
    }
}

private struct SharedItemContent {
    var title = ""
    var excerpt = ""
    var urlString = ""
}

private enum SharedItemExtractor {
    static func extract(from rawItems: [Any]) async -> SharedItemContent {
        var content = SharedItemContent()
        var textCandidates: [String] = []

        for case let item as NSExtensionItem in rawItems {
            if let attributedTitle = normalized(item.attributedTitle?.string) {
                if content.title.isEmpty {
                    content.title = attributedTitle
                }
                textCandidates.append(attributedTitle)
            }

            if let attributedContent = normalized(item.attributedContentText?.string) {
                if content.excerpt.isEmpty {
                    content.excerpt = attributedContent
                }
                textCandidates.append(attributedContent)
            }

            for provider in item.attachments ?? [] {
                if content.urlString.isEmpty,
                   let url = await loadURL(from: provider) {
                    content.urlString = url.absoluteString
                }

                let textValues = await loadTexts(from: provider)
                if !textValues.isEmpty {
                    textCandidates.append(contentsOf: textValues)
                }

                let propertyListValues = await loadPropertyListStrings(from: provider)
                if !propertyListValues.isEmpty {
                    textCandidates.append(contentsOf: propertyListValues)
                }
            }
        }

        content = normalize(content, using: textCandidates)

        if content.title.isEmpty, let host = URL(string: content.urlString)?.host {
            content.title = host
        }

        return content
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }

                if let data = item as? Data,
                   let string = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   let url = URL(string: string) {
                    continuation.resume(returning: url)
                    return
                }

                if let string = item as? String,
                   let url = URL(string: string) {
                    continuation.resume(returning: url)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private static func loadTexts(from provider: NSItemProvider) async -> [String] {
        let candidateIdentifiers = [
            UTType.html.identifier,
            "public.url-name",
            UTType.plainText.identifier,
            UTType.text.identifier,
            UTType.rtf.identifier
        ]

        let matchingIdentifiers = candidateIdentifiers.filter { provider.hasItemConformingToTypeIdentifier($0) }
        guard !matchingIdentifiers.isEmpty else {
            return []
        }

        var values: [String] = []

        for typeIdentifier in matchingIdentifiers {
            if typeIdentifier == UTType.html.identifier {
                values.append(contentsOf: await loadHTMLTextCandidates(from: provider))
                continue
            }

            if let text = await loadText(from: provider, typeIdentifier: typeIdentifier) {
                values.append(contentsOf: usefulLines(in: text))
            }
        }

        return unique(strings: values)
    }

    private static func loadText(from provider: NSItemProvider, typeIdentifier: String) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                continuation.resume(returning: normalizeLoadedText(item, typeIdentifier: typeIdentifier))
            }
        }
    }

    private static func loadHTMLTextCandidates(from provider: NSItemProvider) async -> [String] {
        guard let html = await loadHTML(from: provider) else {
            return []
        }

        var values: [String] = []

        if let title = preferredHTMLTitle(from: html) {
            values.append(title)
        }

        if let text = plainText(fromHTML: html) {
            values.append(contentsOf: usefulLines(in: text))
        }

        return unique(strings: values)
    }

    private static func loadHTML(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.html.identifier, options: nil) { item, _ in
                continuation.resume(returning: htmlString(from: item))
            }
        }
    }

    private static func htmlString(from item: NSSecureCoding?) -> String? {
        if let string = item as? String {
            return normalized(string)
        }

        if let attributedString = item as? NSAttributedString {
            return normalized(attributedString.string)
        }

        if let url = item as? URL {
            if url.isFileURL,
               let data = try? Data(contentsOf: url) {
                return decodedHTMLString(from: data)
            }

            return normalized(url.absoluteString)
        }

        if let data = item as? Data {
            return decodedHTMLString(from: data)
        }

        return nil
    }

    private static func decodedHTMLString(from data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return normalized(utf8)
        }

        if let unicode = String(data: data, encoding: .unicode) {
            return normalized(unicode)
        }

        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return normalized(latin1)
        }

        return nil
    }

    private static func preferredHTMLTitle(from html: String) -> String? {
        if let title = firstMatch(in: html, pattern: #"<title\b[^>]*>(.*?)</title>"#),
           let normalizedTitle = normalizedHTMLContent(title) {
            return normalizedTitle
        }

        let metaCandidates = [
            ("property", "og:title"),
            ("name", "twitter:title")
        ]

        let tags = extractMetaTags(from: html)

        for (attribute, value) in metaCandidates {
            if let content = tags.first(where: { $0[attribute]?.lowercased() == value })?["content"],
               let normalizedTitle = normalizedHTMLContent(content) {
                return normalizedTitle
            }
        }

        return nil
    }

    private static func loadPropertyListStrings(from provider: NSItemProvider) async -> [String] {
        guard provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) else {
            return []
        }

        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier, options: nil) { item, _ in
                continuation.resume(returning: extractStrings(fromPropertyList: item))
            }
        }
    }

    private static func normalizeLoadedText(_ item: NSSecureCoding?, typeIdentifier: String) -> String? {
        if let string = item as? String {
            if typeIdentifier == UTType.html.identifier {
                return plainText(fromHTML: string)
            }
            return normalized(string)
        }

        if let attributedString = item as? NSAttributedString {
            return normalized(attributedString.string)
        }

        if let url = item as? URL {
            if typeIdentifier == UTType.html.identifier, url.isFileURL {
                if let data = try? Data(contentsOf: url),
                   let text = plainText(fromHTMLData: data) {
                    return text
                }
            }

            if typeIdentifier == UTType.rtf.identifier, url.isFileURL {
                if let data = try? Data(contentsOf: url),
                   let text = plainText(fromRTFData: data) {
                    return text
                }
            }

            return normalized(url.absoluteString)
        }

        if let data = item as? Data {
            if typeIdentifier == UTType.html.identifier {
                return plainText(fromHTMLData: data)
            }

            if typeIdentifier == UTType.rtf.identifier {
                return plainText(fromRTFData: data)
            }

            if let string = String(data: data, encoding: .utf8) {
                return normalized(string)
            }
        }

        return nil
    }

    private static func plainText(fromHTML html: String) -> String? {
        guard let data = html.data(using: .utf8) else {
            return normalized(html)
        }

        return plainText(fromHTMLData: data) ?? normalized(html)
    }

    private static func plainText(fromHTMLData data: Data) -> String? {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return normalized(attributed.string)
        }

        return nil
    }

    private static func plainText(fromRTFData data: Data) -> String? {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf
        ]

        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return normalized(attributed.string)
        }

        return nil
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

    private static func parseAttributes(from tag: String) -> [String: String] {
        let pattern = #"([a-zA-Z_:.-]+)\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
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

            attributes[key] = nsTag.substring(with: valueRange)
        }

        return attributes
    }

    private static func normalizedHTMLContent(_ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return plainText(fromHTML: "<span>\(trimmed)</span>") ?? normalized(trimmed)
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

    private static func extractStrings(fromPropertyList item: NSSecureCoding?) -> [String] {
        switch item {
        case let dictionary as [String: Any]:
            return dictionary.keys.sorted().flatMap { key in
                extractStrings(fromAny: dictionary[key])
            }
        case let array as [Any]:
            return array.flatMap(extractStrings(fromAny:))
        default:
            return []
        }
    }

    private static func extractStrings(fromAny value: Any?) -> [String] {
        switch value {
        case let string as String:
            return usefulLines(in: string)
        case let attributed as NSAttributedString:
            return usefulLines(in: attributed.string)
        case let url as URL:
            return usefulLines(in: url.absoluteString)
        case let dictionary as [String: Any]:
            return dictionary.keys.sorted().flatMap { key in
                extractStrings(fromAny: dictionary[key])
            }
        case let array as [Any]:
            return array.flatMap(extractStrings(fromAny:))
        case let number as NSNumber:
            return [number.stringValue]
        default:
            return []
        }
    }

    private static func usefulLines(in text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalized(_ string: String?) -> String? {
        guard let string else {
            return nil
        }

        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func normalize(_ content: SharedItemContent, using textCandidates: [String]) -> SharedItemContent {
        var normalizedContent = content
        if let titleMarkdownLink = markdownLink(in: normalizedContent.title) {
            normalizedContent.title = titleMarkdownLink.text
            if normalizedContent.urlString.isEmpty {
                normalizedContent.urlString = titleMarkdownLink.url
            }
        }

        if let excerptMarkdownLink = markdownLink(in: normalizedContent.excerpt) {
            normalizedContent.excerpt = excerptMarkdownLink.text
            if normalizedContent.urlString.isEmpty {
                normalizedContent.urlString = excerptMarkdownLink.url
            }
        }

        let normalizedCandidates = expandedMarkdownCandidates(from: textCandidates)

        if normalizedContent.urlString.isEmpty,
           let detectedURL = firstDetectedURLString(in: normalizedCandidates) {
            normalizedContent.urlString = detectedURL
        }

        let host = URL(string: normalizedContent.urlString)?.host?.lowercased()
        let candidates = unique(strings: normalizedCandidates).filter {
            $0.caseInsensitiveCompare(normalizedContent.urlString) != .orderedSame
        }

        if shouldPromoteExcerptToTitle(content: normalizedContent, host: host) {
            normalizedContent.title = normalizedContent.excerpt
            normalizedContent.excerpt = ""
        }

        if normalizedContent.title.isEmpty {
            normalizedContent.title = bestTitle(from: candidates, excludingHost: host) ?? normalizedContent.title
        }

        if normalizedContent.excerpt.isEmpty {
            normalizedContent.excerpt = bestExcerpt(
                from: candidates,
                excludingTitle: normalizedContent.title,
                excludingHost: host
            ) ?? normalizedContent.excerpt
        }

        if normalizedContent.excerpt == normalizedContent.title {
            normalizedContent.excerpt = ""
        }

        return normalizedContent
    }

    private static func shouldPromoteExcerptToTitle(content: SharedItemContent, host: String?) -> Bool {
        guard
            !content.title.isEmpty,
            !content.excerpt.isEmpty,
            let host
        else {
            return false
        }

        let title = content.title.lowercased()
        let condensedHost = host.replacingOccurrences(of: "www.", with: "")

        let titleLooksLikeHost = title == host || title == condensedHost || title == condensedHost.replacingOccurrences(of: ".com", with: "")
        let excerptLooksRicher = content.excerpt.count > content.title.count && content.excerpt.contains(" ")
        return titleLooksLikeHost && excerptLooksRicher
    }

    private static func bestTitle(from candidates: [String], excludingHost host: String?) -> String? {
        candidates.first {
            !looksLikeHost($0, host: host)
        } ?? candidates.first
    }

    private static func bestExcerpt(from candidates: [String], excludingTitle title: String, excludingHost host: String?) -> String? {
        candidates.first {
            $0.caseInsensitiveCompare(title) != .orderedSame &&
            !looksLikeHost($0, host: host)
        }
    }

    private static func looksLikeHost(_ value: String, host: String?) -> Bool {
        guard let host else {
            return false
        }

        let lowered = value.lowercased()
        let condensedHost = host.replacingOccurrences(of: "www.", with: "")
        return lowered == host || lowered == condensedHost
    }

    private static func unique(strings: [String]) -> [String] {
        var seen = Set<String>()
        return strings.filter { seen.insert($0.lowercased()).inserted }
    }

    private static func expandedMarkdownCandidates(from candidates: [String]) -> [String] {
        candidates.flatMap { candidate in
            if let link = markdownLink(in: candidate) {
                return [link.text, link.url]
            }

            return [candidate]
        }
    }

    private static func markdownLink(in text: String) -> (text: String, url: String)? {
        let pattern = #"^\[([^\]]+)\]\((https?://[^)\s]+)\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
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

        let title = String(text[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let url = String(text[urlRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !url.isEmpty else {
            return nil
        }

        return (title, url)
    }

    private static func firstDetectedURLString(in candidates: [String]) -> String? {
        for candidate in candidates {
            if let detectedURL = detectedURLString(in: candidate) {
                return detectedURL
            }
        }

        return nil
    }

    private static func detectedURLString(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: range)

        for match in matches {
            guard
                match.resultType == .link,
                let url = match.url,
                isShareableWebURL(url)
            else {
                continue
            }

            return url.absoluteString
        }

        return nil
    }

    private static func isShareableWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }

        return scheme == "http" || scheme == "https"
    }
}
