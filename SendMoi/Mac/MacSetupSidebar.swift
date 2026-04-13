import SwiftUI
#if os(macOS)
import AppKit
#endif

struct MacSetupSidebar: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focusedField: Field?

    let openSetupGuide: () -> Void
    let showResetConfirmation: () -> Void

    private enum Field: Hashable {
        case defaultRecipient
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            gmailCard
            recipientCard
            shareBehaviorCard
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
            subtitle: "Used as the default when starting from the share sheet."
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
