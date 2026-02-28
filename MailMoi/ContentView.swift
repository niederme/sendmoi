import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                composeSection
                queueSection
                statusSection
            }
            .navigationTitle("MailMoi")
        }
    }

    private var accountSection: some View {
        Section {
            #if os(iOS)
            TextField("Default Recipient", text: $model.defaultRecipient)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
            #else
            TextField("Default Recipient", text: $model.defaultRecipient)
            #endif

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
        } header: {
            Text("Account")
        } footer: {
            Text("Set the default recipient once. The share extension will use it automatically.")
        }
    }

    private var composeSection: some View {
        Section {
            #if os(iOS)
            TextField("To", text: $model.draft.toEmail)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
            #else
            TextField("To", text: $model.draft.toEmail)
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

            TextField("Title", text: $model.draft.title)

            VStack(alignment: .leading, spacing: 8) {
                Text("Excerpt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $model.draft.excerpt)
                    .frame(minHeight: 80)
            }

            #if os(iOS)
            TextField("URL", text: $model.draft.urlString)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
            #else
            TextField("URL", text: $model.draft.urlString)
            #endif

            Button(model.isBusy ? "Working..." : "Queue And Send") {
                Task {
                    await model.queueCurrentDraft()
                }
            }
            .disabled(model.isBusy)
        } header: {
            Text("Compose")
        } footer: {
            Text("The recipient defaults from your saved setting, but you can still change it here when needed.")
        }
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

#Preview {
    ContentView()
        .environmentObject(AppModel())
}
