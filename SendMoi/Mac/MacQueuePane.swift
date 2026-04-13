import SwiftUI

struct MacQueuePane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        MacSidebarCard(
            title: "Queue",
            subtitle: cardSubtitle
        ) {
            VStack(alignment: .leading, spacing: 12) {
                actionButtons

                if displayedQueue.isEmpty {
                    Text(emptyStateMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

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
        }
    }

    private var displayedQueue: [QueuedEmail] {
        model.queuedEmails.reversed()
    }

    private var retryCandidateID: UUID? {
        model.queuedEmails.last?.id
    }

    private var cardSubtitle: String {
        if model.requiresGmailReconnect {
            return "Reconnect Gmail to restore send permission, then retry the queue."
        }
        if model.queuedEmails.isEmpty {
            return "Shared items that need attention will appear here."
        }
        if model.session == nil {
            return "Sign in to Gmail to send queued items from this Mac."
        }
        return model.isOnline
            ? "SendMoi retries automatically when the network and Gmail session are healthy."
            : "Items stay here until the app can reach the network again."
    }

    private var emptyStateMessage: String {
        if model.session == nil {
            return "Queue is clear. Sign in to Gmail before sharing from this Mac."
        }

        return model.isOnline
            ? "Queue is clear."
            : "Queue is clear. New items will stay here until the Mac is back online."
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 10) {
            if showsReconnectButton {
                Button("Reconnect Gmail") {
                    Task { await model.signIn() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || !GoogleOAuthConfig.isConfigured)
            }

            if showsSignInButton {
                Button("Sign In With Google") {
                    Task { await model.signIn() }
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

    private var showsReconnectButton: Bool {
        model.requiresGmailReconnect
    }

    private var showsSignInButton: Bool {
        model.session == nil && !model.queuedEmails.isEmpty
    }

    private var showsRetryAllButton: Bool {
        !model.queuedEmails.isEmpty && model.session != nil && !model.requiresGmailReconnect
    }

    private func retryQueue() {
        Task { await model.retryNow() }
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
        guard !item.urlString.isEmpty else { return nil }
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
                .frame(width: 620, height: 400)
                .padding(20)
                .previewDisplayName("Queued Items")

            MacQueuePane()
                .environmentObject(
                    SendMoiPreviewFixtures.appModel(
                        queuedEmails: SendMoiPreviewFixtures.reconnectQueue,
                        defaultRecipient: "ideas@sendmoi.app",
                        shareSheetAutoSendEnabled: false,
                        session: SendMoiPreviewFixtures.connectedSession,
                        statusMessage: "Reconnect Gmail to restore send permission.",
                        isOnline: false,
                        requiresGmailReconnect: true
                    )
                )
                .frame(width: 620, height: 400)
                .padding(20)
                .previewDisplayName("Reconnect Required")
        }
    }
}
#endif
