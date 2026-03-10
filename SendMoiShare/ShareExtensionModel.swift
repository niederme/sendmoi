import Foundation
import LinkPresentation
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
final class ShareExtensionModel: ObservableObject {
    private static let autoSendGracePeriodNanoseconds: UInt64 = 1_000_000_000
    private static let manualSendPreviewWaitLimitNanoseconds: UInt64 = 750_000_000
    static let missingRecipientMessage = "Enter a recipient in the To field, or set a default recipient in the SendMoi app."
    static let recipientHelperMessage = "Pro tip: add a recipient here, or save a default recipient in the SendMoi app."
    private static let connectGmailStatusMessage = "Connect Gmail to send from the share sheet. You can still queue this share and send it after sign-in."

    enum PresentationMode: Equatable {
        case processing
        case editing
    }

    @Published var toEmail = "" {
        didSet {
            if !toEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                showsMissingRecipientValidation = false
            }
        }
    }
    @Published var title = ""
    @Published var excerpt = ""
    @Published var summary = ""
    @Published var urlString = ""
    @Published var previewImageURLString: String?
    @Published var additionalImageURLStrings: [String] = []
    @Published var statusMessage = "Preparing your email..."
    @Published private(set) var autoSendEnabled = true
    @Published var isSaving = false
    @Published var isConnectingGmail = false
    @Published var isRefreshingPreview = false
    @Published var savedRecipients: [String] = []
    @Published var presentationMode: PresentationMode = .processing
    @Published var showsGmailConnectAlert = false
    @Published private(set) var showsMissingRecipientValidation = false
    @Published private(set) var recipientFocusRequest = 0

    private weak var extensionContextRef: NSExtensionContext?
    private let deliveryService = GmailDeliveryService()
    private var previewTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var pendingPreviewApplication: PendingPreviewApplication?
    private var queuedPreviewEnrichmentItem: QueuedEmail?
    private var hasPromptedForGmailConnection = false
    var requestGmailConnection: (@MainActor () async throws -> GmailSession)?

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
            schedulePreviewRefresh()
            autoSendIfPossible()
            promptForGmailConnectionIfNeeded()
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

        let draft = currentDraft()
        let shouldAllowAutoSendEditWindow = presentationMode == .processing

        if draft.toEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showsMissingRecipientValidation = true
            recipientFocusRequest &+= 1
        }

        if let validationMessage = validationMessage(for: draft) {
            statusMessage = validationMessage
            presentationMode = .editing
            return
        }

        showsMissingRecipientValidation = false
        let item = makeQueuedEmail(from: draft)
        let shouldQueueWhilePreviewLoads = isRefreshingPreview && previewTask != nil
        if shouldQueueWhilePreviewLoads && presentationMode == .editing {
            statusMessage = "Finishing preview before send..."
        }

        isSaving = true

        sendTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isSaving = false
                self.sendTask = nil
                self.queuedPreviewEnrichmentItem = nil
            }

            do {
                if shouldAllowAutoSendEditWindow {
                    try await Task.sleep(nanoseconds: Self.autoSendGracePeriodNanoseconds)
                    try Task.checkCancellation()
                }
                let completedItem = try await self.queueAndAttemptBackgroundDelivery(
                    item,
                    waitForPreview: shouldQueueWhilePreviewLoads
                )
                RecipientStore.record(completedItem.toEmail)
            } catch is CancellationError {
                return
            } catch {
                self.statusMessage = "Could not send or save this share item: \(error.localizedDescription)"
                self.presentationMode = .editing
            }
        }
    }

    func stopAutoSendAndEdit() {
        guard presentationMode == .processing, isSaving else { return }

        sendTask?.cancel()
        sendTask = nil
        isSaving = false
        statusMessage = "Review and tap Send when ready."
        presentationMode = .editing
        schedulePreviewRefresh()
    }

    func connectGmail() {
        guard !isConnectingGmail else { return }

        showsGmailConnectAlert = false
        isConnectingGmail = true
        statusMessage = "Connecting Gmail..."

        Task { [weak self] in
            guard let self else { return }
            defer { self.isConnectingGmail = false }

            do {
                guard let requestGmailConnection else {
                    throw GmailAPIError.authorizationFailed("Google sign-in is not available in this share sheet.")
                }

                let session = try await requestGmailConnection()
                try SharedSessionStore.save(session)
                statusMessage = "Connected as \(session.emailAddress ?? "your Gmail account")."
                autoSendIfPossible()
            } catch GmailAPIError.signInCanceled {
                statusMessage = Self.connectGmailStatusMessage
            } catch {
                statusMessage = "Could not connect Gmail: \(error.localizedDescription)"
            }
        }
    }

    var recipientInlineMessage: String? {
        let trimmedRecipient = toEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedRecipient.isEmpty else {
            return nil
        }

        return showsMissingRecipientValidation
            ? Self.missingRecipientMessage
            : Self.recipientHelperMessage
    }

    var recipientInlineMessageIsError: Bool {
        showsMissingRecipientValidation &&
        toEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func currentDraft() -> ShareDraft {
        ShareDraft(
            toEmail: toEmail,
            title: title,
            excerpt: excerpt,
            summary: summary,
            urlString: urlString,
            previewImageURLString: previewImageURLString,
            additionalImageURLStrings: additionalImageURLStrings
        )
    }

    private func makeQueuedEmail(
        from draft: ShareDraft,
        id: UUID = UUID(),
        createdAt: Date = .now,
        lastError: String? = nil
    ) -> QueuedEmail {
        QueuedEmail(
            id: id,
            toEmail: draft.toEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            title: draft.queueTitle,
            excerpt: draft.trimmedExcerpt,
            summary: draft.trimmedSummary.isEmpty ? nil : draft.trimmedSummary,
            urlString: draft.trimmedURLString,
            previewImageURLString: draft.previewImageURLString,
            additionalImageURLStrings: draft.additionalImageURLStrings.isEmpty ? nil : draft.additionalImageURLStrings,
            createdAt: createdAt,
            lastError: lastError
        )
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

        if previewImageURLString == nil {
            previewImageURLString = content.previewImageURLString
        }

        if additionalImageURLStrings.isEmpty {
            additionalImageURLStrings = content.additionalImageURLStrings
        }

        if title.isEmpty && excerpt.isEmpty && urlString.isEmpty && allImageURLStrings.isEmpty {
            statusMessage = "Nothing was extracted automatically. You can still fill it in manually."
            presentationMode = .editing
        } else if !hasSharedGmailSession {
            statusMessage = Self.connectGmailStatusMessage
            presentationMode = .editing
        } else if toEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            statusMessage = "Review and tap Send when ready."
            presentationMode = .editing
        } else if autoSendEnabled {
            statusMessage = "Auto-Sending..."
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
            previewImageURLString: previewImageURLString,
            additionalImageURLStrings: additionalImageURLStrings
        )

        if !draft.hasQueueContent || draft.queueTitle.isEmpty {
            presentationMode = .editing
            return
        }

        if draft.toEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            statusMessage = "Review and tap Send when ready."
            presentationMode = .editing
            return
        }

        if isConnectingGmail {
            statusMessage = "Connecting Gmail..."
            presentationMode = .editing
            return
        }

        guard hasSharedGmailSession else {
            statusMessage = Self.connectGmailStatusMessage
            presentationMode = .editing
            return
        }

        guard autoSendEnabled else {
            statusMessage = "Review and tap Send when ready."
            presentationMode = .editing
            return
        }

        statusMessage = "Auto-Sending..."
        presentationMode = .processing
        queueAndComplete()
    }

    func schedulePreviewRefresh() {
        previewTask?.cancel()
        pendingPreviewApplication = nil

        let normalizedURLString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalizedURLString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            isRefreshingPreview = false
            summary = ""
            pendingPreviewApplication = nil
            if !SharedContainer.isManagedMediaURLString(previewImageURLString) {
                previewImageURLString = nil
            }
            additionalImageURLStrings.removeAll { !SharedContainer.isManagedMediaURLString($0) }
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
            var metadata = await self.deliveryService.fetchDraftPreview(
                urlString: normalizedURLString,
                fallbackTitle: titleSnapshot
            )
            if metadata?.imageURLString == nil,
               Self.shouldAttemptSocialImageFallback(for: normalizedURLString),
               let fallbackImageURLString = await Self.fetchLinkPreviewImageURLString(for: normalizedURLString) {
                metadata = DraftPreviewMetadata(
                    title: metadata?.title,
                    description: metadata?.description,
                    summary: metadata?.summary,
                    imageURLString: fallbackImageURLString
                )
            }

            await MainActor.run {
                guard self.urlString.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedURLString else {
                    return
                }

                self.isRefreshingPreview = false
                let application = PendingPreviewApplication(
                    normalizedURLString: normalizedURLString,
                    titleSnapshot: titleSnapshot,
                    excerptSnapshot: excerptSnapshot,
                    metadata: metadata
                )
                self.pendingPreviewApplication = application

                guard !self.isSaving else {
                    self.refreshQueuedItemForPendingPreviewIfPossible()
                    return
                }

                self.applyPreviewApplication(application)
            }
        }
    }

    private func queueAndAttemptBackgroundDelivery(
        _ item: QueuedEmail,
        waitForPreview: Bool
    ) async throws -> QueuedEmail {
        try Task.checkCancellation()
        try QueueStore.append(item)
        queuedPreviewEnrichmentItem = item
        extensionContextRef?.completeRequest(returningItems: nil, completionHandler: nil)

        let refreshedItem: QueuedEmail
        if waitForPreview {
            refreshedItem = try await waitForPreviewAndRefreshQueuedItem(item)
        } else {
            refreshedItem = item
        }

        do {
            if let session = try SharedSessionStore.load() {
                try Task.checkCancellation()
                let validSession = try await deliveryService.ensureValidSession(session)
                try Task.checkCancellation()
                _ = try await sendQueuedEmailIfPresent(refreshedItem, using: validSession)
                try await flushQueuedEmails(using: validSession)
                try SharedSessionStore.save(validSession)
                return refreshedItem
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return refreshedItem
        }

        return refreshedItem
    }

    private func waitForPreviewAndRefreshQueuedItem(_ item: QueuedEmail) async throws -> QueuedEmail {
        let didFinishPreviewInTime = try await waitForPreviewToFinish(
            upTo: Self.manualSendPreviewWaitLimitNanoseconds
        )
        guard didFinishPreviewInTime else {
            return item
        }

        let draft = draftApplyingPendingPreview(to: currentDraft())
        guard draft.isValidForQueue else {
            return item
        }

        let refreshedItem = makeQueuedEmail(
            from: draft,
            id: item.id,
            createdAt: item.createdAt,
            lastError: item.lastError
        )

        guard refreshedItem != item else {
            return item
        }

        do {
            let didReplace = try QueueStore.replace(refreshedItem)
            if didReplace {
                removeManagedMediaRemoved(from: item, comparedTo: refreshedItem)
            }
            return didReplace ? refreshedItem : item
        } catch {
            return item
        }
    }

    private func waitForPreviewToFinish(upTo timeoutNanoseconds: UInt64) async throws -> Bool {
        guard let previewTask else {
            return false
        }

        let didFinishInTime = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await previewTask.value
                return true
            }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    return false
                } catch {
                    return false
                }
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }

        try Task.checkCancellation()
        return didFinishInTime
    }

    private func applyPreviewApplication(_ application: PendingPreviewApplication) {
        guard urlString.trimmingCharacters(in: .whitespacesAndNewlines) == application.normalizedURLString else {
            return
        }

        if Self.shouldApplyPreviewTitle(
            existingTitle: application.titleSnapshot,
            urlString: application.normalizedURLString
        ),
           let previewTitle = application.metadata?.title,
           !previewTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = previewTitle
        }

        if application.excerptSnapshot.isEmpty,
           let previewDescription = application.metadata?.description,
           !previewDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            excerpt = previewDescription
        }

        summary = application.metadata?.summary ?? ""
        if !SharedContainer.isManagedMediaURLString(previewImageURLString),
           let previewImageURLString = application.metadata?.imageURLString {
            self.previewImageURLString = previewImageURLString
        }
    }

    private func draftApplyingPendingPreview(to draft: ShareDraft) -> ShareDraft {
        guard let pendingPreviewApplication else {
            return draft
        }

        guard draft.trimmedURLString == pendingPreviewApplication.normalizedURLString else {
            return draft
        }

        var updatedDraft = draft

        if Self.shouldApplyPreviewTitle(
            existingTitle: pendingPreviewApplication.titleSnapshot,
            urlString: pendingPreviewApplication.normalizedURLString
        ),
           let previewTitle = pendingPreviewApplication.metadata?.title,
           !previewTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updatedDraft.title = previewTitle
        }

        if pendingPreviewApplication.excerptSnapshot.isEmpty,
           let previewDescription = pendingPreviewApplication.metadata?.description,
           !previewDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updatedDraft.excerpt = previewDescription
        }

        updatedDraft.summary = pendingPreviewApplication.metadata?.summary ?? ""
        if !SharedContainer.isManagedMediaURLString(updatedDraft.previewImageURLString),
           let previewImageURLString = pendingPreviewApplication.metadata?.imageURLString {
            updatedDraft.previewImageURLString = previewImageURLString
        }
        return updatedDraft
    }

    private func refreshQueuedItemForPendingPreviewIfPossible() {
        guard let queuedPreviewEnrichmentItem else {
            return
        }

        let updatedDraft = draftApplyingPendingPreview(to: currentDraft())
        guard updatedDraft.isValidForQueue else {
            return
        }

        let refreshedItem = makeQueuedEmail(
            from: updatedDraft,
            id: queuedPreviewEnrichmentItem.id,
            createdAt: queuedPreviewEnrichmentItem.createdAt,
            lastError: queuedPreviewEnrichmentItem.lastError
        )

        guard refreshedItem != queuedPreviewEnrichmentItem else {
            return
        }

        do {
            let didReplace = try QueueStore.replace(refreshedItem)
            if didReplace {
                removeManagedMediaRemoved(from: queuedPreviewEnrichmentItem, comparedTo: refreshedItem)
                self.queuedPreviewEnrichmentItem = refreshedItem
            }
        } catch {
            return
        }
    }

    @discardableResult
    private func sendQueuedEmailIfPresent(_ item: QueuedEmail, using session: GmailSession) async throws -> Bool {
        var queue = try QueueStore.load()
        guard let index = queue.firstIndex(where: { $0.id == item.id }) else {
            return false
        }

        let queuedItem = queue[index]

        do {
            try await deliveryService.sendEmail(using: session, item: queuedItem)
            removeManagedMedia(for: queuedItem)
            queue.remove(at: index)
            try QueueStore.save(queue)
            return true
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            queue[index].lastError = error.localizedDescription
            try QueueStore.save(queue)
            throw error
        }
    }

    private func flushQueuedEmails(using session: GmailSession) async throws {
        var queue = try QueueStore.load()

        while let next = queue.last {
            try Task.checkCancellation()

            do {
                try await deliveryService.sendEmail(using: session, item: next)
                removeManagedMedia(for: next)
                queue.removeLast()
                try QueueStore.save(queue)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if let index = queue.indices.last {
                    queue[index].lastError = error.localizedDescription
                    try QueueStore.save(queue)
                }
                throw error
            }
        }
    }

    private func validationMessage(for draft: ShareDraft) -> String? {
        if draft.toEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Self.missingRecipientMessage
        }

        if !draft.hasQueueContent || draft.queueTitle.isEmpty {
            return "Enter some content before sending."
        }

        return nil
    }

    private var hasSharedGmailSession: Bool {
        do {
            return try SharedSessionStore.load() != nil
        } catch {
            return false
        }
    }

    private func promptForGmailConnectionIfNeeded() {
        guard !hasPromptedForGmailConnection, !hasSharedGmailSession else {
            return
        }

        hasPromptedForGmailConnection = true
        showsGmailConnectAlert = true
    }

    private static func shouldApplyPreviewTitle(existingTitle: String, urlString: String) -> Bool {
        let trimmedTitle = existingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            return true
        }

        if trimmedTitle.caseInsensitiveCompare("Shared Photo") == .orderedSame ||
            trimmedTitle.caseInsensitiveCompare("Shared Photos") == .orderedSame {
            return true
        }

        if trimmedTitle.caseInsensitiveCompare(urlString) == .orderedSame {
            return true
        }

        guard let host = URL(string: urlString)?.host?.lowercased() else {
            return false
        }

        let loweredTitle = trimmedTitle.lowercased()
        let condensedHost = host.replacingOccurrences(of: "www.", with: "")
        return loweredTitle == host || loweredTitle == condensedHost
    }

    private static func shouldAttemptSocialImageFallback(for urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host?.lowercased() else {
            return false
        }

        return host == "x.com" ||
            host == "www.x.com" ||
            host == "twitter.com" ||
            host == "www.twitter.com" ||
            host == "t.co" ||
            host == "www.t.co" ||
            host == "pic.twitter.com" ||
            host == "www.pic.twitter.com"
    }

    private static func fetchLinkPreviewImageURLString(for urlString: String) async -> String? {
        guard let url = URL(string: urlString) else {
            return nil
        }

        let provider = LPMetadataProvider()
        provider.timeout = 5

        do {
            let metadata = try await provider.startFetchingMetadata(for: url)
            guard let imageProvider = metadata.imageProvider,
                  let (imageData, fileExtension) = await loadImageData(from: imageProvider),
                  let fileURL = try? SharedContainer.storeSharedMedia(data: imageData, fileExtension: fileExtension) else {
                return nil
            }

            return fileURL.absoluteString
        } catch {
            return nil
        }
    }

    private static func loadImageData(from provider: NSItemProvider) async -> (Data, String)? {
        let candidates: [(String, String)] = [
            (UTType.jpeg.identifier, "jpg"),
            (UTType.png.identifier, "png"),
            (UTType.heic.identifier, "heic"),
            (UTType.gif.identifier, "gif")
        ]

        for (typeIdentifier, fileExtension) in candidates where provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
            if let data = await loadDataRepresentation(from: provider, typeIdentifier: typeIdentifier) {
                return (data, fileExtension)
            }
        }

#if canImport(UIKit)
        if let image = await loadUIImage(from: provider),
           let data = image.jpegData(compressionQuality: 0.92) {
            return (data, "jpg")
        }
#elseif canImport(AppKit)
        if let image = await loadNSImage(from: provider),
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) {
            return (data, "jpg")
        }
#endif

        return nil
    }

    private static func loadDataRepresentation(from provider: NSItemProvider, typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

#if canImport(UIKit)
    private static func loadUIImage(from provider: NSItemProvider) async -> UIImage? {
        guard provider.canLoadObject(ofClass: UIImage.self) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                continuation.resume(returning: object as? UIImage)
            }
        }
    }
#elseif canImport(AppKit)
    private static func loadNSImage(from provider: NSItemProvider) async -> NSImage? {
        guard provider.canLoadObject(ofClass: NSImage.self) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: NSImage.self) { object, _ in
                continuation.resume(returning: object as? NSImage)
            }
        }
    }
#endif
}

private struct PendingPreviewApplication {
    let normalizedURLString: String
    let titleSnapshot: String
    let excerptSnapshot: String
    let metadata: DraftPreviewMetadata?
}

private struct SharedItemContent {
    var title = ""
    var excerpt = ""
    var urlString = ""
    var previewImageURLString: String?
    var additionalImageURLStrings: [String] = []
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

                if let imageURLString = await loadStoredImageURLString(from: provider) {
                    content = appendImageURLString(imageURLString, to: content)
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

        let imageCount = ([content.previewImageURLString].compactMap { $0 } + content.additionalImageURLStrings).count
        if content.title.isEmpty, imageCount > 0 {
            content.title = imageCount > 1 ? "Shared Photos" : "Shared Photo"
        }

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

    private static func loadStoredImageURLString(from provider: NSItemProvider) async -> String? {
        let typeIdentifier = preferredImageTypeIdentifier(from: provider)
        guard !typeIdentifier.isEmpty else {
            return nil
        }

        if let data = await loadImageData(from: provider, typeIdentifier: typeIdentifier) {
            let fileExtension = preferredImageFileExtension(for: typeIdentifier)
            let fileURL = try? SharedContainer.storeSharedMedia(data: data, fileExtension: fileExtension)
            return fileURL?.absoluteString
        }

        return nil
    }

    private static func preferredImageTypeIdentifier(from provider: NSItemProvider) -> String {
        let candidates = [
            UTType.jpeg.identifier,
            UTType.png.identifier,
            UTType.gif.identifier,
            UTType.tiff.identifier,
            UTType.bmp.identifier,
            UTType.heic.identifier,
            UTType.image.identifier
        ]

        return candidates.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) ?? ""
    }

    private static func preferredImageFileExtension(for typeIdentifier: String) -> String {
        switch typeIdentifier {
        case UTType.heic.identifier:
            return "heic"
        case UTType.png.identifier:
            return "png"
        case UTType.gif.identifier:
            return "gif"
        case UTType.tiff.identifier:
            return "tiff"
        case UTType.bmp.identifier:
            return "bmp"
        default:
            return "jpg"
        }
    }

    private static func loadImageData(from provider: NSItemProvider, typeIdentifier: String) async -> Data? {
        if let data = await loadImageDataRepresentation(from: provider, typeIdentifier: typeIdentifier) {
            return data
        }

        return await loadImageFileRepresentationData(from: provider, typeIdentifier: typeIdentifier)
    }

    private static func loadImageDataRepresentation(from provider: NSItemProvider, typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func loadImageFileRepresentationData(from provider: NSItemProvider, typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                guard let url,
                      let data = try? Data(contentsOf: url) else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: data)
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
        if let socialShare = SharedPostTextParser.parseSocialPostShare(in: normalizedContent.title) {
            normalizedContent.title = socialShare.title
            if normalizedContent.excerpt.isEmpty {
                normalizedContent.excerpt = socialShare.excerpt
            }
            if normalizedContent.urlString.isEmpty, let url = socialShare.url {
                normalizedContent.urlString = url
            }
        }

        if let socialShare = SharedPostTextParser.parseSocialPostShare(in: normalizedContent.excerpt) {
            if normalizedContent.title.isEmpty {
                normalizedContent.title = socialShare.title
            }
            normalizedContent.excerpt = socialShare.excerpt
            if normalizedContent.urlString.isEmpty, let url = socialShare.url {
                normalizedContent.urlString = url
            }
        }

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

        if let linkedSocialShare = SharedPostTextParser.parseLinkedSocialPostShare(
            title: normalizedContent.title,
            excerpt: normalizedContent.excerpt,
            urlString: normalizedContent.urlString
        ) {
            normalizedContent.title = linkedSocialShare.title
            normalizedContent.excerpt = linkedSocialShare.excerpt
            if let url = linkedSocialShare.url {
                normalizedContent.urlString = url
            }
        }

        if let promotedContentURL = SharedPostTextParser.preferredContentURL(
            title: normalizedContent.title,
            currentURLString: normalizedContent.urlString
        ) {
            normalizedContent.urlString = promotedContentURL
        }

        let normalizedCandidates = expandedMarkdownCandidates(from: textCandidates)
        if let socialShare = normalizedCandidates.compactMap(SharedPostTextParser.parseSocialPostShare(in:)).first {
            if normalizedContent.title.isEmpty {
                normalizedContent.title = socialShare.title
            }
            if normalizedContent.excerpt.isEmpty {
                normalizedContent.excerpt = socialShare.excerpt
            }
        }

        if normalizedContent.urlString.isEmpty,
           let detectedURL = firstDetectedURLString(in: normalizedCandidates) {
            normalizedContent.urlString = detectedURL
        }

        let host = URL(string: normalizedContent.urlString)?.host?.lowercased()
        let candidates = unique(strings: normalizedCandidates).filter {
            $0.caseInsensitiveCompare(normalizedContent.urlString) != .orderedSame
        }
        let derivedSocialShare = SharedPostTextParser.derivedSocialPostShare(from: normalizedContent.urlString)

        if let derivedSocialShare {
            let shouldReplaceTitle =
                normalizedContent.title.isEmpty ||
                looksLikeHost(normalizedContent.title, host: host) ||
                normalizedContent.title.caseInsensitiveCompare(normalizedContent.urlString) == .orderedSame

            if shouldReplaceTitle {
                normalizedContent.title = derivedSocialShare.title
            }

            if normalizedContent.excerpt.isEmpty, !derivedSocialShare.excerpt.isEmpty {
                normalizedContent.excerpt = derivedSocialShare.excerpt
            }
        }

        if !normalizedContent.title.isEmpty {
            normalizedContent.title = SharedContentFormatter.normalizedTitle(
                normalizedContent.title,
                urlString: normalizedContent.urlString
            )
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
        SharedPostTextParser.markdownLikeLink(in: text)
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

    private static func appendImageURLString(_ imageURLString: String, to content: SharedItemContent) -> SharedItemContent {
        let normalized = imageURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return content
        }

        var updatedContent = content
        let existing = [updatedContent.previewImageURLString].compactMap { $0 } + updatedContent.additionalImageURLStrings
        guard !existing.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) else {
            return updatedContent
        }

        if updatedContent.previewImageURLString == nil {
            updatedContent.previewImageURLString = normalized
        } else {
            updatedContent.additionalImageURLStrings.append(normalized)
        }

        return updatedContent
    }
}

private extension ShareExtensionModel {
    var allImageURLStrings: [String] {
        ([previewImageURLString].compactMap { $0 } + additionalImageURLStrings)
            .reduce(into: [String]()) { result, next in
                guard !result.contains(where: { $0.caseInsensitiveCompare(next) == .orderedSame }) else {
                    return
                }

                result.append(next)
            }
    }

    func removeManagedMedia(for item: QueuedEmail) {
        item.allImageURLStrings.forEach { SharedContainer.removeManagedMediaIfPresent(urlString: $0) }
    }

    func removeManagedMediaRemoved(from previous: QueuedEmail, comparedTo updated: QueuedEmail) {
        let updatedImageKeys = Set(updated.allImageURLStrings.map { $0.lowercased() })

        previous.allImageURLStrings.forEach { urlString in
            guard !updatedImageKeys.contains(urlString.lowercased()) else {
                return
            }

            SharedContainer.removeManagedMediaIfPresent(urlString: urlString)
        }
    }
}
