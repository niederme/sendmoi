import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedField: Field?
    @State private var showsResetConfirmation = false

    private enum Field: Hashable {
        case defaultRecipient
    }

    var body: some View {
        NavigationStack {
            rootContent
                .navigationTitle("SendMoi")
        }
        .sheet(isPresented: $model.shouldShowOnboarding, onDismiss: finalizeOnboardingSheetState) {
            OnboardingFlowView(
                isDesktopLayout: usesDesktopLayout,
                finish: {
                    model.completeOnboarding()
                }
            )
            .environmentObject(model)
            #if os(macOS) || targetEnvironment(macCatalyst)
            .frame(minWidth: 680, minHeight: 720)
            #endif
        }
        .confirmationDialog(
            "Reset SendMoi?",
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Settings", role: .destructive) {
                clearSettingsAndRestartSetup()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This disconnects Gmail, clears saved defaults, and reopens setup. Queued items stay in place.")
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if usesDesktopLayout {
            MacControlCenterView(
                openSetupGuide: openSetupGuide,
                showResetConfirmation: {
                    showsResetConfirmation = true
                }
            )
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

    private func openSetupGuide() {
        model.shouldShowOnboarding = true
    }

    private func finalizeOnboardingSheetState() {
        model.completeOnboarding()
    }

    private func clearSettingsAndRestartSetup() {
        model.resetSetup()
    }

    private var compactMobileContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Send links to your Gmail inbox without losing them in tabs, bookmarks, or chats.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(1.2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

            Form {
                accountSection
                defaultRecipientSection
                shareSheetSection
                queueSection
                setupActionsSection
                attributionSection
            }
            .sendMoiListSectionSpacing(24)
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

                    if model.requiresGmailReconnect {
                        Text("The saved Gmail session is missing send permission.")
                            .font(.footnote)
                            .foregroundStyle(.orange)

                        Button("Reconnect Gmail") {
                            Task {
                                await model.signIn()
                            }
                        }
                        .disabled(model.isBusy || !GoogleOAuthConfig.isConfigured)
                    }

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

    private var shareSheetFooterText: String {
        if model.shareSheetAutoSendEnabled {
            return "Items shared from other apps send automatically when enough details are available."
        }

        return "Items shared from other apps stay open so you can review the draft before sending."
    }

    private var accountSectionFooterText: String {
        if model.requiresGmailReconnect {
            return "Reconnect Gmail to restore send permission for queued items."
        }

        if usesDesktopLayout {
        return "Manage Gmail sign-in for the desktop app."
        } else {
        return "Tap to manage Gmail sign-in."
        }
    }

    private var queueFooterText: String {
        if model.requiresGmailReconnect {
            return "Reconnect Gmail to restore send permission, then retry the queue."
        }

        return model.isOnline
            ? "Network looks available. The app retries automatically."
            : "Offline or unreachable. Items remain queued."
    }

    private var queueSummaryTitle: String {
        let count = model.queuedEmails.count

        if count == 0 {
            return "No pending emails"
        }

        return "\(count) pending email\(count == 1 ? "" : "s")"
    }

    private var queueSummaryDetail: String {
        if model.isBusy && !model.queuedEmails.isEmpty {
            return "Retry in progress"
        }

        if model.queuedEmails.isEmpty {
            return "Queue is clear"
        }

        if model.requiresGmailReconnect {
            return "Reconnect Gmail to resume sending"
        }

        return "Tap to review and send now"
    }

    private func saveDefaultRecipient() {
        focusedField = nil
        model.setDefaultRecipient(model.defaultRecipient)
    }

    private var queueSection: some View {
        Section {
            DisclosureGroup(isExpanded: $model.isQueueSectionExpanded) {
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

                if model.requiresGmailReconnect {
                    Button {
                        Task {
                            await model.signIn()
                        }
                    } label: {
                        Text("Reconnect Gmail")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.isBusy || !GoogleOAuthConfig.isConfigured)
                }

                Button {
                    Task {
                        await model.retryNow()
                    }
                } label: {
                    Text("Send Queued Now")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isBusy || model.queuedEmails.isEmpty || model.requiresGmailReconnect)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(queueSummaryTitle)
                    Text(queueSummaryDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Offline Queue")
        } footer: {
            Text(queueFooterText)
        }
    }

    private var setupActionsSection: some View {
        Section {
            Button("Open Setup Guide") {
                openSetupGuide()
            }
            .disabled(model.isBusy)

            Button("Clear Settings", role: .destructive) {
                showsResetConfirmation = true
            }
            .disabled(model.isBusy)
        } header: {
            Text("Setup")
        } footer: {
            Text("Open Setup Guide keeps your current account. Clear Settings disconnects Gmail and resets SendMoi to first launch.")
        }
    }

    private var attributionSection: some View {
        Section {
            EmptyView()
        } footer: {
            Text("SendMoi by John Niedermeyer, with a little help from Codex, Claude Code and friends.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}

extension View {
    @ViewBuilder
    func sendMoiPageTabViewStyle() -> some View {
        #if os(iOS) || targetEnvironment(macCatalyst)
        self.tabViewStyle(.page(indexDisplayMode: .never))
        #else
        self
        #endif
    }

    @ViewBuilder
    func sendMoiListSectionSpacing(_ spacing: CGFloat) -> some View {
        #if os(iOS) || targetEnvironment(macCatalyst)
        self.listSectionSpacing(spacing)
        #else
        self
        #endif
    }
}

extension ContentView {
    private var wideIOSContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                desktopTopRow
                desktopQueueCard
                desktopStatusCard
                desktopSetupActionsCard
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

                    if model.requiresGmailReconnect {
                        Text("The saved Gmail session is missing send permission.")
                            .font(.footnote)
                            .foregroundStyle(.orange)

                        HStack {
                            Button("Reconnect Gmail") {
                                Task {
                                    await model.signIn()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isBusy || !GoogleOAuthConfig.isConfigured)

                            Spacer()
                        }
                    }

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
                    .disabled(model.isBusy || model.queuedEmails.isEmpty || model.requiresGmailReconnect)
                }

                if model.requiresGmailReconnect {
                    HStack {
                        Text("Reconnect Gmail, then retry the queue.")
                            .font(.footnote)
                            .foregroundStyle(.orange)

                        Spacer()

                        Button("Reconnect Gmail") {
                            Task {
                                await model.signIn()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy || !GoogleOAuthConfig.isConfigured)
                    }
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

    private var desktopSetupActionsCard: some View {
        desktopSectionCard(title: "Setup") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Reopen the guide or reset SendMoi to first launch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Button("Open Setup Guide") {
                            openSetupGuide()
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isBusy)

                        Button("Clear Settings", role: .destructive) {
                            showsResetConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isBusy)

                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Button("Open Setup Guide") {
                            openSetupGuide()
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isBusy)

                        Button("Clear Settings", role: .destructive) {
                            showsResetConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isBusy)
                    }
                }
            }
        }
    }

    private var desktopAttribution: some View {
        Text("SendMoi by John Niedermeyer, with a little help from Codex, Claude Code and friends.")
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

struct OnboardingGmailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var model: AppModel
    let onSuccess: () -> Void
    @State private var phase: Phase = .connecting
    @State private var errorMessage: String?

    private enum Phase {
        case connecting
        case success
        case failure
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                sheetHero

                VStack(alignment: .leading, spacing: 12) {
                    Text(sheetTitle)
                        .font(.title2.weight(.semibold))

                    Text(sheetDescription)
                        .foregroundStyle(.secondary)
                }

                if phase == .connecting {
                    ProgressView()
                        .controlSize(.large)
                }

                if let errorMessage, phase == .failure {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                Spacer(minLength: 0)

                if phase == .success {
                    Button("Continue") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                } else if phase == .failure {
                    Button("Try Again") {
                        beginSignIn()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(sheetBackground.ignoresSafeArea())
            #if os(macOS) || targetEnvironment(macCatalyst)
            .frame(minWidth: 520, minHeight: 420)
            #endif
            .presentationDetents([.medium])
            .task {
                guard phase == .connecting else {
                    return
                }

                beginSignIn()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .disabled(phase == .connecting)
                }
            }
        }
    }

    private var sheetHero: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(phase == .success ? 0.2 : 0.14))

                Image(systemName: phase == .success ? "checkmark.circle.fill" : "person.crop.circle.badge.checkmark")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(phase == .success ? Color.green : Color.accentColor)
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text("SendMoi")
                    .font(.headline)

                Text(phase == .success ? "Gmail connected" : "Secure Google sign-in")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sheetTitle: String {
        switch phase {
        case .connecting:
            return "Opening Google"
        case .success:
            return "You are ready"
        case .failure:
            return "Google sign-in did not finish"
        }
    }

    private var sheetDescription: String {
        switch phase {
        case .connecting:
            return "Finish the Google sign-in flow in the system sheet. SendMoi will bring you right back."
        case .success:
            return model.session?.emailAddress.map { "Connected as \($0). The onboarding flow is complete, and the app is ready." }
                ?? "Your Gmail account is connected and the onboarding flow is complete."
        case .failure:
            return "You can try again now, or close this and keep using the app."
        }
    }

    private var sheetBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.08, green: 0.10, blue: 0.16),
                    Color(red: 0.10, green: 0.13, blue: 0.22)
                ]
                : [
                    Color(red: 0.98, green: 0.99, blue: 1.0),
                    Color(red: 0.95, green: 0.97, blue: 1.0)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func beginSignIn() {
        guard phase != .success else {
            return
        }

        errorMessage = nil
        phase = .connecting

        Task {
            let didSignIn = await model.signIn()

            if didSignIn {
                phase = .success
                onSuccess()
                try? await Task.sleep(for: .milliseconds(900))
                if !Task.isCancelled {
                    dismiss()
                }
            } else {
                phase = .failure
                errorMessage = model.statusMessage
            }
        }
    }
}

extension View {
    @ViewBuilder
    func onboardingPrimaryButtonStyle(tint: Color) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .buttonStyle(.glassProminent)
                .tint(tint)
        } else {
            self
                .buttonStyle(.borderedProminent)
                .tint(tint)
        }
    }

    @ViewBuilder
    func onboardingSecondaryButtonStyle() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

private struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppModel())
    }
}

@MainActor
private final class LoopingVideoPlayerModel: ObservableObject {
    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?

    init(resource: String, ext: String) {
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        queuePlayer.actionAtItemEnd = .none
        self.player = queuePlayer

        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            return
        }

        let item = Self.makeVideoOnlyItem(url: url)
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    private static func makeVideoOnlyItem(url: URL) -> AVPlayerItem {
        let sourceAsset = AVURLAsset(url: url)
        let composition = AVMutableComposition()
        guard
            let sourceVideoTrack = sourceAsset.tracks(withMediaType: .video).first,
            let videoOnlyCompositionTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            return AVPlayerItem(url: url)
        }

        do {
            let timeRange = CMTimeRange(start: .zero, duration: sourceAsset.duration)
            try videoOnlyCompositionTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)
            videoOnlyCompositionTrack.preferredTransform = sourceVideoTrack.preferredTransform
            return AVPlayerItem(asset: composition)
        } catch {
            return AVPlayerItem(url: url)
        }
    }
}

struct LoopingVideoPlayerView: View {
    @StateObject private var model: LoopingVideoPlayerModel

    init(resourceName: String, resourceExtension: String) {
        _model = StateObject(
            wrappedValue: LoopingVideoPlayerModel(resource: resourceName, ext: resourceExtension)
        )
    }

    var body: some View {
        LoopingVideoPlayerNativeView(player: model.player)
            .clipped()
            .allowsHitTesting(false)
            .onAppear {
                model.play()
            }
            .onDisappear {
                model.pause()
            }
    }
}

#if canImport(UIKit)
private final class LoopingVideoPlayerContainerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

private struct LoopingVideoPlayerNativeView: UIViewRepresentable {
    let player: AVQueuePlayer

    func makeUIView(context: Context) -> LoopingVideoPlayerContainerView {
        let view = LoopingVideoPlayerContainerView()
        view.backgroundColor = .black
        view.clipsToBounds = true
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: LoopingVideoPlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }

    static func dismantleUIView(_ uiView: LoopingVideoPlayerContainerView, coordinator: ()) {
        uiView.playerLayer.player = nil
    }
}
#else
private struct LoopingVideoPlayerNativeView: View {
    let player: AVQueuePlayer

    var body: some View {
        Color.black
    }
}
#endif
