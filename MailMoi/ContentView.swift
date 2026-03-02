import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case defaultRecipient
    }

    var body: some View {
        NavigationStack {
            rootContent
                .navigationTitle("MailMoi")
        }
        .onChange(of: model.draft.urlString) { _, _ in
            model.scheduleDraftPreviewRefresh()
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if usesDesktopLayout {
        desktopContent
        } else {
        mobileContent
        }
    }

    private var usesDesktopLayout: Bool {
        #if os(macOS) || targetEnvironment(macCatalyst)
        true
        #else
        ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    private var mobileContent: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 700 {
                wideIOSContent
            } else {
                compactMobileContent
            }
        }
    }

    private var compactMobileContent: some View {
        Form {
            accountSection
            defaultRecipientSection
            shareSheetSection
            composeSection
            queueSection
            statusMessageView
            attributionSection
        }
    }

    private var accountSummaryTitle: String {
        if let session = model.session {
            return session.emailAddress ?? "Connected to Gmail"
        }

        return "No Gmail account connected"
    }

    private var accountSummaryDetail: String {
        if model.session != nil {
            return "Signed in to Gmail"
        }

        if usesDesktopLayout {
        return "Click to manage account"
        } else {
        return "Tap to manage account"
        }
    }

    private var accountSection: some View {
        Section {
            DisclosureGroup(isExpanded: $model.isAccountSectionExpanded) {
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
            Text(accountSectionFooterText)
        }
    }

    private var defaultRecipientSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Default Recipient")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #if os(iOS)
                TextField("Email address", text: $model.defaultRecipient)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focusedField, equals: .defaultRecipient)
                    .onSubmit(saveDefaultRecipient)
                #else
                TextField("Email address", text: $model.defaultRecipient)
                    .onSubmit(saveDefaultRecipient)
                #endif
            }

            Button {
                saveDefaultRecipient()
            } label: {
                Text("Save Default Recipient")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } header: {
            Text("Recipient")
        } footer: {
            Text("Used as the default when starting from the share sheet.")
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
                        TextField(titleIsLoading ? "" : "Title", text: $model.draft.title, axis: .vertical)
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
                Text("Link (Optional)")
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
            Text(shareSheetFooterText)
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

    private var previewMetadataContent: some View {
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

    private var previewMetadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Summary")
                .font(.caption)
                .foregroundStyle(.secondary)

            previewMetadataContent
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

    private var desktopRecentRecipientsChips: some View {
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

    private var previewImageURL: URL? {
        guard let urlString = model.draft.previewImageURLString else {
            return nil
        }

        return URL(string: urlString)
    }

    private var shareSheetFooterText: String {
        if model.shareSheetAutoSendEnabled {
            return "Items shared from other apps send automatically when enough details are available."
        }

        return "Items shared from other apps stay open so you can review the draft before sending."
    }

    private var accountSectionFooterText: String {
        if usesDesktopLayout {
        return "Manage Gmail sign-in for the desktop app."
        } else {
        return "Tap to manage Gmail sign-in."
        }
    }

    private var queueFooterText: String {
        model.isOnline ? "Network looks available. The app retries automatically." : "Offline or unreachable. Items remain queued."
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

    private func saveDefaultRecipient() {
        focusedField = nil
        model.setDefaultRecipient(model.defaultRecipient)
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
            Text(queueFooterText)
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

extension ContentView {
    private var wideIOSContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                desktopTopRow
                desktopComposeCard
                desktopQueueCard
                desktopStatusCard
                desktopAttribution
            }
            .frame(maxWidth: 920)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(desktopBackground.ignoresSafeArea())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var desktopContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                desktopHeader
                desktopTopRow
                desktopComposeCard
                desktopQueueCard
                desktopStatusCard
                desktopAttribution
            }
            .frame(maxWidth: 860)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(desktopBackground.ignoresSafeArea())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var desktopHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MailMoi")
                    .font(.system(size: 28, weight: .semibold))

                Text("Queue links, notes, and images in a layout that reads like a desktop app instead of a stretched settings pane.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 20)

            Text(model.isOnline ? "Online" : "Offline")
                .font(.caption.weight(.semibold))
                .foregroundStyle(model.isOnline ? Color.green : Color.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill((model.isOnline ? Color.green : Color.orange).opacity(0.12))
                )
        }
    }

    private var desktopTopRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                desktopAccountCard
                    .frame(maxWidth: .infinity, alignment: .top)
                desktopPreferencesCard
                    .frame(maxWidth: .infinity, alignment: .top)
            }

            VStack(alignment: .leading, spacing: 18) {
                desktopAccountCard
                desktopPreferencesCard
            }
        }
    }

    private var desktopAccountCard: some View {
        desktopSectionCard(
            title: "Account",
            subtitle: accountSectionFooterText,
            fixedHeight: desktopTopCardHeight
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: model.session == nil ? "person.crop.circle.badge.exclamationmark" : "checkmark.shield.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(model.session == nil ? Color.orange : Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(accountSummaryTitle)
                            .font(.headline)
                        Text(accountSummaryDetail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                if let session = model.session {
                    desktopReadout(label: "Signed in as", value: session.emailAddress ?? "Authenticated via Gmail")

                    HStack {
                        Button("Sign Out", role: .destructive) {
                            model.signOut()
                        }
                        .disabled(model.isBusy)

                        Spacer()
                    }
                } else {
                    Text("No Gmail account connected.")
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Sign In With Google") {
                            Task {
                                await model.signIn()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy || !GoogleOAuthConfig.isConfigured)

                        Spacer()
                    }
                }

                if !GoogleOAuthConfig.isConfigured {
                    Text("Set `GoogleOAuthConfig.clientID` before signing in.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var desktopPreferencesCard: some View {
        desktopSectionCard(
            title: "Preferences",
            fixedHeight: desktopTopCardHeight
        ) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    desktopFieldLabel("Default Recipient")

                    HStack {
                        TextField("Email address", text: $model.defaultRecipient)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveDefaultRecipient)
                            .frame(maxWidth: .infinity)

                        Button("Save Default Recipient") {
                            saveDefaultRecipient()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy)
                    }

                    Text("Used as the default when starting from the share sheet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Toggle(isOn: Binding(
                    get: { model.shareSheetAutoSendEnabled },
                    set: { model.setShareSheetAutoSendEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Auto-send shared items")
                        Text(shareSheetFooterText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
        }
    }

    private var desktopComposeCard: some View {
        desktopSectionCard(title: "Compose") {
            VStack(alignment: .leading, spacing: 16) {
                desktopComposeMainColumn

                HStack {
                    Text("Drafts queue locally and retry automatically when the network is available.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        Task {
                            await model.queueCurrentDraft()
                        }
                    } label: {
                        Text(model.isBusy ? "Working..." : "Queue And Send")
                            .frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.isBusy)
                }
            }
        }
    }

    private var desktopComposeMainColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                desktopInputGroup("To") {
                    TextField("Email address", text: $model.draft.toEmail)
                        .textFieldStyle(.roundedBorder)

                    if !recentRecipientSuggestions.isEmpty {
                        desktopRecentRecipientsChips
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                desktopInputGroup("Link") {
                    TextField("https://example.com", text: $model.draft.urlString)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(width: 250, alignment: .leading)
            }

            if shouldShowDesktopPreviewPanel {
                desktopPreviewPanel
            }

            desktopInputGroup("Title") {
                ZStack(alignment: .topLeading) {
                    TextField(titleIsLoading ? "" : "Title", text: $model.draft.title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.title3.weight(.medium))
                        .lineLimit(3, reservesSpace: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(desktopEditorSurface)

                    if titleIsLoading {
                        fieldLoadingIndicator(topPadding: 12)
                            .padding(.leading, 14)
                    }
                }
            }

            desktopInputGroup("Description") {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $model.draft.excerpt)
                        .scrollContentBackground(.hidden)
                        .font(.body)
                        .frame(minHeight: 220)
                        .padding(10)
                        .background(desktopEditorSurface)

                    if descriptionIsLoading {
                        fieldLoadingIndicator(topPadding: 18)
                            .padding(.leading, 18)
                    }
                }
            }
        }
    }

    private var shouldShowDesktopPreviewPanel: Bool {
        (previewImageURL != nil) || model.isRefreshingDraftPreview || shouldShowSummarySection
    }

    private var desktopPreviewPanel: some View {
        HStack(alignment: .top, spacing: 14) {
            if previewImageURL != nil || model.isRefreshingDraftPreview {
                Group {
                    if let previewURL = previewImageURL {
                        AsyncImage(url: previewURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.primary.opacity(0.03))
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        }
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.primary.opacity(0.03))
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .frame(width: 120, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                if shouldShowSummarySection {
                    Text("AI Summary")
                        .font(.footnote.weight(.semibold))
                    previewMetadataContent
                } else if model.isRefreshingDraftPreview {
                    Text("Fetching page details...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var desktopQueueCard: some View {
        desktopSectionCard(
            title: "Offline Queue",
            subtitle: queueFooterText
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if model.queuedEmails.isEmpty {
                    Text("No pending emails.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.primary.opacity(0.03))
                        )
                } else {
                    ForEach(model.queuedEmails) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.title)
                                        .font(.headline)

                                    Text("To: \(item.toEmail)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    if !item.urlString.isEmpty {
                                        Text(item.urlString)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }

                                    if let lastError = item.lastError {
                                        Text(lastError)
                                            .font(.footnote)
                                            .foregroundStyle(.orange)
                                    }
                                }

                                Spacer()

                                Button(role: .destructive) {
                                    model.deleteQueuedEmail(id: item.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .disabled(model.isBusy)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.primary.opacity(0.03))
                        )
                    }
                }

                HStack {
                    Text(model.queuedEmails.isEmpty ? "Queue is empty." : "\(model.queuedEmails.count) item\(model.queuedEmails.count == 1 ? "" : "s") waiting.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Send Queued Now") {
                        Task {
                            await model.retryNow()
                        }
                    }
                    .disabled(model.isBusy || model.queuedEmails.isEmpty)
                }
            }
        }
    }

    private var desktopStatusCard: some View {
        Text(model.statusMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }

    private var desktopAttribution: some View {
        Text("MailMoi by John Niedermeyer, with a little help from Codex, Claude Code and friends.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
    }

    private var desktopBackground: some View {
        LinearGradient(
            colors: [
                Color.primary.opacity(0.05),
                Color.primary.opacity(0.02)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var desktopTopCardHeight: CGFloat {
        250
    }

    private var desktopEditorSurface: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.primary.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private func desktopSectionCard<Content: View>(
        title: String,
        subtitle: String? = nil,
        fixedHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(
            minHeight: fixedHeight,
            maxHeight: fixedHeight,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func desktopInputGroup<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            desktopFieldLabel(label)
            content()
        }
    }

    private func desktopFieldLabel(_ label: String) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func desktopReadout(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
}
