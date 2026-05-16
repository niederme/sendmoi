import SwiftUI
#if os(macOS)
import AppKit
#endif

struct MacSetupSidebar: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focusedField: Field?
    @State private var recipientPresetDraft = ""

    let openSetupGuide: () -> Void
    let showResetConfirmation: () -> Void

    private enum Field: Hashable {
        case defaultRecipient
        case recipientPreset
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            gmailCard
            recipientCard
            shareBehaviorCard
            goodLinksCard
            analyticsCard
            setupCard
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task {
            clearInitialRecipientFocus()
        }
    }

    private var gmailCard: some View {
        MacSidebarCard(
            title: "Gmail",
            subtitle: model.requiresGmailReconnect
                ? "Reconnect Gmail to restore send permission for queued items."
                : (model.session == nil
                    ? "Connect Gmail so SendMoi can send queued items from this Mac."
                    : "Use the connected account for queued delivery on this Mac.")
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: gmailIcon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(gmailIconTint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.session?.emailAddress ?? "No Gmail account connected")
                            .font(.headline)

                        Text(gmailStatusDetail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                if model.session != nil {
                    if model.requiresGmailReconnect {
                        Button("Reconnect Gmail") {
                            Task { await model.signIn() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy || !GoogleOAuthConfig.isConfigured)
                    }

                    Button("Sign Out", role: .destructive) {
                        model.signOut()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isBusy)
                } else {
                    Button("Sign In With Google") {
                        Task { await model.signIn() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy || !GoogleOAuthConfig.isConfigured)
                }

                if !GoogleOAuthConfig.isConfigured {
                    Text("Set `GoogleOAuthConfig.clientID` before signing in.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var recipientCard: some View {
        MacSidebarCard(
            title: "Default Recipient",
            subtitle: "Auto-send uses the default. Additional recipients appear as quick picks when editing."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Email address", text: $model.defaultRecipient)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .defaultRecipient)
                    .onSubmit(saveDefaultRecipient)

                Button("Save Default Recipient") {
                    saveDefaultRecipient()
                }
                .buttonStyle(.bordered)
                .disabled(model.isBusy)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Additional Recipients")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    if !additionalRecipientPresets.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(additionalRecipientPresets, id: \.self) { recipient in
                                    Button {
                                        removeRecipientPreset(recipient)
                                    } label: {
                                        HStack(spacing: 5) {
                                            Text(recipient)
                                                .lineLimit(1)
                                            Image(systemName: "xmark")
                                                .font(.caption.weight(.bold))
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("Email address", text: $recipientPresetDraft)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .recipientPreset)
                            .onSubmit(addRecipientPreset)

                        Button("Add") {
                            addRecipientPreset()
                        }
                        .buttonStyle(.bordered)
                        .disabled(recipientPresetDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private var shareBehaviorCard: some View {
        MacSidebarCard(
            title: "Share Behavior",
            subtitle: model.shareSheetAutoSendEnabled
                ? "Items shared from other apps send automatically when enough details are available."
                : "Items shared from other apps stay open so you can review the draft before sending."
        ) {
            Toggle(isOn: Binding(
                get: { model.shareSheetAutoSendEnabled },
                set: { model.setShareSheetAutoSendEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-send shared items")
                    Text(model.shareSheetAutoSendEnabled ? "Automatic send is on." : "Manual review stays on.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    private var goodLinksCard: some View {
        MacSidebarCard(
            title: "GoodLinks",
            subtitle: goodLinksSubtitle
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: goodLinksBinding(\.isEnabled)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Also save to GoodLinks")
                        Text("Uses the local GoodLinks API for shares started on this Mac.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                goodLinksSetupState

                TextField("API address", text: goodLinksBinding(\.apiAddress))
                    .textFieldStyle(.roundedBorder)

                SecureField("API token", text: goodLinksBinding(\.apiToken))
                    .textFieldStyle(.roundedBorder)

                goodLinksSetupGuide

                GoodLinksTagsEditor(
                    tagsText: goodLinksBinding(\.tagsText),
                    isEnabled: true
                )

                Toggle("Star saved links", isOn: goodLinksBinding(\.starred))

                Toggle("Mark saved links as read", isOn: goodLinksBinding(\.read))

                Button(goodLinksTestButtonTitle) {
                    Task { await model.testGoodLinksConnection() }
                }
                .buttonStyle(.bordered)
                .disabled(
                    model.isBusy ||
                    model.isTestingGoodLinks ||
                    model.goodLinksSettings.apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
    }

    private var analyticsCard: some View {
        MacSidebarCard(
            title: "Analytics",
            subtitle: model.analyticsEnabled
                ? "Sending anonymous usage signals to help improve SendMoi."
                : "Off by default. Share a few anonymous signals to help improve SendMoi."
        ) {
            Toggle(isOn: Binding(
                get: { model.analyticsEnabled },
                set: { model.setAnalyticsEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share anonymous usage analytics")
                    Text("Installs, active use, and setup completion only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    private var setupCard: some View {
        MacSidebarCard(
            title: "Setup",
            subtitle: "Reopen the guide or reset SendMoi to first launch."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Button("Open Setup Guide") {
                    openSetupGuide()
                }
                .buttonStyle(.bordered)
                .disabled(model.isBusy)

                Button("Clear Settings", role: .destructive) {
                    showResetConfirmation()
                }
                .buttonStyle(.bordered)
                .disabled(model.isBusy)
            }
        }
    }

    private func saveDefaultRecipient() {
        focusedField = nil
        model.setDefaultRecipient(model.defaultRecipient)
    }

    private var additionalRecipientPresets: [String] {
        let normalizedDefault = model.defaultRecipient.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return model.savedRecipients.filter { recipient in
            recipient.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != normalizedDefault
        }
    }

    private func addRecipientPreset() {
        let recipient = recipientPresetDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recipient.isEmpty else {
            return
        }

        model.addSavedRecipient(recipient)
        recipientPresetDraft = ""
        focusedField = nil
    }

    private func removeRecipientPreset(_ recipient: String) {
        model.removeSavedRecipient(recipient)
    }

    private func goodLinksBinding<Value>(_ keyPath: WritableKeyPath<GoodLinksSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.goodLinksSettings[keyPath: keyPath] },
            set: { value in
                var settings = model.goodLinksSettings
                settings[keyPath: keyPath] = value
                model.setGoodLinksSettings(settings)
            }
        )
    }

    private func clearInitialRecipientFocus() {
        focusedField = nil
        #if os(macOS)
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
            NSApp.mainWindow?.makeFirstResponder(nil)
        }
        #endif
    }

    private var gmailStatusDetail: String {
        if model.requiresGmailReconnect {
            return "Reconnect Gmail to resume queued delivery."
        }
        if model.session == nil {
            return "SendMoi needs Gmail to send queued items."
        }
        return "Ready for queued delivery on this Mac."
    }

    private var goodLinksSubtitle: String {
        if !model.syncedGoodLinksJobs.isEmpty {
            return "Paste the local API token so this Mac can save iPhone GoodLinks items."
        }

        if model.goodLinksSettings.isEnabled {
            return "Save a bonus copy to GoodLinks after Gmail sends."
        }

        return "Optional. Gmail remains the required delivery path."
    }

    private var goodLinksSetupState: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(goodLinksSetupStateTitle)
                    .font(.footnote.weight(.semibold))
                Text(goodLinksSetupStateDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: goodLinksSetupStateIcon)
                .foregroundStyle(goodLinksSetupStateTint)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(goodLinksSetupStateTint.opacity(0.10))
        )
    }

    private var goodLinksSetupGuide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GoodLinks setup")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            goodLinksSetupStep("1", "In GoodLinks for Mac, open Settings > API and turn on API Server.")
            goodLinksSetupStep("2", "Paste the Address and API Token from GoodLinks into SendMoi.")
            goodLinksSetupStep("3", "Test the connection. Pending iPhone items retry after a successful test.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func goodLinksSetupStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var goodLinksTestButtonTitle: String {
        if model.isTestingGoodLinks {
            return "Testing..."
        }

        if !model.syncedGoodLinksJobs.isEmpty {
            return "Test & Retry Queue"
        }

        return "Test Connection"
    }

    private var goodLinksSetupStateTitle: String {
        if model.goodLinksConnectionSucceeded {
            return "GoodLinks is ready"
        }

        if model.goodLinksConnectionMessage != nil {
            return "GoodLinks needs attention"
        }

        if goodLinksAddressIsMissing {
            return "Add the API address"
        }

        if goodLinksTokenIsMissing {
            return "Paste the API token"
        }

        if !model.syncedGoodLinksJobs.isEmpty {
            return "Pending iPhone saves are waiting"
        }

        if model.goodLinksSettings.isEnabled {
            return "Ready to test"
        }

        return "Configured for later"
    }

    private var goodLinksSetupStateDetail: String {
        if let message = model.goodLinksConnectionMessage {
            return message
        }

        if goodLinksAddressIsMissing {
            return "Use the local address shown in GoodLinks Settings > API, usually http://localhost:9428."
        }

        if goodLinksTokenIsMissing {
            return "SendMoi cannot save to GoodLinks until this Mac has the token from GoodLinks Settings > API."
        }

        if !model.syncedGoodLinksJobs.isEmpty {
            return "The Mac will use this API token even if Mac-origin GoodLinks copies are off."
        }

        if model.goodLinksSettings.isEnabled {
            return "Test the local API before relying on GoodLinks copies."
        }

        return "The token stays saved for iPhone queue processing and future Mac saves."
    }

    private var goodLinksSetupStateIcon: String {
        if model.goodLinksConnectionSucceeded {
            return "checkmark.circle.fill"
        }

        if model.goodLinksConnectionMessage != nil || goodLinksAddressIsMissing || goodLinksTokenIsMissing {
            return "exclamationmark.triangle.fill"
        }

        if !model.syncedGoodLinksJobs.isEmpty {
            return "arrow.triangle.2.circlepath.circle.fill"
        }

        return "info.circle.fill"
    }

    private var goodLinksSetupStateTint: Color {
        if model.goodLinksConnectionSucceeded {
            return .green
        }

        if model.goodLinksConnectionMessage != nil || goodLinksAddressIsMissing || goodLinksTokenIsMissing {
            return .orange
        }

        return .accentColor
    }

    private var goodLinksAddressIsMissing: Bool {
        model.goodLinksSettings.apiAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var goodLinksTokenIsMissing: Bool {
        model.goodLinksSettings.apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var gmailIcon: String {
        if model.requiresGmailReconnect {
            return "exclamationmark.triangle.fill"
        }
        return model.session == nil ? "person.crop.circle.badge.xmark" : "checkmark.shield.fill"
    }

    private var gmailIconTint: Color {
        if model.requiresGmailReconnect || model.session == nil {
            return .orange
        }
        return .accentColor
    }
}

struct MacSidebarCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            content
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
}

#if DEBUG
@MainActor
private struct MacSetupSidebar_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MacSetupSidebar(
                openSetupGuide: {},
                showResetConfirmation: {}
            )
            .environmentObject(
                SendMoiPreviewFixtures.appModel(
                    queuedEmails: SendMoiPreviewFixtures.queuedItems,
                    defaultRecipient: "ideas@sendmoi.app",
                    shareSheetAutoSendEnabled: true,
                    session: SendMoiPreviewFixtures.connectedSession,
                    statusMessage: "Signed in as founder@sendmoi.app.",
                    isOnline: true
                )
            )
            .frame(width: 620, height: 560)
            .padding(20)
            .previewDisplayName("Connected Setup")

            MacSetupSidebar(
                openSetupGuide: {},
                showResetConfirmation: {}
            )
            .environmentObject(
                SendMoiPreviewFixtures.appModel(
                    defaultRecipient: "",
                    shareSheetAutoSendEnabled: false,
                    session: nil,
                    statusMessage: "Configure Google OAuth, sign in, then queue or send shared items.",
                    isOnline: false
                )
            )
            .frame(width: 620, height: 560)
            .padding(20)
            .previewDisplayName("Needs Setup")
        }
    }
}
#endif
