import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var draft = ShareDraft()
    @Published var queuedEmails: [QueuedEmail] = []
    @Published var savedRecipients: [String] = []
    @Published var defaultRecipient = ""
    @Published var session: GmailSession?
    @Published var statusMessage = "Configure Google OAuth, sign in, then queue or send links."
    @Published var isBusy = false
    @Published var isOnline = false

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
        savedRecipients = RecipientStore.load()
        defaultRecipient = RecipientStore.loadDefault()
        if draft.toEmail.isEmpty {
            draft.toEmail = defaultRecipient
        }
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
            statusMessage = "Signed out. Queued items stay on disk until you send them."
        } catch {
            statusMessage = "Could not remove saved Gmail credentials: \(error.localizedDescription)"
        }
    }

    func queueCurrentDraft() async {
        let normalized = normalizeDraft(draft)
        guard normalized.isValidForQueue else {
            statusMessage = "Enter a recipient, title, and valid URL before queuing."
            return
        }

        let item = QueuedEmail(
            toEmail: normalized.toEmail,
            title: normalized.trimmedTitle,
            excerpt: normalized.trimmedExcerpt,
            urlString: normalized.trimmedURLString
        )

        queuedEmails.insert(item, at: 0)
        persistQueue()
        draft = ShareDraft(toEmail: defaultRecipient)
        statusMessage = "Saved offline. The app will keep retrying until Gmail accepts it."
        await processQueue()
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
                    removeQueuedEmail(id: next.id)
                    RecipientStore.record(next.toEmail)
                    savedRecipients = RecipientStore.load()
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
        queuedEmails.remove(atOffsets: offsets)
        persistQueue()
    }

    func useSavedRecipient(_ recipient: String) {
        draft.toEmail = recipient
    }

    func setDefaultRecipient(_ recipient: String) {
        RecipientStore.setDefault(recipient)
        defaultRecipient = RecipientStore.loadDefault()
        savedRecipients = RecipientStore.load()
        draft.toEmail = defaultRecipient
    }

    func retryNow() async {
        savedRecipients = RecipientStore.load()
        defaultRecipient = RecipientStore.loadDefault()
        if draft.toEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.toEmail = defaultRecipient
        }
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

    private func normalizeDraft(_ draft: ShareDraft) -> ShareDraft {
        var copy = draft
        copy.toEmail = draft.toEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.title = draft.trimmedTitle
        copy.excerpt = draft.trimmedExcerpt
        copy.urlString = draft.trimmedURLString
        return copy
    }

    private func removeQueuedEmail(id: UUID) {
        queuedEmails.removeAll { $0.id == id }
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
