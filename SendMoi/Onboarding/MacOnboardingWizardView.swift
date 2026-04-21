import SwiftUI

struct MacOnboardingWizardView: View {
    @EnvironmentObject private var model: AppModel

    @Binding var onboardingStep: Int
    @Binding var onboardingRecipientDraft: String
    @Binding var onboardingRecipientConfirmed: Bool

    let finish: () -> Void
    let skip: () -> Void
    let goBack: () -> Void
    let handlePrimaryAction: () -> Void
    let showAccountSheet: () -> Void
    let saveRecipient: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                contextColumn
                    .frame(maxWidth: 260, maxHeight: .infinity, alignment: .topLeading)

                Divider()

                stepColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            Divider()

            actionBar
        }
        .background(wizardBackground.ignoresSafeArea())
    }

    private var contextColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("SendMoi")
                .font(.title2.weight(.semibold))

            Text(contextTitle)
                .font(.system(size: 28, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)

            Text(contextDetail)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(contextBullets, id: \.self) { bullet in
                    Label(bullet, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Text("Step \(onboardingStep + 1) of 3")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .background(
            LinearGradient(
                colors: [
                    Color.primary.opacity(0.07),
                    Color.primary.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    @ViewBuilder
    private var stepColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                stepHeader

                switch onboardingStep {
                case 0:
                    howItWorksStep
                case 1:
                    connectGmailStep
                default:
                    defaultsStep
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(stepTitle)
                .font(.system(size: 34, weight: .bold))

            Text(stepSubtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var howItWorksStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            wizardCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        wizardNode(iconName: "square.and.arrow.up", title: "Share")
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        wizardNode(iconName: "paperplane.fill", title: "Queue or Send")
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        wizardNode(iconName: "tray.full", title: "Recover")
                    }

                    Text("On macOS, SendMoi is your control center. Share content from another app, let SendMoi send immediately when it can, and use the main window to recover anything that gets stuck.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            wizardCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What the app helps you answer")
                        .font(.headline)

                    Text("Am I connected?")
                    Text("Where will shares go?")
                    Text("What is queued?")
                    Text("What should I do next?")
                }
            }
        }
    }

    private var connectGmailStep: some View {
        wizardCard {
            VStack(alignment: .leading, spacing: 16) {
                if let session = model.session {
                    LabeledContent("Connected Gmail", value: session.emailAddress ?? "Authenticated via Gmail")
                        .font(.body)

                    Text("You can keep this account or switch before finishing setup.")
                        .foregroundStyle(.secondary)

                    Button("Switch Account") {
                        showAccountSheet()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isBusy)
                } else {
                    Text("SendMoi needs Gmail permission to deliver queued items from this Mac.")
                        .foregroundStyle(.secondary)

                    Button("Connect Gmail") {
                        showAccountSheet()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy || !GoogleOAuthConfig.isConfigured)
                }

                if model.requiresGmailReconnect {
                    Text("Reconnect Gmail to restore send permission for queued items.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                if !GoogleOAuthConfig.isConfigured {
                    Text("Set `GoogleOAuthConfig.clientID` before signing in.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var defaultsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            wizardCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Default recipient")
                        .font(.headline)

                    TextField("Email address (optional)", text: $onboardingRecipientDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveRecipient)

                    if showsRecipientSave {
                        Button("Save Recipient") {
                            saveRecipient()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            wizardCard {
                Toggle(isOn: Binding(
                    get: { model.shareSheetAutoSendEnabled },
                    set: { model.setShareSheetAutoSendEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto-send shared items")
                        Text(model.shareSheetAutoSendEnabled ? "Send immediately when enough detail is available." : "Keep the share sheet open for review before sending.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button("Skip") {
                skip()
            }
            .onboardingSecondaryButtonStyle()

            if onboardingStep > 0 {
                Button("Back") {
                    goBack()
                }
                .onboardingSecondaryButtonStyle()
            }

            Spacer(minLength: 0)

            Button(primaryButtonTitle) {
                handlePrimaryAction()
            }
            .onboardingPrimaryButtonStyle(tint: .accentColor)
        }
        .padding(20)
    }

    private var primaryButtonTitle: String {
        switch onboardingStep {
        case 0:
            return "Continue"
        case 1:
            return model.session == nil ? "Connect Gmail" : "Continue"
        default:
            return "Done"
        }
    }

    private var contextTitle: String {
        switch onboardingStep {
        case 0:
            return "Your Mac keeps SendMoi ready."
        case 1:
            return "Connect the Gmail account that sends queued items."
        default:
            return "Choose the defaults SendMoi should use."
        }
    }

    private var contextDetail: String {
        switch onboardingStep {
        case 0:
            return "The share extension starts the flow. The Mac app is where you check trust, recover failures, and see what is waiting."
        case 1:
            return "Google handles sign-in. SendMoi stores the Gmail session so queued items can retry automatically."
        default:
            return "You can save a default recipient now and decide whether shares send immediately or stay open for review."
        }
    }

    private var contextBullets: [String] {
        switch onboardingStep {
        case 0:
            return ["Queue-first control center", "Recover failed sends", "Know account and network health"]
        case 1:
            return ["Secure Google sign-in", "Reconnect when scopes expire", "Queued items stay on disk"]
        default:
            return ["Optional default recipient", "Auto-send can stay off", "These can all be changed later"]
        }
    }

    private var stepTitle: String {
        switch onboardingStep {
        case 0:
            return "How SendMoi works on Mac"
        case 1:
            return "Connect Gmail"
        default:
            return "Set your defaults"
        }
    }

    private var stepSubtitle: String {
        switch onboardingStep {
        case 0:
            return "Share from another app, then use the Mac app to monitor queue health and recover stuck sends."
        case 1:
            return "This account is used for delivery and queue retries."
        default:
            return "Pick a default recipient and share behavior before you start using the app."
        }
    }

    private var showsRecipientSave: Bool {
        let normalizedSavedRecipient = model.defaultRecipient
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedDraft = onboardingRecipientDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return !normalizedDraft.isEmpty
            && (!onboardingRecipientConfirmed || normalizedDraft != normalizedSavedRecipient)
    }

    private var wizardBackground: some View {
        LinearGradient(
            colors: [
                Color.primary.opacity(0.04),
                Color.primary.opacity(0.015)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func wizardCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func wizardNode(iconName: String, title: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accentColor.opacity(0.14))

                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 58, height: 58)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
private struct MacOnboardingWizardPreviewState: View {
    let step: Int
    let recipientDraft: String
    let recipientConfirmed: Bool
    let model: AppModel

    var body: some View {
        MacOnboardingWizardView(
            onboardingStep: .constant(step),
            onboardingRecipientDraft: .constant(recipientDraft),
            onboardingRecipientConfirmed: .constant(recipientConfirmed),
            finish: {},
            skip: {},
            goBack: {},
            handlePrimaryAction: {},
            showAccountSheet: {},
            saveRecipient: {}
        )
        .environmentObject(model)
        .frame(width: 980, height: 700)
    }
}

@MainActor
private struct MacOnboardingWizardView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MacOnboardingWizardPreviewState(
                step: 0,
                recipientDraft: "",
                recipientConfirmed: false,
                model: SendMoiPreviewFixtures.appModel(
                    defaultRecipient: "",
                    shareSheetAutoSendEnabled: true,
                    session: nil,
                    statusMessage: "Configure Google OAuth, sign in, then queue or send shared items.",
                    isOnline: true,
                    shouldShowOnboarding: true
                )
            )
            .previewDisplayName("Step 1")

            MacOnboardingWizardPreviewState(
                step: 1,
                recipientDraft: "",
                recipientConfirmed: false,
                model: SendMoiPreviewFixtures.appModel(
                    defaultRecipient: "",
                    shareSheetAutoSendEnabled: true,
                    session: nil,
                    statusMessage: "Connect Gmail to send queued items from this Mac.",
                    isOnline: true,
                    shouldShowOnboarding: true
                )
            )
            .previewDisplayName("Step 2")

            MacOnboardingWizardPreviewState(
                step: 2,
                recipientDraft: "ideas@sendmoi.app",
                recipientConfirmed: true,
                model: SendMoiPreviewFixtures.appModel(
                    defaultRecipient: "ideas@sendmoi.app",
                    shareSheetAutoSendEnabled: false,
                    session: SendMoiPreviewFixtures.connectedSession,
                    statusMessage: "Signed in as founder@sendmoi.app.",
                    isOnline: true,
                    shouldShowOnboarding: true
                )
            )
            .previewDisplayName("Step 3")
        }
    }
}
#endif
