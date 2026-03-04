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

    private let client = GmailAPIClient()
    private let monitor = NetworkMonitor()

    init() {
        monitor.onStatusChange = { [weak self] online in
            Task { @MainActor [weak self] in
                self?.handleNetworkChange(online: online)
            }
        }
    }

    func startup() async {
        defaultRecipient = RecipientStore.loadDefault()
        shareSheetAutoSendEnabled = RecipientStore.loadShareSheetAutoSendEnabled()
        reloadQueueFromDisk()

        do {
            session = try KeychainStore.loadSession()
            if session == nil {
                session = try SharedSessionStore.load()
            }
            if let session {
                self.session = session
                try? SharedSessionStore.save(session)
                statusMessage = "Signed in as \(session.emailAddress ?? "your Gmail account")."
            }
        } catch {
            statusMessage = "Could not read saved Gmail credentials: \(error.localizedDescription)"
        }

        isAccountSectionExpanded = session == nil || !GoogleOAuthConfig.isConfigured

        await processQueue()
    }

    func signIn() async {
        guard !isBusy else { return }
        isBusy = true

        do {
            let signedInSession = try await client.signIn()
            session = signedInSession
            try KeychainStore.save(session: signedInSession)
            try SharedSessionStore.save(signedInSession)
            statusMessage = "Signed in as \(signedInSession.emailAddress ?? "your Gmail account")."
            isAccountSectionExpanded = false
            reloadQueueFromDisk()
        } catch {
            statusMessage = "Sign in failed: \(error.localizedDescription)"
        }

        isBusy = false

        if session != nil {
            await processQueue()
        }
    }

    func signOut() {
        guard !isBusy else { return }
        do {
            try KeychainStore.clearSession()
            SharedSessionStore.clear()
            session = nil
            isAccountSectionExpanded = true
            statusMessage = "Signed out. Queued items stay on disk until you send them."
        } catch {
            statusMessage = "Could not remove saved Gmail credentials: \(error.localizedDescription)"
        }
    }

    func processQueue() async {
        guard !isBusy else { return }
        reloadQueueFromDisk()
        guard !queuedEmails.isEmpty else { return }
        guard let existingSession = session else {
            statusMessage = "You have queued items. Sign in to Gmail to send them."
            return
        }

        isBusy = true
        defer { isBusy = false }

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
                    SharedContainer.removeManagedMediaIfPresent(urlString: next.previewImageURLString)
                    removeQueuedEmail(id: next.id)
                    RecipientStore.record(next.toEmail)
                    statusMessage = "Sent \"\(next.title)\" to \(next.toEmail)."
                } catch {
                    markFailure(for: next.id, message: error.localizedDescription)
                    statusMessage = "Queued item kept for retry: \(error.localizedDescription)"
                    break
                }
            }
        } catch {
            statusMessage = "Queue processing paused: \(error.localizedDescription)"
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
        defaultRecipient = RecipientStore.loadDefault()
        reloadQueueFromDisk()
        await processQueue()
    }

    private func reloadQueueFromDisk() {
        do {
            queuedEmails = try QueueStore.load()
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
            SharedContainer.removeManagedMediaIfPresent(urlString: item.previewImageURLString)
        }
        queuedEmails.removeAll { ids.contains($0.id) }
        persistQueue()
    }

    private func markFailure(for id: UUID, message: String) {
        if let index = queuedEmails.firstIndex(where: { $0.id == id }) {
            queuedEmails[index].lastError = message
            persistQueue()
        }
    }

    private func persistQueue() {
        do {
            try QueueStore.save(queuedEmails)
        } catch {
            statusMessage = "Could not save the offline queue: \(error.localizedDescription)"
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
}
