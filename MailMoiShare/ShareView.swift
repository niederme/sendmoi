import SwiftUI

struct ShareView: View {
    @ObservedObject var model: ShareExtensionModel

    var body: some View {
        NavigationStack {
            Group {
                if model.presentationMode == .editing {
                    editorView
                } else {
                    processingView
                }
            }
            .navigationTitle("MailMoi")
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

                if model.presentationMode == .editing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(model.isSaving ? "Sending..." : "Send") {
                            model.queueAndComplete()
                        }
                        .disabled(model.isSaving)
                        #if os(macOS)
                        .keyboardShortcut(.defaultAction)
                        #endif
                    }
                }
            }
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
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                    #else
                    TextField("Email address", text: $model.toEmail)
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
                        if previewImageURL != nil || model.isRefreshingPreview {
                            previewThumbnail
                        }

                        ZStack(alignment: .topLeading) {
                            TextField(titleIsLoading ? "" : "Page title", text: $model.title, axis: .vertical)
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
                    Text("URL")
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
                        ? "MailMoi sends immediately when it can. If you're offline or Gmail is unavailable, it saves to the offline queue."
                        : "MailMoi pre-fills these fields from the page and waits for you to tap Send. If you're offline or Gmail is unavailable, it saves to the offline queue."
                )
            }

            if shouldShowInlineStatusMessage {
                statusMessageView
            }
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

    private func fieldLoadingIndicator(topPadding: CGFloat) -> some View {
        ProgressView()
            .controlSize(.small)
            .padding(.top, topPadding)
    }

    private var processingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(model.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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

        return !hiddenMessages.contains(model.statusMessage)
    }
}
