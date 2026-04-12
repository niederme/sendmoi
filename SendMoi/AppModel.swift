import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var queuedEmails: [QueuedEmail] = []
    @Published var defaultRecipient = ""
    @Published var shareSheetAutoSendEnabled = true
    @Published var session: GmailSession?
    @Published var statusMessage = "Configure Google OAuth, sign in, then queue or send shared items."
    @Published var isBusy = false
    @Published var isOnline = false
    @Published var isAccountSectionExpanded = true
    @Published var isQueueSectionExpanded = false
    @Published var requiresGmailReconnect = false
    @Published var shouldShowOnboarding = false

    private let client = GmailAPIClient()
    private let monitor = NetworkMonitor()
    private let queueChangeObserver = QueueChangeObserver()
    private var shouldReprocessQueue = false

    init() {
        monitor.onStatusChange = { [weak self] online in
            Task { @MainActor [weak self] in
                self?.handleNetworkChange(online: online)
            }
        }
        queueChangeObserver.onChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleSharedQueueChange()
            }
        }
        queueChangeObserver.start()
    }

    func startup() async {
        reloadSharedPreferences()
        reloadQueueFromDisk()
        reloadSessionFromDisk()

        isAccountSectionExpanded = session == nil || !GoogleOAuthConfig.isConfigured

        #if os(macOS)
        checkForShareExtensionDebugError()
        #endif

        await processQueue()
    }

    #if os(macOS)
    private func checkForShareExtensionDebugError() {
        guard let error = SharedContainer.sharedDefaults.string(forKey: "debugLastShareExtensionError") else {
            return
        }
        statusMessage = "⚠️ Last share attempt failed — \(error)"
    }
    #endif

    @discardableResult
    func signIn() async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        var didSignIn = false

        do {
            let signedInSession = try await client.signIn()
            session = signedInSession
            try KeychainStore.save(session: signedInSession)
            try SharedSessionStore.save(signedInSession)
            requiresGmailReconnect = false
            statusMessage = "Signed in as \(signedInSession.emailAddress ?? "your Gmail account")."
            isAccountSectionExpanded = false
            reloadQueueFromDisk()
            didSignIn = true
        } catch {
            statusMessage = "Sign in failed: \(error.localizedDescription)"
        }

        isBusy = false

        if didSignIn {
            await processQueue()
            return true
        }

        return false
    }

    func signOut() {
        guard !isBusy else { return }
        do {
            try KeychainStore.clearSession()
            SharedSessionStore.clear()
            session = nil
            requiresGmailReconnect = false
            isAccountSectionExpanded = true
            statusMessage = "Signed out. Queued items stay on disk until you send them."
        } catch {
            statusMessage = "Could not remove saved Gmail credentials: \(error.localizedDescription)"
        }
    }

    func processQueue() async {
        guard !isBusy else {
            shouldReprocessQueue = true
            return
        }

        reloadSharedPreferences()
        reloadSessionFromDisk()
        reloadQueueFromDisk()
        guard !queuedEmails.isEmpty else { return }
        guard let existingSession = session else {
            statusMessage = "You have queued items. Sign in to Gmail to send them."
            return
        }

        isBusy = true
        defer {
            isBusy = false
            if shouldReprocessQueue {
                shouldReprocessQueue = false
                Task {
                    await processQueue()
                }
            }
        }

        do {
            let validSession = try await client.ensureValidSession(existingSession)
            if validSession != existingSession {
                session = validSession
                try KeychainStore.save(session: validSession)
                try SharedSessionStore.save(validSession)
            }

            while let next = queuedEmails.last {
                do {
                    try await client.sendEmail(using: validSession, item: next)
                    removeManagedMedia(for: next)
                    removeQueuedEmail(id: next.id)
                    RecipientStore.record(next.toEmail)
                    statusMessage = "Sent \"\(next.title)\" to \(next.toEmail)."
                } catch {
                    if let gmailError = error as? GmailAPIError, gmailError.requiresReconnect {
                        requiresGmailReconnect = true
                        isAccountSectionExpanded = true
                        isQueueSectionExpanded = true
                        markFailure(for: next.id, message: gmailError.localizedDescription)
                        statusMessage = "Reconnect Gmail to grant send permission. Queued items will send after you reconnect."
                    } else {
                        markFailure(for: next.id, message: error.localizedDescription)
                        statusMessage = "Queued item kept for retry: \(error.localizedDescription)"
                    }
                    break
                }
            }
        } catch {
            if let gmailError = error as? GmailAPIError, gmailError.requiresReconnect {
                requiresGmailReconnect = true
                isAccountSectionExpanded = true
                isQueueSectionExpanded = true
                statusMessage = "Reconnect Gmail to grant send permission. Queued items will send after you reconnect."
            } else {
                statusMessage = "Queue processing paused: \(error.localizedDescription)"
            }
        }
    }

    func deleteQueuedEmails(at offsets: IndexSet) {
        let removedIDs = offsets.compactMap { index in
            queuedEmails.indices.contains(index) ? queuedEmails[index].id : nil
        }
        removeQueuedEmails(ids: removedIDs)
    }

    func deleteQueuedEmail(id: UUID) {
        removeQueuedEmails(ids: [id])
    }

    func setDefaultRecipient(_ recipient: String) {
        RecipientStore.setDefault(recipient)
        defaultRecipient = RecipientStore.loadDefault()
    }

    func setShareSheetAutoSendEnabled(_ isEnabled: Bool) {
        RecipientStore.setShareSheetAutoSendEnabled(isEnabled)
        shareSheetAutoSendEnabled = RecipientStore.loadShareSheetAutoSendEnabled()
    }

    func retryNow() async {
        reloadSharedPreferences()
        reloadSessionFromDisk()
        reloadQueueFromDisk()
        await processQueue()
    }

    func resetSetup() {
        guard !isBusy else { return }

        do {
            try KeychainStore.clearSession()
            SharedSessionStore.clear()
            RecipientStore.resetSetup()

            session = nil
            defaultRecipient = RecipientStore.loadDefault()
            shareSheetAutoSendEnabled = RecipientStore.loadShareSheetAutoSendEnabled()
            isAccountSectionExpanded = true
            shouldShowOnboarding = true
            statusMessage = "Setup reset. Walk through the guide to reconnect Gmail and reconfigure defaults."
        } catch {
            statusMessage = "Could not reset setup: \(error.localizedDescription)"
        }
    }

    func completeOnboarding() {
        RecipientStore.setHasCompletedOnboarding(true)
        shouldShowOnboarding = false
    }

    private func reloadQueueFromDisk() {
        let previousCount = queuedEmails.count

        do {
            queuedEmails = try QueueStore.load()
            let hasQueuedEmails = !queuedEmails.isEmpty
            let hadQueuedEmails = previousCount > 0

            if hasQueuedEmails && !hadQueuedEmails {
                isQueueSectionExpanded = true
            } else if !hasQueuedEmails {
                isQueueSectionExpanded = false
            }

            updateReconnectRequirement()
        } catch {
            statusMessage = "Could not load the offline queue: \(error.localizedDescription)"
        }
    }

    private func removeQueuedEmail(id: UUID) {
        removeQueuedEmails(ids: [id])
    }

    private func removeQueuedEmails(ids: [UUID]) {
        guard !ids.isEmpty else {
            return
        }

        let removedItems = queuedEmails.filter { ids.contains($0.id) }
        removedItems.forEach { item in
            removeManagedMedia(for: item)
        }
        queuedEmails.removeAll { ids.contains($0.id) }
        updateReconnectRequirement()
        persistQueue()
    }

    private func markFailure(for id: UUID, message: String) {
        if let index = queuedEmails.firstIndex(where: { $0.id == id }) {
            queuedEmails[index].lastError = message
            updateReconnectRequirement()
            persistQueue()
        }
    }

    private func updateReconnectRequirement() {
        requiresGmailReconnect = queuedEmails.contains { item in
            guard let lastError = item.lastError else {
                return false
            }

            return GmailAPIError.indicatesInsufficientAuthenticationScopes(lastError)
        }
    }

    private func persistQueue() {
        do {
            try QueueStore.save(queuedEmails)
        } catch {
            statusMessage = "Could not save the offline queue: \(error.localizedDescription)"
        }
    }

    private func reloadSharedPreferences() {
        defaultRecipient = RecipientStore.loadDefault()
        shareSheetAutoSendEnabled = RecipientStore.loadShareSheetAutoSendEnabled()
        shouldShowOnboarding = !RecipientStore.loadHasCompletedOnboarding()
    }

    private func reloadSessionFromDisk() {
        do {
            if let persistedSession = try KeychainStore.loadSession() ?? SharedSessionStore.load() {
                session = persistedSession
                try? SharedSessionStore.save(persistedSession)
                return
            }
        } catch {
            statusMessage = "Could not read saved Gmail credentials: \(error.localizedDescription)"
        }
    }

    private func handleNetworkChange(online: Bool) {
        isOnline = online
        if online {
            Task {
                await processQueue()
            }
        }
    }

    private func handleSharedQueueChange() {
        reloadSharedPreferences()
        reloadSessionFromDisk()
        reloadQueueFromDisk()
        #if os(macOS)
        checkForShareExtensionDebugError()
        #endif
        Task {
            await processQueue()
        }
    }

    private func removeManagedMedia(for item: QueuedEmail) {
        item.allImageURLStrings.forEach { SharedContainer.removeManagedMediaIfPresent(urlString: $0) }
    }
}

private final class QueueChangeObserver {
    var onChange: (() -> Void)?
    private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let queueObserver = Unmanaged<QueueChangeObserver>
                    .fromOpaque(observer)
                    .takeUnretainedValue()
                queueObserver.onChange?()
            },
            QueueStore.didChangeNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CFNotificationCenterRemoveObserver(
            center,
            observer,
            CFNotificationName(rawValue: QueueStore.didChangeNotification as CFString),
            nil
        )
    }

    deinit {
        stop()
    }
}
