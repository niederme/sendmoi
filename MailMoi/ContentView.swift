import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                shareSheetSection
                composeSection
                queueSection
                statusMessageView
                attributionSection
            }
            .navigationTitle("MailMoi")
            .onChange(of: model.draft.urlString) { _, _ in
                model.scheduleDraftPreviewRefresh()
            }
        }
    }

    private var accountSummaryTitle: String {
        if let session = model.session {
            return session.emailAddress ?? "Connected to Gmail"
        }

        return "No Gmail account connected"
    }

    private var accountSummaryDetail: String {
        let normalizedDefaultRecipient = model.defaultRecipient
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedSessionEmail = model.session?.emailAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let normalizedSessionEmail {
            if normalizedDefaultRecipient.isEmpty {
                return "Signed in to Gmail"
            }

            if normalizedDefaultRecipient == normalizedSessionEmail {
                return "Default recipient matches this account"
            }
        }

        if model.defaultRecipient.isEmpty {
            return "Tap to manage account"
        }

        return "Default recipient: \(model.defaultRecipient)"
    }

    private var accountSection: some View {
        Section {
            DisclosureGroup(isExpanded: $model.isAccountSectionExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Default Recipient")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    #if os(iOS)
                    TextField("Email address", text: $model.defaultRecipient)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                    #else
                    TextField("Email address", text: $model.defaultRecipient)
                    #endif
                }

                Button("Save Default Recipient") {
                    model.setDefaultRecipient(model.defaultRecipient)
                }

                if let session = model.session {
                    LabeledContent("From", value: session.emailAddress ?? "Authenticated via Gmail")
                    Button("Sign Out") {
                        model.signOut()
                    }
                    .disabled(model.isBusy)
                } else {
                    Text("No Gmail account connected.")
                        .foregroundStyle(.secondary)
                    Button("Sign In With Google") {
                        Task {
                            await model.signIn()
                        }
                    }
                    .disabled(model.isBusy || !GoogleOAuthConfig.isConfigured)
                }

                if !GoogleOAuthConfig.isConfigured {
                    Text("Set `GoogleOAuthConfig.clientID` before signing in.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(accountSummaryTitle)
                    Text(accountSummaryDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Tap to manage Gmail and your default recipient.")
        }
    }

    private var composeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("To")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #if os(iOS)
                TextField("Email address", text: $model.draft.toEmail)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                #else
                TextField("Email address", text: $model.draft.toEmail)
                #endif
                if !recentRecipientSuggestions.isEmpty {
                    recentRecipientsView
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 10) {
                    if previewImageURL != nil || model.isRefreshingDraftPreview {
                        previewThumbnail
                    }

                    ZStack(alignment: .topLeading) {
                        TextField(titleIsLoading ? "" : "Page title", text: $model.draft.title, axis: .vertical)
                            .lineLimit(3, reservesSpace: true)

                        if titleIsLoading {
                            fieldLoadingIndicator(topPadding: 8)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $model.draft.excerpt)
                        .frame(minHeight: 80)

                    if descriptionIsLoading {
                        fieldLoadingIndicator(topPadding: 8)
                    }
                }
            }

            if shouldShowSummarySection {
                previewMetadataSection
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("URL")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #if os(iOS)
                TextField("https://example.com", text: $model.draft.urlString)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                #else
                TextField("https://example.com", text: $model.draft.urlString)
                #endif
            }

            Button {
                Task {
                    await model.queueCurrentDraft()
                }
            } label: {
                Text(model.isBusy ? "Working..." : "Queue And Send")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isBusy)
        } header: {
            Text("Compose")
        }
    }

    private var shareSheetSection: some View {
        Section {
            Toggle(
                "Auto-send",
                isOn: Binding(
                    get: { model.shareSheetAutoSendEnabled },
                    set: { model.setShareSheetAutoSendEnabled($0) }
                )
            )
        } header: {
            Text("Share Sheet")
        } footer: {
            Text(
                model.shareSheetAutoSendEnabled
                    ? "Links shared from other apps send automatically when enough page details are available."
                    : "Links shared from other apps stay open so you can review the draft before sending."
            )
        }
    }

    private var previewThumbnail: some View {
        Group {
            if let previewURL = previewImageURL {
                AsyncImage(url: previewURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.12))
                    }
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.12))
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var previewMetadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Summary")
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                if model.isRefreshingDraftPreview && model.draft.summary.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(model.draft.summary)
                        .font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var recentRecipientsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recentRecipientSuggestions, id: \.self) { recipient in
                        Button(recipient) {
                            model.useSavedRecipient(recipient)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private var previewImageURL: URL? {
        guard let urlString = model.draft.previewImageURLString else {
            return nil
        }

        return URL(string: urlString)
    }

    private var recentRecipientSuggestions: [String] {
        let currentRecipient = model.draft.toEmail
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return model.savedRecipients
            .filter { $0.lowercased() != currentRecipient }
            .prefix(4)
            .map { $0 }
    }

    private var titleIsLoading: Bool {
        model.isRefreshingDraftPreview && model.draft.trimmedTitle.isEmpty
    }

    private var descriptionIsLoading: Bool {
        model.isRefreshingDraftPreview && model.draft.trimmedExcerpt.isEmpty
    }

    private var shouldShowSummarySection: Bool {
        model.isRefreshingDraftPreview || !model.draft.summary.isEmpty
    }

    private func fieldLoadingIndicator(topPadding: CGFloat) -> some View {
        ProgressView()
            .controlSize(.small)
            .padding(.top, topPadding)
    }

    private var queueSection: some View {
        Section {
            if model.queuedEmails.isEmpty {
                Text("No pending emails.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.queuedEmails) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.headline)
                        Text("To: \(item.toEmail)")
                            .font(.subheadline)
                        Text(item.urlString)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let lastError = item.lastError {
                            Text(lastError)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: model.deleteQueuedEmails)
            }

            Button("Send Queued Now") {
                Task {
                    await model.retryNow()
                }
            }
            .disabled(model.isBusy || model.queuedEmails.isEmpty)
        } header: {
            Text("Offline Queue")
        } footer: {
            Text(model.isOnline ? "Network looks available. The app retries automatically." : "Offline or unreachable. Items remain queued.")
        }
    }

    private var statusMessageView: some View {
        Text(model.statusMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributionSection: some View {
        Section {
            EmptyView()
        } footer: {
            Text("MailMoi by John Niedermeyer, with a little help from Codex, Claude Code and friends.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
}
