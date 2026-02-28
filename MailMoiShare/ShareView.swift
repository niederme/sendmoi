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
                #if os(iOS)
                TextField("To", text: $model.toEmail)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                #else
                TextField("To", text: $model.toEmail)
                #endif

                if !model.savedRecipients.isEmpty {
                    Menu("Use Recent Recipient") {
                        ForEach(model.savedRecipients, id: \.self) { recipient in
                            Button(recipient) {
                                model.useSavedRecipient(recipient)
                            }
                        }
                    }
                }

                TextField("Title", text: $model.title)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Excerpt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $model.excerpt)
                        .frame(minHeight: 100)
                }

                #if os(iOS)
                TextField("URL", text: $model.urlString)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                #else
                TextField("URL", text: $model.urlString)
                #endif
            } header: {
                Text("Send Email")
            } footer: {
                Text("MailMoi sends immediately when it can. If you're offline or Gmail is unavailable, it saves to the offline queue.")
            }

            statusSection
        }
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

    private var statusSection: some View {
        Section {
            Text(model.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Status")
        }
    }
}
