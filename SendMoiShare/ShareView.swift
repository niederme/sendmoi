import SwiftUI

struct ShareView: View {
    @ObservedObject var model: ShareExtensionModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case recipient
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if showsAutoSendOverlayLayout {
                    editorView
                        .allowsHitTesting(false)
                        .overlay {
                            Rectangle()
                                .fill(.black.opacity(0.58))
                                .ignoresSafeArea()
                        }

                    autoSendOverlayCard
                } else if model.presentationMode == .editing {
                    editorView
                } else {
                    processingView
                }
            }
            .navigationTitle("SendMoi")
            .onChange(of: model.recipientFocusRequest) { _, request in
                guard request > 0 else { return }
                focusedField = .recipient
            }
            .onChange(of: model.urlString) { _, _ in
                model.schedulePreviewRefresh()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.cancel()
                    }
                    #if os(macOS)
                    .keyboardShortcut(.cancelAction)
                    #endif
                }

                if showsSendToolbarItem {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(sendButtonTitle) {
                            model.queueAndComplete()
                        }
                        .disabled(sendButtonDisabled)
                        .opacity(model.presentationMode == .editing ? 1 : 0.38)
                        #if os(macOS)
                        .keyboardShortcut(.defaultAction)
                        #endif
                    }
                }
            }
        }
        .alert("Connect Gmail in SendMoi", isPresented: $model.showsGmailConnectAlert) {
            Button("Sign In to Gmail") {
                model.connectGmail()
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("SendMoi is not connected to Gmail on this device yet. Sign in now to send from this share sheet, or choose Not Now and this share will stay queued until you connect Gmail later.")
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 420, idealHeight: 460)
        #endif
    }

    private var editorView: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("To")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    #if os(iOS)
                    TextField("Email address", text: $model.toEmail)
                        .focused($focusedField, equals: .recipient)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                    #else
                    TextField("Email address", text: $model.toEmail)
                        .focused($focusedField, equals: .recipient)
                    #endif
                    if let recipientInlineMessage = model.recipientInlineMessage {
                        Text(recipientInlineMessage)
                            .font(.caption2)
                            .foregroundStyle(model.recipientInlineMessageIsError ? .red : .secondary)
                    }
                    if !recentRecipientSuggestions.isEmpty {
                        recentRecipientsView
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Title")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    #if os(iOS)
                    HStack(alignment: .top, spacing: 10) {
                        if previewImageURL != nil || model.isRefreshingPreview {
                            previewThumbnail
                        }

                        titleInputField(lineLimit: 2)
                    }

                    if previewImageCount > 1 {
                        Text("\(previewImageCount) photos attached")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    #else
                    HStack(alignment: .top, spacing: 10) {
                        if previewImageURL != nil || model.isRefreshingPreview {
                            previewThumbnail
                        }

                        titleInputField(lineLimit: 3)
                    }

                    if previewImageCount > 1 {
                        Text("\(previewImageCount) photos attached")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    #endif
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $model.excerpt)
                            .frame(minHeight: 72)

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
                    TextField("https://example.com", text: $model.urlString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    #else
                    TextField("https://example.com", text: $model.urlString)
                    #endif
                }
            } header: {
                Text("Send Email")
            } footer: {
                Text(
                    model.autoSendEnabled
                        ? "SendMoi sends immediately when it can. If you're offline or Gmail is unavailable, it saves to the offline queue."
                        : "SendMoi pre-fills these fields from the shared item and waits for you to tap Send. If you're offline or Gmail is unavailable, it saves to the offline queue."
                )
            }

            if shouldShowInlineStatusMessage {
                statusMessageView
            }
        }
        .disabled(model.isSaving || model.isConnectingGmail)
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
        .overlay(alignment: .bottomTrailing) {
            #if os(iOS)
            if previewImageCount > 1 {
                imageCountBadge
            }
            #endif
        }
    }

    private var previewMetadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Summary")
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                if model.isRefreshingPreview && model.summary.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(model.summary)
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
        guard let urlString = model.previewImageURLString else {
            return nil
        }

        return URL(string: urlString)
    }

    private var previewImageCount: Int {
        ([model.previewImageURLString].compactMap { $0 } + model.additionalImageURLStrings).count
    }

    private var imageCountBadge: some View {
        Text("+\(max(previewImageCount - 1, 1))")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.78))
            .clipShape(Capsule())
            .padding(4)
    }

    private var recentRecipientSuggestions: [String] {
        let currentRecipient = model.toEmail
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return model.savedRecipients
            .filter { $0.lowercased() != currentRecipient }
            .prefix(4)
            .map { $0 }
    }

    private var titleIsLoading: Bool {
        model.isRefreshingPreview && model.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var descriptionIsLoading: Bool {
        model.isRefreshingPreview && model.excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowSummarySection: Bool {
        model.isRefreshingPreview || !model.summary.isEmpty
    }

    private func titleInputField(lineLimit: Int) -> some View {
        ZStack(alignment: .topLeading) {
            TextField(titleIsLoading ? "" : "Title", text: $model.title, axis: .vertical)
                .lineLimit(lineLimit, reservesSpace: true)

            if titleIsLoading {
                fieldLoadingIndicator(topPadding: 8)
            }
        }
    }

    private func fieldLoadingIndicator(topPadding: CGFloat) -> some View {
        ProgressView()
            .controlSize(.small)
            .padding(.top, topPadding)
    }

    private var autoSendOverlayCard: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)

            Text(model.statusMessage)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            if model.isSaving {
                Button {
                    model.stopAutoSendAndEdit()
                } label: {
                    Text("Edit")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .background(
                    Capsule()
                        .fill(overlayButtonFill)
                        .overlay {
                            Capsule()
                                .strokeBorder(overlayBorderColor, lineWidth: 1)
                        }
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: 248)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(overlayCardFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(overlayBorderColor, lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        .padding(24)
    }

    private var processingView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(model.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if model.autoSendEnabled && model.isSaving {
                Button {
                    model.stopAutoSendAndEdit()
                } label: {
                    Text("Edit")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(.primary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var statusMessageView: some View {
        Text(model.statusMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shouldShowInlineStatusMessage: Bool {
        let hiddenMessages = [
            "Preparing your email...",
            "Review and tap Send when ready."
        ]

        if showsAutoSendOverlayLayout {
            return false
        }

        if model.statusMessage == model.recipientInlineMessage {
            return false
        }

        return !hiddenMessages.contains(model.statusMessage)
    }

    private var showsAutoSendOverlayLayout: Bool {
        model.presentationMode == .processing &&
        model.autoSendEnabled &&
        model.statusMessage == "Auto-Sending..."
    }

    private var showsSendToolbarItem: Bool {
        model.presentationMode == .editing || showsAutoSendOverlayLayout
    }

    private var sendButtonTitle: String {
        if model.isSaving {
            return "Sending…"
        }

        return "Send"
    }

    private var sendButtonDisabled: Bool {
        model.presentationMode != .editing || model.isSaving
            || model.isConnectingGmail
    }

    private var overlayBorderColor: Color {
        .white.opacity(0.08)
    }

    private var overlayCardFill: Color {
        #if os(iOS)
        return Color(uiColor: .secondarySystemBackground).opacity(0.94)
        #else
        return Color(nsColor: .controlBackgroundColor).opacity(0.96)
        #endif
    }

    private var overlayButtonFill: Color {
        #if os(iOS)
        return Color(uiColor: .tertiarySystemBackground).opacity(0.98)
        #else
        return Color(nsColor: .underPageBackgroundColor).opacity(0.98)
        #endif
    }
}
