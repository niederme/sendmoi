import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedField: Field?
    @State private var desktopSelection: DesktopPanel = .overview
    @State private var onboardingStep = 0
    @State private var onboardingRecipientDraft = ""
    @State private var onboardingRecipientConfirmed = false
    @State private var onboardingPulse = false
    @State private var showsResetConfirmation = false
    @State private var showsOnboardingAccountSheet = false

    private enum Field: Hashable {
        case defaultRecipient
    }

    private enum DesktopPanel: String, CaseIterable, Identifiable {
        case overview
        case account
        case preferences
        case compose
        case queue

        var id: Self { self }

        var title: String {
            switch self {
            case .overview:
                return "Overview"
            case .account:
                return "Account"
            case .preferences:
                return "Preferences"
            case .compose:
                return "Compose"
            case .queue:
                return "Queue"
            }
        }

        var subtitle: String {
            switch self {
            case .overview:
                return "App status and activity"
            case .account:
                return "Gmail session"
            case .preferences:
                return "Defaults and share sheet"
            case .compose:
                return "Draft and send"
            case .queue:
                return "Offline deliveries"
            }
        }

        var iconName: String {
            switch self {
            case .overview:
                return "square.grid.2x2"
            case .account:
                return "person.crop.circle"
            case .preferences:
                return "slider.horizontal.3"
            case .compose:
                return "square.and.pencil"
            case .queue:
                return "tray.full"
            }
        }
    }

    var body: some View {
        NavigationStack {
            rootContent
                .navigationTitle("SendMoi")
        }
        .sheet(isPresented: $model.shouldShowOnboarding, onDismiss: finalizeOnboardingSheetState) {
            onboardingContent
            #if os(macOS) || targetEnvironment(macCatalyst)
            .frame(minWidth: 680, minHeight: 720)
            #endif
            .sheet(isPresented: $showsOnboardingAccountSheet) {
                OnboardingGmailSheet {
                    onboardingStep = 2
                    onboardingRecipientDraft = model.defaultRecipient
                    onboardingRecipientConfirmed = false
                }
                    .environmentObject(model)
            }
        }
        .alert(
            "Reset SendMoi?",
            isPresented: $showsResetConfirmation,
            actions: {
            Button("Clear Settings", role: .destructive) {
                clearSettingsAndRestartSetup()
            }
            Button("Cancel", role: .cancel) { }
        },
            message: {
            Text("This disconnects Gmail, clears saved defaults, and reopens setup. Queued items stay in place.")
        })
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

    private var onboardingContent: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    onboardingHero
                    onboardingProgress
                    onboardingStepCard
                    onboardingActions
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .background(onboardingBackground.ignoresSafeArea())
            .task {
                guard !onboardingPulse else {
                    return
                }

                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    onboardingPulse = true
                }
            }
        }
    }

    private var onboardingBackground: some View {
        ZStack {
            LinearGradient(
                colors: onboardingBackgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(onboardingOrbHighlight)
                .frame(width: 220, height: 220)
                .blur(radius: 6)
                .offset(x: 140, y: -220)

            Circle()
                .fill(onboardingOrbAccent)
                .frame(width: 260, height: 260)
                .offset(x: -170, y: 260)
        }
    }

    private var onboardingHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.14, green: 0.44, blue: 0.98),
                                    Color(red: 0.11, green: 0.34, blue: 0.96),
                                    Color(red: 0.58, green: 0.16, blue: 0.97)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    VStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .rotationEffect(.degrees(18))
                            .foregroundStyle(.white)

                        Text("moi")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 74, height: 74)

                VStack(alignment: .leading, spacing: 4) {
                    Text("SendMoi")
                        .font(.system(size: 30, weight: .semibold))

                    Text("Send Anything to Yourself")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var onboardingProgress: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index == onboardingStep ? Color.accentColor : Color.primary.opacity(0.12))
                    .frame(maxWidth: .infinity)
                    .frame(height: 8)
                    .overlay {
                        if index == onboardingStep {
                            Capsule()
                                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                        }
                    }
            }
        }
    }

    private var onboardingStepCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            onboardingStepDetail

            if onboardingStep == 2 && model.session == nil && !GoogleOAuthConfig.isConfigured {
                Text("Google OAuth is not configured yet, so Gmail sign-in is disabled until `GoogleOAuthConfig.clientID` is set.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(onboardingCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(onboardingCardStroke, lineWidth: 1)
        )
    }

    private var onboardingActions: some View {
        HStack(spacing: 12) {
            if onboardingStep == 2 && model.session != nil {
                Button("View Settings") {
                    finishOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .tint(onboardingSecondaryButtonTint)
                .foregroundStyle(.primary)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            } else {
                Button("Skip") {
                    model.completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .tint(onboardingSecondaryButtonTint)
                .foregroundStyle(.primary)
                .controlSize(.large)

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    if onboardingStep > 0 {
                        Button("Back") {
                            onboardingStep -= 1
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(onboardingSecondaryButtonTint)
                        .foregroundStyle(.primary)
                        .controlSize(.large)
                    }

                    Button(onboardingPrimaryButtonTitle) {
                        handleOnboardingPrimaryAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(onboardingStep == 2 && model.session == nil && !GoogleOAuthConfig.isConfigured)
                }
            }
        }
    }

    private var onboardingPrimaryButtonTitle: String {
        if onboardingStep < 2 {
            return "Next"
        }

        return "Connect Gmail"
    }

    @ViewBuilder
    private var onboardingStepDetail: some View {
        switch onboardingStep {
        case 0:
            VStack(alignment: .leading, spacing: 12) {
                Text("Share to SendMoi. It arrives as a polished email to yourself.")
                    .font(.system(size: 24, weight: .semibold))

                onboardingFlowPreview

                onboardingFeatureRow(
                    iconName: "paperplane.circle.fill",
                    title: "Save it with context",
                    detail: "SendMoi keeps the link, title, and any notes together for later."
                )
                onboardingFeatureRow(
                    iconName: "tray.full.fill",
                    title: "If it cannot send, it waits",
                    detail: "When Gmail or the network is unavailable, it stays queued until it can go out."
                )
            }
        case 1:
            VStack(alignment: .leading, spacing: 14) {
                Text("Pin it once, then it is always close.")
                    .font(.system(size: 24, weight: .semibold))

                RoundedRectangle(cornerRadius: 24)
                    .fill(onboardingInsetCardFill)
                    .frame(height: 190)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Share Sheet Order")
                                .font(.headline)

                            VStack(alignment: .leading, spacing: 8) {
                                onboardingInstructionRow(number: 1, text: "Tap Share in any app.")
                                onboardingInstructionRow(number: 2, text: "Open More.")
                                onboardingInstructionRow(number: 3, text: "Drag SendMoi upward.")
                            }
                        }
                        .padding(18)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(onboardingCardStroke, lineWidth: 1)
                    )

                Text("Do this once. It saves a lot of friction.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        default:
            onboardingFinishStep
        }
    }

    @ViewBuilder
    private var onboardingFinishStep: some View {
        if model.session == nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Connect Gmail to finish setup.")
                    .font(.system(size: 24, weight: .semibold))

                onboardingFeatureRow(
                    iconName: "lock.shield.fill",
                    title: "Secure sign-in",
                    detail: "Google handles the login in a system sheet."
                )
                onboardingFeatureRow(
                    iconName: "envelope.badge.fill",
                    title: "Skip if you want",
                    detail: "You can use the app now and connect Gmail later."
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ready to go.")
                    .font(.system(size: 24, weight: .semibold))

                Text("Gmail is connected. Add a default recipient now, or leave it blank and choose in the share sheet each time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Connected Gmail")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.session?.emailAddress ?? "Signed in to Gmail")
                                .font(.body.weight(.medium))

                            Text("You can switch accounts before finishing setup.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Button("Switch Account") {
                            showsOnboardingAccountSheet = true
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(onboardingInsetCardFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(onboardingCardStroke, lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Default recipient")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    #if os(iOS)
                    HStack(alignment: .center, spacing: 10) {
                        TextField("Email address (optional)", text: $onboardingRecipientDraft)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($focusedField, equals: .defaultRecipient)
                            .onSubmit(saveOnboardingRecipient)
                            .frame(maxWidth: .infinity)
                            .layoutPriority(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(onboardingInsetCardFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(onboardingCardStroke, lineWidth: 1)
                            )

                        if onboardingShowsRecipientSave {
                            Button("Save") {
                                saveOnboardingRecipient()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }
                    #else
                    HStack(alignment: .center, spacing: 10) {
                        TextField("Email address (optional)", text: $onboardingRecipientDraft)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveOnboardingRecipient)
                            .frame(maxWidth: .infinity)
                            .layoutPriority(1)

                        if onboardingShowsRecipientSave {
                            Button("Save") {
                                saveOnboardingRecipient()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    #endif
                }

                if onboardingShowsAutoSendToggle {
                    Toggle(isOn: Binding(
                        get: { model.shareSheetAutoSendEnabled },
                        set: { model.setShareSheetAutoSendEnabled($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Auto-send when ready")
                            Text("Or leave this off and review the draft every time.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
            }
        }
    }

    private var onboardingFlowPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 22)
                .fill(onboardingInsetCardFill)
                .frame(height: 108)
                .overlay {
                    HStack(spacing: 14) {
                        onboardingFlowNode(iconName: "square.and.arrow.up", title: "Share")
                        onboardingFlowConnector
                        onboardingFlowNode(iconName: "paperplane.fill", title: "Send")
                    }
                    .padding(.horizontal, 22)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(onboardingCardStroke, lineWidth: 1)
                )
        }
    }

    private func onboardingFeatureRow(iconName: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private func onboardingFlowNode(iconName: String, title: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(onboardingPulse ? 0.22 : 0.12))

                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 38, height: 38)

            Text(title)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }

    private var onboardingFlowConnector: some View {
        Capsule()
            .fill(Color.primary.opacity(0.10))
            .frame(maxWidth: .infinity)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 28, height: 4)
                    .offset(x: onboardingPulse ? 52 : 0)
            }
    }

    private func onboardingInstructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Color.accentColor)
                )

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }

    private var onboardingBackgroundColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.08, green: 0.10, blue: 0.16),
                Color(red: 0.09, green: 0.14, blue: 0.24),
                Color(red: 0.15, green: 0.10, blue: 0.22)
            ]
        }

        return [
            Color(red: 0.96, green: 0.98, blue: 1.0),
            Color(red: 0.92, green: 0.96, blue: 1.0),
            Color(red: 0.95, green: 0.93, blue: 1.0)
        ]
    }

    private var onboardingOrbHighlight: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.85)
    }

    private var onboardingOrbAccent: Color {
        let opacity = colorScheme == .dark ? 0.18 : 0.08
        return Color(red: 0.17, green: 0.43, blue: 0.97).opacity(opacity)
    }

    private var onboardingCardBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.white.opacity(0.78)
    }

    private var onboardingInsetCardFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.white.opacity(0.82)
    }

    private var onboardingCardStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.primary.opacity(0.08)
    }

    private var onboardingSecondaryButtonTint: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.primary.opacity(0.10)
    }

    private var onboardingRecipientDraftNormalized: String {
        onboardingRecipientDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var onboardingHasSavedRecipient: Bool {
        !model.defaultRecipient.isEmpty
    }

    private var onboardingShowsRecipientSave: Bool {
        let normalizedSavedRecipient = model.defaultRecipient.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !onboardingRecipientDraftNormalized.isEmpty
            && (!onboardingRecipientConfirmed || onboardingRecipientDraftNormalized != normalizedSavedRecipient)
    }

    private var onboardingShowsAutoSendToggle: Bool {
        let normalizedSavedRecipient = model.defaultRecipient.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return onboardingHasSavedRecipient
            && onboardingRecipientDraftNormalized == normalizedSavedRecipient
    }

    private func handleOnboardingPrimaryAction() {
        if onboardingStep < 2 {
            onboardingStep += 1
        } else if model.session == nil {
            showsOnboardingAccountSheet = true
        } else {
            finishOnboarding()
        }
    }

    private func openSetupGuide() {
        onboardingStep = 0
        onboardingRecipientDraft = model.defaultRecipient
        onboardingRecipientConfirmed = false
        showsOnboardingAccountSheet = false
        model.shouldShowOnboarding = true
    }

    private func finalizeOnboardingSheetState() {
        onboardingStep = 0
        showsOnboardingAccountSheet = false
        onboardingRecipientConfirmed = false
        model.completeOnboarding()
    }

    private func finishOnboarding() {
        model.completeOnboarding()
    }

    private func clearSettingsAndRestartSetup() {
        onboardingStep = 0
        onboardingRecipientDraft = ""
        onboardingRecipientConfirmed = false
        onboardingPulse = false
        showsOnboardingAccountSheet = false
        model.resetSetup()
    }

    private var compactMobileContent: some View {
        Form {
            accountSection
            defaultRecipientSection
            shareSheetSection
            queueSection
            statusMessageView
            setupActionsSection
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
        if usesDesktopLayout {
        return "Manage Gmail sign-in for the desktop app."
        } else {
        return "Tap to manage Gmail sign-in."
        }
    }

    private var queueFooterText: String {
        model.isOnline ? "Network looks available. The app retries automatically." : "Offline or unreachable. Items remain queued."
    }

    private func saveDefaultRecipient() {
        focusedField = nil
        model.setDefaultRecipient(model.defaultRecipient)
    }

    private func saveOnboardingRecipient() {
        guard onboardingShowsRecipientSave else {
            return
        }

        focusedField = nil
        model.setDefaultRecipient(onboardingRecipientDraft)
        onboardingRecipientDraft = model.defaultRecipient
        onboardingRecipientConfirmed = true
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

    private var desktopContent: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                desktopSidebar
                    .frame(width: min(max(proxy.size.width * 0.24, 230), 280))

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)
                    .padding(.vertical, 22)

                ScrollView {
                    desktopDetailContent
                        .frame(maxWidth: 900)
                        .padding(28)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(
                RoundedRectangle(cornerRadius: 30)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(desktopBackground.ignoresSafeArea())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var desktopSidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SendMoi")
                    .font(.title3.weight(.semibold))

                Text("Desktop workspace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Workspace")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(DesktopPanel.allCases) { panel in
                    desktopSidebarButton(for: panel)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 10) {
                Text("Live Status")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                HStack {
                    Text(model.isOnline ? "Online" : "Offline")
                        .font(.headline)
                        .foregroundStyle(model.isOnline ? Color.green : Color.orange)

                    Spacer()

                    Text("\(model.queuedEmails.count)")
                        .font(.headline.weight(.semibold))
                }

                Text(model.queuedEmails.isEmpty ? "Queue is clear" : "Queued item\(model.queuedEmails.count == 1 ? "" : "s") waiting")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(20)
    }

    private func desktopSidebarButton(for panel: DesktopPanel) -> some View {
        Button {
            desktopSelection = panel
        } label: {
            HStack(spacing: 12) {
                Image(systemName: panel.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 18)
                    .foregroundStyle(desktopSelection == panel ? Color.primary : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(panel.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(panel.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if panel == .queue && !model.queuedEmails.isEmpty {
                    Text("\(model.queuedEmails.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(desktopSelection == panel ? Color.primary.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(desktopSelection == panel ? Color.primary.opacity(0.1) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var desktopDetailContent: some View {
        switch desktopSelection {
        case .overview:
            VStack(alignment: .leading, spacing: 18) {
                desktopHeroCard
                desktopStatsCard
                desktopTopRow
                desktopQueueCard
                desktopStatusCard
                desktopSetupActionsCard
                desktopAttribution
            }
        case .account:
            VStack(alignment: .leading, spacing: 18) {
                desktopSectionIntro(
                    title: "Account",
                    subtitle: "Manage the Gmail account used for queued delivery on this Mac."
                )
                desktopAccountCard
                desktopStatusCard
                desktopSetupActionsCard
            }
        case .preferences:
            VStack(alignment: .leading, spacing: 18) {
                desktopSectionIntro(
                    title: "Preferences",
                    subtitle: "Set the default recipient and decide how shared items behave before they hit the queue."
                )
                desktopPreferencesCard
                desktopStatusCard
                desktopSetupActionsCard
            }
        case .compose:
            VStack(alignment: .leading, spacing: 18) {
                desktopSectionIntro(
                    title: "Compose",
                    subtitle: "Build the draft, enrich it with preview data, and queue it for delivery."
                )
                desktopComposeCard
                desktopStatusCard
                desktopSetupActionsCard
            }
        case .queue:
            VStack(alignment: .leading, spacing: 18) {
                desktopSectionIntro(
                    title: "Offline Queue",
                    subtitle: "Items wait here when Gmail is unavailable and send automatically once the app can reach the network."
                )
                desktopQueueCard
                desktopStatusCard
                desktopSetupActionsCard
            }
        }
    }

    private var desktopHeroCard: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.14, green: 0.44, blue: 0.98),
                                Color(red: 0.11, green: 0.34, blue: 0.96),
                                Color(red: 0.58, green: 0.16, blue: 0.97)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 38, weight: .medium))
                        .rotationEffect(.degrees(18))
                        .foregroundStyle(.white)

                    Text("moi")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 10) {
                Text("SendMoi")
                    .font(.system(size: 34, weight: .semibold))

                Text("A macOS workspace for queueing shared links, refining drafts, and sending as soon as Gmail is available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        desktopSelection = .compose
                    } label: {
                        Text("Compose")
                            .frame(minWidth: 96)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("View Queue") {
                        desktopSelection = .queue
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer(minLength: 16)

            Text(model.isOnline ? "macOS Online" : "macOS Offline")
                .font(.caption.weight(.semibold))
                .foregroundStyle(model.isOnline ? Color.green : Color.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill((model.isOnline ? Color.green : Color.orange).opacity(0.12))
                )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var desktopStatsCard: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                desktopStat(
                    title: "Account",
                    value: model.session == nil ? "Not Signed In" : "Connected",
                    detail: model.session?.emailAddress ?? "Gmail required"
                )
                desktopStatDivider
                desktopStat(
                    title: "Queue",
                    value: "\(model.queuedEmails.count)",
                    detail: model.queuedEmails.isEmpty ? "Nothing waiting" : "Pending item\(model.queuedEmails.count == 1 ? "" : "s")"
                )
                desktopStatDivider
                desktopStat(
                    title: "Auto-Send",
                    value: model.shareSheetAutoSendEnabled ? "On" : "Off",
                    detail: model.shareSheetAutoSendEnabled ? "Share sheet sends" : "Manual review"
                )
                desktopStatDivider
                desktopStat(
                    title: "Recipient",
                    value: model.defaultRecipient.isEmpty ? "Unset" : "Ready",
                    detail: model.defaultRecipient.isEmpty ? "No default saved" : model.defaultRecipient
                )
            }

            VStack(alignment: .leading, spacing: 14) {
                desktopStat(
                    title: "Account",
                    value: model.session == nil ? "Not Signed In" : "Connected",
                    detail: model.session?.emailAddress ?? "Gmail required"
                )
                desktopStat(
                    title: "Queue",
                    value: "\(model.queuedEmails.count)",
                    detail: model.queuedEmails.isEmpty ? "Nothing waiting" : "Pending item\(model.queuedEmails.count == 1 ? "" : "s")"
                )
                desktopStat(
                    title: "Auto-Send",
                    value: model.shareSheetAutoSendEnabled ? "On" : "Off",
                    detail: model.shareSheetAutoSendEnabled ? "Share sheet sends" : "Manual review"
                )
                desktopStat(
                    title: "Recipient",
                    value: model.defaultRecipient.isEmpty ? "Unset" : "Ready",
                    detail: model.defaultRecipient.isEmpty ? "No default saved" : model.defaultRecipient
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var desktopStatDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1)
            .padding(.vertical, 8)
    }

    private func desktopStat(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(.title3.weight(.semibold))

            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func desktopSectionIntro(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 30, weight: .semibold))

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var desktopHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SendMoi")
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
        desktopSectionCard(
            title: "Compose",
            subtitle: "Drafting and editing now happen in the share sheet."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("SendMoi now treats the main app as a control center for account, defaults, and queue recovery. To create a new draft, share a link, note, or image from another app into SendMoi.")
                    .font(.body)

                VStack(alignment: .leading, spacing: 10) {
                    desktopFieldLabel("Current Delivery Defaults")

                    desktopReadout(
                        label: "Default Recipient",
                        value: model.defaultRecipient.isEmpty ? "Not set" : model.defaultRecipient
                    )

                    desktopReadout(
                        label: "Share Sheet",
                        value: model.shareSheetAutoSendEnabled ? "Auto-send enabled" : "Manual review before send"
                    )

                    desktopReadout(
                        label: "Gmail Session",
                        value: model.session?.emailAddress ?? "No Gmail account connected"
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    desktopFieldLabel("How To Compose")

                    Text("1. Share content into SendMoi from Safari, Photos, or another app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("2. Edit the draft in the share sheet if Auto-send is off.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("3. If sending cannot finish immediately, SendMoi keeps the item in the offline queue and retries later.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Use the queue panel to monitor items that still need delivery.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("View Queue") {
                        desktopSelection = .queue
                    }
                    .buttonStyle(.borderedProminent)
                }
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

private struct OnboardingGmailSheet: View {
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
                } else if phase == .failure {
                    Button("Try Again") {
                        beginSignIn()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Button(phase == .success ? "Done" : "Close") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(phase == .connecting)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(sheetBackground.ignoresSafeArea())
            #if os(macOS) || targetEnvironment(macCatalyst)
            .frame(minWidth: 520, minHeight: 420)
            #endif
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

private struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppModel())
    }
}
