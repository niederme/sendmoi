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
    @Published var urlString = ""
    @Published var statusMessage = "Preparing your email..."
    @Published var isSaving = false
    @Published var savedRecipients: [String] = []
    @Published var presentationMode: PresentationMode = .processing

    private weak var extensionContextRef: NSExtensionContext?
    private let deliveryService = GmailDeliveryService()

    func attach(extensionContext: NSExtensionContext?) {
        extensionContextRef = extensionContext
        savedRecipients = RecipientStore.load()
        toEmail = RecipientStore.loadDefault()
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
            urlString: urlString
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
            urlString: draft.trimmedURLString
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
        } else {
            statusMessage = "Sending..."
        }
    }

    private func autoSendIfPossible() {
        let draft = ShareDraft(
            toEmail: toEmail,
            title: title,
            excerpt: excerpt,
            urlString: urlString
        )

        guard draft.isValidForQueue else {
            presentationMode = .editing
            return
        }

        presentationMode = .processing
        queueAndComplete()
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
            "public.url-name",
            UTType.plainText.identifier,
            UTType.text.identifier,
            UTType.html.identifier,
            UTType.rtf.identifier
        ]

        let matchingIdentifiers = candidateIdentifiers.filter { provider.hasItemConformingToTypeIdentifier($0) }
        guard !matchingIdentifiers.isEmpty else {
            return []
        }

        var values: [String] = []

        for typeIdentifier in matchingIdentifiers {
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
