import SwiftUI

struct MacQueuePane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if model.queuedEmails.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(displayedQueue) { item in
                            MacQueueRow(
                                item: item,
                                isRetryCandidate: item.id == retryCandidateID,
                                retryDisabled: model.isBusy || model.requiresGmailReconnect,
                                onRetry: retryQueue,
                                onDelete: {
                                    model.deleteQueuedEmail(id: item.id)
                                }
                            )
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var displayedQueue: [QueuedEmail] {
        model.queuedEmails.reversed()
    }

    private var retryCandidateID: UUID? {
        model.queuedEmails.last?.id
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Queue")
                        .font(.system(size: 28, weight: .semibold))

                    if let headerSummary {
                        Text(headerSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                HStack(spacing: 10) {
                    if showsReconnectButton {
                        Button("Reconnect Gmail") {
                            Task {
                                await model.signIn()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy || !GoogleOAuthConfig.isConfigured)
                    }

                    if showsSignInButton {
                        Button("Sign In With Google") {
                            Task {
                                await model.signIn()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy || !GoogleOAuthConfig.isConfigured)
                    }

                    if showsRetryAllButton {
                        Button("Retry All") {
                            retryQueue()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy)
                    }
                }
            }

            if let statusBannerMessage {
                Text(statusBannerMessage)
                    .font(.footnote)
                    .foregroundStyle(statusBannerTint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(0.04))
                    )
            }
        }
        .padding(20)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(emptyStateMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var headerSummary: String? {
        guard !model.queuedEmails.isEmpty else {
            return nil
        }

        if model.requiresGmailReconnect {
            return "Reconnect Gmail to restore send permission for these queued items."
        }

        if model.session == nil {
            return "Sign in to Gmail to send queued items from this Mac."
        }

        return model.isOnline
            ? "SendMoi retries automatically when the network and Gmail session are healthy."
            : "Items stay here until the app can reach the network again."
    }

    private var emptyStateMessage: String {
        model.isOnline
            ? "Queue clear. Shared items that need attention will appear here."
            : "Queue clear. If the network drops, shared items will wait here until SendMoi can retry."
    }

    private var showsReconnectButton: Bool {
        model.requiresGmailReconnect && !model.queuedEmails.isEmpty
    }

    private var showsSignInButton: Bool {
        model.session == nil && !model.queuedEmails.isEmpty
    }

    private var showsRetryAllButton: Bool {
        !model.queuedEmails.isEmpty && model.session != nil && !model.requiresGmailReconnect
    }

    private var statusBannerMessage: String? {
        let message = model.statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return nil
        }

        if message.hasPrefix("Signed in as ") {
            return nil
        }

        if message == "Configure Google OAuth, sign in, then queue or send shared items." {
            return nil
        }

        if model.requiresGmailReconnect && message.hasPrefix("Reconnect Gmail") {
            return nil
        }

        if model.session == nil && !model.queuedEmails.isEmpty && message.contains("Sign in to Gmail") {
            return nil
        }

        return message
    }

    private var statusBannerTint: Color {
        if model.requiresGmailReconnect || model.statusMessage.contains("failed") || model.statusMessage.contains("Could not") {
            return .orange
        }

        return .secondary
    }

    private func retryQueue() {
        Task {
            await model.retryNow()
        }
    }
}

private struct MacQueueRow: View {
    let item: QueuedEmail
    let isRetryCandidate: Bool
    let retryDisabled: Bool
    let onRetry: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.headline)

                    LabeledContent("Recipient", value: item.toEmail)
                        .font(.subheadline)

                    if let sourceLabel {
                        LabeledContent("Source", value: sourceLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let lastError = item.lastError {
                        Text(lastError)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 10) {
                    if isRetryCandidate {
                        Button("Retry Now", action: onRetry)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(retryDisabled)
                    }

                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if !item.urlString.isEmpty {
                Text(item.urlString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var sourceLabel: String? {
        guard !item.urlString.isEmpty else {
            return nil
        }

        return URL(string: item.urlString)?.host ?? item.urlString
    }
}

#if DEBUG
@MainActor
private struct MacQueuePane_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MacQueuePane()
                .environmentObject(
                    SendMoiPreviewFixtures.appModel(
                        queuedEmails: SendMoiPreviewFixtures.queuedItems,
                        defaultRecipient: "ideas@sendmoi.app",
                        shareSheetAutoSendEnabled: true,
                        session: SendMoiPreviewFixtures.connectedSession,
                        statusMessage: "SendMoi retries automatically when the network and Gmail session are healthy.",
                        isOnline: true
                    )
                )
                .frame(width: 760, height: 520)
                .previewDisplayName("Queued Items")

            MacQueuePane()
                .environmentObject(
                    SendMoiPreviewFixtures.appModel(
                        queuedEmails: [],
                        defaultRecipient: "ideas@sendmoi.app",
                        shareSheetAutoSendEnabled: true,
                        session: SendMoiPreviewFixtures.connectedSession,
                        statusMessage: "Nothing is waiting right now.",
                        isOnline: true
                    )
                )
                .frame(width: 760, height: 520)
                .previewDisplayName("Empty Queue")
        }
    }
}
#endif
