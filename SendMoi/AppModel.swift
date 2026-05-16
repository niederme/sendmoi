import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var queuedEmails: [QueuedEmail] = []
    @Published var defaultRecipient = ""
    @Published var savedRecipients: [String] = []
    @Published var shareSheetAutoSendEnabled = true
    @Published var goodLinksSettings = GoodLinksSettingsStore.load()
    @Published var syncedGoodLinksJobs: [GoodLinksSyncJob] = GoodLinksSyncStore.load()
    @Published var isTestingGoodLinks = false
    @Published var goodLinksConnectionMessage: String?
    @Published var goodLinksConnectionSucceeded = false
    @Published var session: GmailSession?
    @Published var statusMessage = "Configure Google OAuth, sign in, then queue or send shared items."
    @Published var isBusy = false
    @Published var isOnline = false
    @Published var isAccountSectionExpanded = true
    @Published var isQueueSectionExpanded = false
    @Published var requiresGmailReconnect = false
    @Published var shouldShowOnboarding = false
    @Published var analyticsEnabled = false

    private let client = GmailAPIClient()
    private let goodLinksService = GoodLinksService()
    private let monitor = NetworkMonitor()
    private let queueChangeObserver = QueueChangeObserver()
    private let goodLinksQueueChangeObserver = QueueChangeObserver(notificationName: GoodLinksSyncStore.didChangeNotification)
    private var shouldReprocessQueue = false
    #if os(macOS)
    private var queuePollTimer: Timer?
    private var lastQueueFileModificationDate: Date?
    #endif

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

        goodLinksQueueChangeObserver.onChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleGoodLinksSyncQueueChange()
            }
        }
        goodLinksQueueChangeObserver.start()

        #if os(macOS)
        // Darwin notifications between a Mac Catalyst extension and the main app
        // are unreliable. Re-check the queue every time the app comes to the
        // foreground so freshly-queued items always appear.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSharedQueueChange()
            }
        }
        #endif
    }

    func startup() async {
        reloadSharedPreferences()
        reloadQueueFromDisk()
        reloadGoodLinksSyncQueue()
        reloadSessionFromDisk()

        isAccountSectionExpanded = session == nil || !GoogleOAuthConfig.isConfigured

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        Task {
            await AnalyticsClient.shared.send("app_launched", params: ["app_version": version], enabled: analyticsEnabled)
        }
        recordDailyActiveIfNeeded()

        #if os(macOS)
        checkForShareExtensionDebugError()
        startQueuePolling()
        #endif

        await processQueue()
    }

    #if os(macOS)
    private func startQueuePolling() {
        queuePollTimer?.invalidate()
        queuePollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkQueueFileForChanges()
            }
        }
    }

    private func checkQueueFileForChanges() {
        guard let fileURL = try? SharedContainer.appDirectoryURL()
            .appendingPathComponent("queued-emails.json", isDirectory: false),
              let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path(percentEncoded: false)),
              let modDate = attrs[.modificationDate] as? Date,
              modDate != lastQueueFileModificationDate else { return }
        lastQueueFileModificationDate = modDate
        handleSharedQueueChange()
    }

    private func checkForShareExtensionDebugError() {
        guard let url = try? SharedContainer.appDirectoryURL()
            .appendingPathComponent("share-extension-last-error.txt", isDirectory: false),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }
        statusMessage = "⚠️ Last share attempt failed — \(text)"
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
            Task {
                await AnalyticsClient.shared.send("gmail_connected", enabled: analyticsEnabled)
            }
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

        let wasShowingOnboarding = shouldShowOnboarding
        reloadSharedPreferences()
        if wasShowingOnboarding { shouldShowOnboarding = true }
        reloadSessionFromDisk()
        reloadQueueFromDisk()
        reloadGoodLinksSyncQueue()

        #if os(macOS)
        await processSyncedGoodLinksQueue()
        #endif

        guard !queuedEmails.isEmpty else { return }
        guard let existingSession = session else {
            statusMessage = "You have queued items. Sign in to Gmail to send them."
            return
        }
        guard isOnline else { return }

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
                    if next.needsEmailDelivery {
                        try await client.sendEmail(using: validSession, item: next)
                        markEmailDelivered(for: next.id)
                        RecipientStore.record(next.toEmail)
                        await AnalyticsClient.shared.send("email_sent", enabled: analyticsEnabled)
                        statusMessage = "Sent \"\(next.title)\" to \(next.toEmail)."
                    }

                    if queuedEmails.last?.id == next.id,
                       queuedEmails.last?.needsGoodLinksDelivery == true {
                        try await deliverGoodLinksCopy(for: queuedEmails.last!)
                    }

                    if let updated = queuedEmails.last, updated.id == next.id, updated.isFullyDelivered {
                        removeManagedMedia(for: updated)
                        removeQueuedEmail(id: updated.id)
                    }
                } catch {
                    if let gmailError = error as? GmailAPIError, gmailError.requiresReconnect {
                        requiresGmailReconnect = true
                        isAccountSectionExpanded = true
                        isQueueSectionExpanded = true
                        markFailure(for: next.id, message: gmailError.localizedDescription)
                        statusMessage = "Reconnect Gmail to grant send permission. Queued items will send after you reconnect."
                    } else if error is GoodLinksError {
                        markGoodLinksFailure(for: next.id, message: error.localizedDescription)
                        statusMessage = "Email is done. GoodLinks copy is queued for retry: \(error.localizedDescription)"
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
        savedRecipients = RecipientStore.load()
    }

    func addSavedRecipient(_ recipient: String) {
        RecipientStore.record(recipient)
        savedRecipients = RecipientStore.load()
    }

    func removeSavedRecipient(_ recipient: String) {
        let normalizedRecipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedDefault = defaultRecipient.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedRecipient != normalizedDefault else {
            return
        }

        RecipientStore.remove(recipient)
        savedRecipients = RecipientStore.load()
    }

    func setShareSheetAutoSendEnabled(_ isEnabled: Bool) {
        RecipientStore.setShareSheetAutoSendEnabled(isEnabled)
        shareSheetAutoSendEnabled = RecipientStore.loadShareSheetAutoSendEnabled()
    }

    func setGoodLinksSettings(_ settings: GoodLinksSettings) {
        let previousSettings = goodLinksSettings
        GoodLinksSettingsStore.save(settings)
        goodLinksSettings = GoodLinksSettingsStore.load()
        if previousSettings.apiAddress != goodLinksSettings.apiAddress ||
            previousSettings.apiToken != goodLinksSettings.apiToken {
            goodLinksConnectionMessage = nil
            goodLinksConnectionSucceeded = false
        }
    }

    func testGoodLinksConnection() async {
        guard !isTestingGoodLinks else { return }
        isTestingGoodLinks = true
        defer { isTestingGoodLinks = false }

        do {
            let settings = GoodLinksSettingsStore.load()
            try await goodLinksService.testLocalAPI(settings: settings)
            goodLinksConnectionSucceeded = true
            goodLinksConnectionMessage = "Connection verified."
            statusMessage = "GoodLinks connection verified."
            #if os(macOS)
            await processSyncedGoodLinksQueue()
            #endif
        } catch {
            goodLinksConnectionSucceeded = false
            goodLinksConnectionMessage = error.localizedDescription
            statusMessage = "GoodLinks test failed: \(error.localizedDescription)"
        }
    }

    func retryNow() async {
        let wasShowingOnboarding = shouldShowOnboarding
        reloadSharedPreferences()
        if wasShowingOnboarding { shouldShowOnboarding = true }
        reloadSessionFromDisk()
        reloadQueueFromDisk()
        reloadGoodLinksSyncQueue()
        await processQueue()
    }

    func deleteSyncedGoodLinksJob(id: UUID) {
        do {
            try GoodLinksSyncStore.remove(id: id)
            reloadGoodLinksSyncQueue()
        } catch {
            statusMessage = "Could not remove GoodLinks sync item: \(error.localizedDescription)"
        }
    }

    func resetSetup() {
        guard !isBusy else { return }

        do {
            try KeychainStore.clearSession()
            SharedSessionStore.clear()
            RecipientStore.resetSetup()
            GoodLinksSettingsStore.reset()

            session = nil
            defaultRecipient = RecipientStore.loadDefault()
            savedRecipients = RecipientStore.load()
            shareSheetAutoSendEnabled = RecipientStore.loadShareSheetAutoSendEnabled()
            goodLinksSettings = GoodLinksSettingsStore.load()
            goodLinksConnectionMessage = nil
            goodLinksConnectionSucceeded = false
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
        Task {
            await AnalyticsClient.shared.send("onboarding_completed", enabled: analyticsEnabled)
        }
    }

    func setAnalyticsEnabled(_ isEnabled: Bool) {
        RecipientStore.setAnalyticsEnabled(isEnabled)
        analyticsEnabled = RecipientStore.loadAnalyticsEnabled()
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

    private func reloadGoodLinksSyncQueue() {
        syncedGoodLinksJobs = GoodLinksSyncStore.load()
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

    private func markEmailDelivered(for id: UUID) {
        if let index = queuedEmails.firstIndex(where: { $0.id == id }) {
            queuedEmails[index].emailDeliveredAt = .now
            queuedEmails[index].lastError = nil
            persistQueue()
        }
    }

    private func markGoodLinksDelivered(for id: UUID) {
        if let index = queuedEmails.firstIndex(where: { $0.id == id }) {
            queuedEmails[index].goodLinksDeliveredAt = .now
            queuedEmails[index].goodLinksLastError = nil
            persistQueue()
        }
    }

    private func markGoodLinksFailure(for id: UUID, message: String) {
        if let index = queuedEmails.firstIndex(where: { $0.id == id }) {
            queuedEmails[index].goodLinksLastError = message
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
        savedRecipients = RecipientStore.load()
        shareSheetAutoSendEnabled = RecipientStore.loadShareSheetAutoSendEnabled()
        goodLinksSettings = GoodLinksSettingsStore.load()
        shouldShowOnboarding = !RecipientStore.loadHasCompletedOnboarding()
        analyticsEnabled = RecipientStore.loadAnalyticsEnabled()
    }

    private func recordDailyActiveIfNeeded() {
        let key = "analytics.lastActiveDate"
        let today = Calendar.current.startOfDay(for: Date())
        if let last = UserDefaults.standard.object(forKey: key) as? Date,
           Calendar.current.isDate(last, inSameDayAs: today) { return }
        UserDefaults.standard.set(today, forKey: key)
        Task {
            await AnalyticsClient.shared.send("app_active", enabled: analyticsEnabled)
        }
    }

    private func reloadSessionFromDisk() {
        // Skip the keychain read if a session is already live in memory.
        // The keychain only needs to be consulted on cold start; after that
        // the in-memory session is kept current by processQueue's token refresh.
        guard session == nil else { return }

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
        let wasShowingOnboarding = shouldShowOnboarding
        reloadSharedPreferences()
        if wasShowingOnboarding { shouldShowOnboarding = true }
        reloadSessionFromDisk()
        reloadQueueFromDisk()
        Task {
            await processQueue()
            #if os(macOS)
            checkForShareExtensionDebugError()
            #endif
        }
    }

    private func handleGoodLinksSyncQueueChange() {
        reloadGoodLinksSyncQueue()

        #if os(macOS)
        guard syncedGoodLinksJobs.contains(where: { $0.lastError == nil }) else {
            return
        }

        Task {
            await processSyncedGoodLinksQueue()
        }
        #endif
    }

    private func removeManagedMedia(for item: QueuedEmail) {
        item.allImageURLStrings.forEach { SharedContainer.removeManagedMediaIfPresent(urlString: $0) }
    }

    private func deliverGoodLinksCopy(for item: QueuedEmail) async throws {
        let settings = GoodLinksSettingsStore.load()
        #if os(macOS) || targetEnvironment(macCatalyst)
        do {
            try await goodLinksService.saveUsingLocalAPI(item: item, settings: settings)
            markGoodLinksDelivered(for: item.id)
            statusMessage = "Saved \"\(item.title)\" to GoodLinks."
        } catch {
            markGoodLinksFailure(for: item.id, message: error.localizedDescription)
            throw error
        }
        #elseif os(iOS)
        do {
            try GoodLinksSyncStore.append(item: item, settings: settings)
            reloadGoodLinksSyncQueue()
            markGoodLinksDelivered(for: item.id)
            statusMessage = "Queued \"\(item.title)\" for GoodLinks on your Mac."
        } catch {
            markGoodLinksFailure(for: item.id, message: error.localizedDescription)
            throw error
        }
        #endif
    }

    #if os(macOS)
    private func processSyncedGoodLinksQueue() async {
        let result = await GoodLinksSyncProcessor.drain(using: goodLinksService)
        reloadGoodLinksSyncQueue()
        if result.didSaveJobs {
            statusMessage = result.savedCount == 1
                ? "Saved 1 synced GoodLinks item."
                : "Saved \(result.savedCount) synced GoodLinks items."
        } else if let lastError = result.lastError, result.remainingCount > 0 {
            statusMessage = "Synced GoodLinks items will retry later: \(lastError)"
        }
    }
    #endif

}

private final class QueueChangeObserver {
    var onChange: (() -> Void)?
    private let notificationName: String
    private var isStarted = false

    init(notificationName: String = QueueStore.didChangeNotification) {
        self.notificationName = notificationName
    }

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
            notificationName as CFString,
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
            CFNotificationName(rawValue: notificationName as CFString),
            nil
        )
    }

    deinit {
        stop()
    }
}
