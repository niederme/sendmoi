import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedField: Field?
    @State private var desktopSelection: DesktopPanel = .overview
    @State private var onboardingStep = 0
    @State private var onboardingRecipientDraft = ""
    @State private var onboardingRecipientConfirmed = false
    @State private var onboardingPulse = false
    @State private var onboardingPinSlide = 0
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
            ZStack(alignment: .bottom) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: onboardingMainSpacing) {
                        onboardingStepCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, onboardingVerticalPadding)
                    .padding(.bottom, onboardingPinnedActionsInset)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }

                onboardingPinnedActions
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

            RadialGradient(
                colors: [onboardingAuroraHighlight, .clear],
                center: .topTrailing,
                startRadius: 24,
                endRadius: 320
            )
            .offset(x: -34, y: -190)

            LinearGradient(
                colors: [onboardingAuroraAccent, .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: 420, height: 320)
            .blur(radius: 52)
            .rotationEffect(.degrees(-16))
            .offset(x: -168, y: 286)
        }
    }

    private var onboardingStepCard: some View {
        Group {
            if onboardingStep == 0 {
                onboardingStepDetail
                    .padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    onboardingStepDetail

                    if onboardingStep == 2 && model.session == nil && !GoogleOAuthConfig.isConfigured {
                        Text("Google OAuth is not configured yet, so Gmail sign-in is disabled until `GoogleOAuthConfig.clientID` is set.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(onboardingStepCardPadding)
                .background(
                    RoundedRectangle(cornerRadius: onboardingStepCardCornerRadius)
                        .fill(onboardingCardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: onboardingStepCardCornerRadius)
                        .stroke(onboardingCardStroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.09), radius: 18, y: 10)
            }
        }
    }

    private var onboardingActions: some View {
        HStack(spacing: 12) {
            if onboardingStep == 2 && model.session != nil {
                Button("Back") {
                    onboardingStep -= 1
                }
                .onboardingSecondaryButtonStyle()
                .buttonBorderShape(.capsule)
                .controlSize(.large)

                Spacer(minLength: 0)

                Button("Done") {
                    finishOnboarding()
                }
                .onboardingPrimaryButtonStyle(tint: onboardingBrandAccent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            } else {
                Button("Skip") {
                    model.completeOnboarding()
                }
                .onboardingSecondaryButtonStyle()
                .buttonBorderShape(.capsule)
                .controlSize(.large)

                Spacer(minLength: 10)

                onboardingInlinePagination

                Spacer(minLength: 10)

                HStack(spacing: 12) {
                    if onboardingStep > 0 {
                        Button {
                            onboardingStep -= 1
                        }
                        label: {
                            Image(systemName: "chevron.left")
                        }
                        .onboardingSecondaryButtonStyle()
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .frame(width: 46, height: 46)
                    }

                    if onboardingStep < 2 {
                        Button {
                            handleOnboardingPrimaryAction()
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .onboardingPrimaryButtonStyle(tint: onboardingBrandAccent)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .frame(width: 46, height: 46)
                    } else if onboardingStep == 2 && model.session == nil {
                        Button {
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .onboardingSecondaryButtonStyle()
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .frame(width: 46, height: 46)
                        .disabled(true)
                        .accessibilityLabel("Next unavailable")
                        .accessibilityHint("Connect Gmail with the button above, or tap Skip.")
                    }
                }
            }
        }
    }

    private var onboardingInlinePagination: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index == onboardingStep ? onboardingInlinePaginationActive : onboardingInlinePaginationInactive)
                    .frame(width: index == onboardingStep ? 14 : 6, height: 4)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: onboardingStep)
    }

    @ViewBuilder
    private var onboardingStepDetail: some View {
        switch onboardingStep {
        case 0:
            VStack(alignment: .leading, spacing: 0) {
                onboardingFlowPreview
                    .padding(.top, onboardingFirstStepTopSpacing)
                    .padding(.bottom, onboardingFirstStepMediaToCopySpacing)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Send anything to your\nGmail inbox, with just two taps.")
                        .font(.system(size: onboardingFirstStepHeadlineFontSize, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)

                    Text("SendMoi makes it easy to send links to your Gmail inbox without losing them in tabs, bookmarks, or chats.")
                        .font(.system(size: onboardingFirstStepSubheadingFontSize, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: onboardingFirstStepCopyMaxWidth)
                .frame(maxWidth: .infinity)
            }
        case 1:
            VStack(alignment: .leading, spacing: 14) {
                Text("Pin SendMoi in your Share Sheet")
                    .font(.system(size: onboardingSecondStepHeadlineFontSize, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)

                Text("Do this once and SendMoi stays one tap away.")
                    .font(.system(size: onboardingSecondStepSubheadingFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1.3)
                    .fixedSize(horizontal: false, vertical: true)

                TabView(selection: $onboardingPinSlide) {
                    ForEach(onboardingPinSlides) { slide in
                        RoundedRectangle(cornerRadius: 24)
                            .fill(onboardingInsetCardFill)
                            .overlay {
                                Image(slide.imageName)
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFit()
                                    .padding(onboardingPinCarouselImagePadding)
                                    .accessibilityLabel(Text(slide.accessibilityLabel))
                                    .accessibilityHint(Text(slide.accessibilityHint))
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(onboardingCardStroke, lineWidth: 1)
                            )
                            .tag(slide.id)
                    }
                }
                .frame(height: onboardingPinCarouselHeight)
                .tabViewStyle(.page(indexDisplayMode: .never))
                .accessibilityLabel(Text("Pin SendMoi setup steps"))
                .accessibilityValue(Text("Step \(onboardingPinSlide + 1) of \(onboardingPinSlides.count)"))

                Text("Step \(onboardingPinSlide + 1) of \(onboardingPinSlides.count)")
                    .font(.system(size: onboardingSecondStepProgressFontSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    ForEach(onboardingPinSlides) { slide in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                onboardingPinSlide = slide.id
                            }
                        } label: {
                            Capsule()
                                .fill(slide.id == onboardingPinSlide ? onboardingBrandAccent : onboardingMutedTrack)
                                .frame(width: slide.id == onboardingPinSlide ? 16 : 6, height: 5)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Show step \(slide.id + 1)"))
                        .accessibilityHint(Text(slide.title))
                    }
                    Spacer(minLength: 0)
                }
                .animation(.easeInOut(duration: 0.2), value: onboardingPinSlide)

                VStack(alignment: .leading, spacing: 6) {
                    Text(onboardingPinSlides[onboardingPinSlide].title)
                        .font(.system(size: onboardingSecondStepInstructionTitleFontSize, weight: .semibold))

                    Text(onboardingPinSlides[onboardingPinSlide].detail)
                        .font(.system(size: onboardingSecondStepInstructionBodyFontSize, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineSpacing(1.2)
                }
                .padding(.horizontal, 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    Text("\(onboardingPinSlides[onboardingPinSlide].title). \(onboardingPinSlides[onboardingPinSlide].detail)")
                )

            }
        default:
            onboardingFinishStep
        }
    }

    private var onboardingPinSlides: [OnboardingPinSlide] {
        [
            OnboardingPinSlide(
                id: 0,
                imageName: "OnboardingPinStep1",
                title: "1. Open Share and tap More",
                detail: "From the first app row in the share sheet, open More to edit your app list.",
                accessibilityLabel: "Share sheet app row with More highlighted.",
                accessibilityHint: "This shows where to find More before editing your app list."
            ),
            OnboardingPinSlide(
                id: 1,
                imageName: "OnboardingPinStep2",
                title: "2. Add SendMoi to Favorites",
                detail: "Tap the green plus next to SendMoi so it appears in Favorites.",
                accessibilityLabel: "Apps list showing SendMoi being added to Favorites.",
                accessibilityHint: "Use the plus button next to SendMoi in the apps list."
            ),
            OnboardingPinSlide(
                id: 2,
                imageName: "OnboardingPinStep3",
                title: "3. Keep SendMoi enabled",
                detail: "Make sure SendMoi stays toggled on, then tap Done.",
                accessibilityLabel: "Apps list showing SendMoi enabled and ready.",
                accessibilityHint: "Verify SendMoi stays enabled, then finish by tapping Done."
            )
        ]
    }

    private var onboardingPinCarouselHeight: CGFloat {
        onboardingUsesSmallPhoneLayout ? 320 : 360
    }

    private var onboardingPinCarouselImagePadding: CGFloat {
        onboardingUsesSmallPhoneLayout ? 10 : 14
    }

    private var onboardingSecondStepHeadlineFontSize: CGFloat {
        onboardingUsesSmallPhoneLayout ? 24 : 28
    }

    private var onboardingSecondStepSubheadingFontSize: CGFloat {
        onboardingUsesSmallPhoneLayout ? 17 : 19
    }

    private var onboardingSecondStepInstructionTitleFontSize: CGFloat {
        onboardingUsesSmallPhoneLayout ? 18 : 20
    }

    private var onboardingSecondStepInstructionBodyFontSize: CGFloat {
        onboardingUsesSmallPhoneLayout ? 16 : 17
    }

    private var onboardingSecondStepProgressFontSize: CGFloat {
        onboardingUsesSmallPhoneLayout ? 13 : 14
    }

    private struct OnboardingPinSlide: Identifiable {
        let id: Int
        let imageName: String
        let title: String
        let detail: String
        let accessibilityLabel: String
        let accessibilityHint: String
    }

    @ViewBuilder
    private var onboardingFinishStep: some View {
        if model.session == nil {
            VStack(alignment: .leading, spacing: 14) {
                Text("Connect Gmail to finish setup.")
                    .font(.system(size: onboardingFirstStepHeadlineFontSize, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)

                onboardingFeatureRow(
                    iconName: "lock.shield.fill",
                    title: "Secure sign-in",
                    detail: "Google handles the login. SendMoi never sees your password or inbox."
                )
                onboardingFeatureRow(
                    iconName: "envelope.badge.fill",
                    title: "Skip if you want",
                    detail: "You can use the app now and connect Gmail later."
                )

                Button("Connect Gmail") {
                    showsOnboardingAccountSheet = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!GoogleOAuthConfig.isConfigured)
                .padding(.top, 4)
                .accessibilityHint("Opens Google sign-in in a system sheet.")

                Text("Or tap Skip below and connect later from Account. · [Privacy Policy](https://send.moi/privacy)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .tint(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ready to go.")
                    .font(.system(size: onboardingFirstStepHeadlineFontSize, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)

                Text("Gmail is connected. Add a default recipient now, or leave it blank and choose in the share sheet each time.")
                    .font(.system(size: onboardingFirstStepSubheadingFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1.3)

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
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
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
            if onboardingStep == 0 {
                HStack {
                    Spacer(minLength: 0)
                    onboardingDemoPhoneFrame
                    Spacer(minLength: 0)
                }
            } else {
                RoundedRectangle(cornerRadius: 22)
                    .fill(onboardingInsetCardFill)
                    .frame(height: onboardingFlowPreviewHeight)
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
    }

    private var onboardingDemoPhoneFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: onboardingDemoPhoneCornerRadius + 7, style: .continuous)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.52 : 0.24))
                .overlay(
                    RoundedRectangle(cornerRadius: onboardingDemoPhoneCornerRadius + 7, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    onboardingBrandSecondary.opacity(colorScheme == .dark ? 0.95 : 0.7),
                                    Color(red: 0.49804, green: 0.24706, blue: 0.97647).opacity(colorScheme == .dark ? 0.95 : 0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: onboardingBrandSecondary.opacity(colorScheme == .dark ? 0.4 : 0.18), radius: 16, y: 8)

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: onboardingDemoPhoneCornerRadius, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.92 : 0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: onboardingDemoPhoneCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.24), lineWidth: 1)
                    )

                LoopingVideoPlayerView(resourceName: "sendmoi-demo-hero", resourceExtension: "mp4")
                    .aspectRatio(onboardingDemoVideoAspectRatio, contentMode: .fit)
                    .frame(width: onboardingDemoPhoneWidth - 14, height: onboardingDemoPhoneHeight - 18)
                    .clipShape(RoundedRectangle(cornerRadius: onboardingDemoScreenCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: onboardingDemoScreenCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .padding(.top, 9)

                Capsule()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: onboardingDemoPhoneWidth * 0.34, height: 8)
                    .padding(.top, 7)
            }
            .padding(8)
        }
        .frame(width: onboardingDemoPhoneWidth + 16, height: onboardingDemoPhoneHeight + 16)
        .shadow(color: .black.opacity(0.32), radius: 16, y: 9)
    }

    private func onboardingFeatureRow(iconName: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(onboardingBrandAccentSoft)

                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(onboardingBrandAccent)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: onboardingFeatureTitleFontSize, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.system(size: onboardingFeatureDetailFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1.2)
            }

            Spacer(minLength: 0)
        }
    }

    private func onboardingFlowNode(iconName: String, title: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(onboardingBrandAccent.opacity(onboardingPulse ? 0.26 : 0.14))

                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(onboardingBrandAccent)
            }
            .frame(width: 42, height: 42)

            Text(title)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }

    private var onboardingFlowConnector: some View {
        Capsule()
            .fill(onboardingMutedTrack)
            .frame(maxWidth: .infinity)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(onboardingBrandAccent)
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
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(onboardingBrandAccent)
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
                Color(red: 0.02, green: 0.07, blue: 0.18),
                Color(red: 0.04, green: 0.11, blue: 0.28),
                Color(red: 0.06, green: 0.16, blue: 0.38)
            ]
        }

        return [
            Color(red: 0.95, green: 0.98, blue: 1.0),
            Color(red: 0.91, green: 0.96, blue: 1.0),
            Color(red: 0.92, green: 0.95, blue: 1.0)
        ]
    }

    private var onboardingAuroraHighlight: Color {
        colorScheme == .dark
            ? onboardingBrandSecondary.opacity(0.26)
            : Color.white.opacity(0.78)
    }

    private var onboardingAuroraAccent: Color {
        colorScheme == .dark
            ? onboardingBrandDeep.opacity(0.30)
            : onboardingBrandSecondary.opacity(0.18)
    }

    private var onboardingCardBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.09)
            : Color.white.opacity(0.8)
    }

    private var onboardingInsetCardFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.07)
            : Color.white.opacity(0.86)
    }

    private var onboardingCardStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.16)
            : Color.primary.opacity(0.1)
    }

    private var onboardingBrandAccent: Color {
        Color(red: 0.16863, green: 0.49804, blue: 1.0)
    }

    private var onboardingBrandSecondary: Color {
        Color(red: 0.21961, green: 0.44706, blue: 1.0)
    }

    private var onboardingBrandDeep: Color {
        Color(red: 0.07059, green: 0.18824, blue: 0.47843)
    }

    private var onboardingBrandAccentSoft: Color {
        onboardingBrandAccent.opacity(colorScheme == .dark ? 0.24 : 0.16)
    }

    private var onboardingMutedTrack: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.primary.opacity(0.12)
    }

    private var onboardingInlinePaginationActive: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.42)
            : Color.primary.opacity(0.28)
    }

    private var onboardingInlinePaginationInactive: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.18)
            : Color.primary.opacity(0.14)
    }

    private var onboardingStepHeadlineGradient: LinearGradient {
        LinearGradient(
            colors: [
                onboardingBrandSecondary.opacity(colorScheme == .dark ? 0.96 : 0.92),
                Color(red: 0.49804, green: 0.24706, blue: 0.97647).opacity(colorScheme == .dark ? 0.97 : 0.92)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var onboardingStepSupportingText: Color {
        colorScheme == .dark
            ? onboardingBrandSecondary.opacity(0.76)
            : onboardingBrandDeep.opacity(0.72)
    }

    private var onboardingUsesTightFirstStepLayout: Bool {
        onboardingStep == 0 && !usesDesktopLayout
    }

    private var onboardingUsesSmallPhoneLayout: Bool {
        #if os(iOS)
        !usesDesktopLayout && UIScreen.main.bounds.height <= 812
        #else
        false
        #endif
    }

    private var onboardingMainSpacing: CGFloat {
        if onboardingUsesSmallPhoneLayout {
            return 14
        }
        return onboardingUsesTightFirstStepLayout ? 16 : 24
    }

    private var onboardingVerticalPadding: CGFloat {
        onboardingUsesSmallPhoneLayout ? 12 : (onboardingUsesTightFirstStepLayout ? 14 : 24)
    }

    private var onboardingStepCardPadding: CGFloat {
        onboardingUsesSmallPhoneLayout ? 16 : (onboardingUsesTightFirstStepLayout ? 18 : 22)
    }

    private var onboardingStepCardCornerRadius: CGFloat {
        onboardingUsesSmallPhoneLayout ? 22 : (onboardingUsesTightFirstStepLayout ? 24 : 28)
    }

    private var onboardingFirstStepSpacing: CGFloat {
        onboardingUsesTightFirstStepLayout ? 10 : 12
    }

    private var onboardingFirstStepHeadingSize: CGFloat {
        onboardingUsesTightFirstStepLayout ? 22 : 24
    }

    private var onboardingFirstStepHeadlineFontSize: CGFloat {
        onboardingUsesSmallPhoneLayout ? 24 : onboardingFirstStepHeadingSize + 4
    }

    private var onboardingFirstStepSubheadingFontSize: CGFloat {
        onboardingUsesSmallPhoneLayout ? 17 : (onboardingUsesTightFirstStepLayout ? 18 : 19)
    }

    private var onboardingFirstStepMediaToCopySpacing: CGFloat {
        onboardingUsesSmallPhoneLayout ? 18 : (onboardingUsesTightFirstStepLayout ? 22 : 26)
    }

    private var onboardingFirstStepTopSpacing: CGFloat {
        onboardingUsesSmallPhoneLayout ? 6 : (onboardingUsesTightFirstStepLayout ? 10 : 14)
    }

    private var onboardingFirstStepCopyMaxWidth: CGFloat {
        onboardingUsesSmallPhoneLayout ? 306 : (onboardingUsesTightFirstStepLayout ? 326 : 396)
    }

    private var onboardingFlowPreviewHeight: CGFloat {
        118
    }

    private var onboardingDemoVideoAspectRatio: CGFloat {
        1206.0 / 2622.0
    }

    private var onboardingDemoPhoneWidth: CGFloat {
        if onboardingUsesSmallPhoneLayout {
            return 202
        }
        return onboardingUsesTightFirstStepLayout ? 218 : 180
    }

    private var onboardingDemoPhoneHeight: CGFloat {
        onboardingDemoPhoneWidth / onboardingDemoVideoAspectRatio
    }

    private var onboardingDemoPhoneCornerRadius: CGFloat {
        onboardingUsesTightFirstStepLayout ? 24 : 22
    }

    private var onboardingDemoScreenCornerRadius: CGFloat {
        onboardingUsesTightFirstStepLayout ? 19 : 17
    }

    private var onboardingPinnedActionsInset: CGFloat {
        onboardingUsesSmallPhoneLayout ? 102 : 110
    }

    private var onboardingFeatureTitleFontSize: CGFloat {
        onboardingUsesSmallPhoneLayout ? 16 : 18
    }

    private var onboardingFeatureDetailFontSize: CGFloat {
        onboardingUsesSmallPhoneLayout ? 15 : 16
    }

    private var onboardingPinnedActions: some View {
        onboardingActions
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 14)
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

private extension View {
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

        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }
}

private struct LoopingVideoPlayerView: View {
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
