import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedField: Field?
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

    var body: some View {
        NavigationStack {
            rootContent
                .navigationTitle(usesDesktopLayout ? "SendMoi" : "")
#if !os(macOS)
                .toolbar(usesDesktopLayout ? .automatic : .hidden, for: .navigationBar)
#endif
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
            MacControlCenterView(
                openSetupGuide: openSetupGuide,
                showResetConfirmation: { showsResetConfirmation = true }
            )
            .frame(minWidth: 980, minHeight: 880, alignment: .topLeading)
        } else {
            #if os(iOS)
            mobileContent
            #endif
        }
    }

    private var usesDesktopLayout: Bool {
        #if os(macOS) || targetEnvironment(macCatalyst)
        true
        #else
        ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    #if os(iOS)
    private var mobileContent: some View {
        GeometryReader { proxy in
            let topBarHeight = mobileTopBarHeight(topInset: proxy.safeAreaInsets.top)

            ScrollView {
                compactMobileContent
                    .padding(.top, topBarHeight + 12)
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemGroupedBackground))
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .top) {
                mobileTopBar(topInset: proxy.safeAreaInsets.top)
            }
        }
    }

    private func mobileTopBarHeight(topInset: CGFloat) -> CGFloat {
        topInset + 56
    }

    private func mobileTopBar(topInset: CGFloat) -> some View {
        let solidHeight = topInset + 18
        let fadeHeight = mobileTopBarHeight(topInset: topInset) - solidHeight

        return ZStack(alignment: .top) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: mobileTopBarHeight(topInset: topInset))
                .mask(alignment: .top) {
                    VStack(spacing: 0) {
                        Rectangle()
                            .frame(height: solidHeight)

                        LinearGradient(
                            colors: [.black, .black.opacity(0.72), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: fadeHeight)
                    }
                }

            LinearGradient(
                colors: [
                    Color(.systemBackground).opacity(colorScheme == .dark ? 0.72 : 0.62),
                    Color(.systemBackground).opacity(colorScheme == .dark ? 0.28 : 0.16),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: mobileTopBarHeight(topInset: topInset) + 8)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    #endif

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
                        .frame(width: 56, height: 56)
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
                        .frame(width: 56, height: 56)
                    } else if onboardingStep == 2 && model.session == nil {
                        Button {
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .onboardingSecondaryButtonStyle()
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .frame(width: 56, height: 56)
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
                .sendMoiPageTabViewStyle()
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
                    .tint(onboardingBrandAccent)
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
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Text("You can switch accounts before finishing setup.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            showsOnboardingAccountSheet = true
                        } label: {
                            Text("Switch Account")
                                .lineLimit(1)
                                .minimumScaleFactor(0.95)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)
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

    #if os(iOS)
    private var compactMobileContent: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            mobileIntroView
                .padding(EdgeInsets(top: 8, leading: 20, bottom: 28, trailing: 20))

            mobileSectionLabel("Account")
            GroupedCard { mobileAccountCardContent }
            mobileSectionFooter(accountSectionFooterText)

            mobileSectionLabel("Recipient")
            GroupedCard { mobileRecipientCardContent }
            mobileSectionFooter("Used as the default when starting from the share sheet.")

            mobileSectionLabel("Share Sheet")
            GroupedCard {
                Toggle("Auto-send", isOn: Binding(
                    get: { model.shareSheetAutoSendEnabled },
                    set: { model.setShareSheetAutoSendEnabled($0) }
                ))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            mobileSectionFooter(shareSheetFooterText)

            mobileSectionLabel("Offline Queue")
            GroupedCard { mobileQueueCardContent }
            mobileSectionFooter(queueFooterText)

            mobileSectionLabel("Setup")
            GroupedCard {
                Button("Open Setup Guide") { openSetupGuide() }
                    .disabled(model.isBusy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                Divider().padding(.leading, 20)
                Button("Clear Settings", role: .destructive) {
                    showsResetConfirmation = true
                }
                .disabled(model.isBusy)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            mobileSectionFooter("Open Setup Guide keeps your current account. Clear Settings disconnects Gmail and resets SendMoi to first launch.")

            mobileAttributionFooter
        }
        .padding(.bottom, 40)
    }

    private var mobileIntroView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SendMoi")
                .font(.largeTitle.weight(.bold))

            Text("Send links to your Gmail inbox without losing them in tabs, bookmarks, or chats.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(1.2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func mobileSectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }

    private func mobileSectionFooter(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 8)
    }

    private var mobileAccountCardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.isAccountSectionExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(accountSummaryTitle)
                        Text(accountSummaryDetail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(model.isAccountSectionExpanded ? .degrees(90) : .zero)
                        .animation(.easeInOut(duration: 0.2), value: model.isAccountSectionExpanded)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if model.isAccountSectionExpanded {
                if let session = model.session {
                    Divider().padding(.leading, 20)
                    LabeledContent("From", value: session.emailAddress ?? "Authenticated via Gmail")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)

                    if model.requiresGmailReconnect {
                        Divider().padding(.leading, 20)
                        Text("The saved Gmail session is missing send permission.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                        Divider().padding(.leading, 20)
                        Button("Reconnect Gmail") {
                            Task { await model.signIn() }
                        }
                        .disabled(model.isBusy || !GoogleOAuthConfig.isConfigured)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }

                    Divider().padding(.leading, 20)
                    Button("Sign Out") { model.signOut() }
                        .disabled(model.isBusy)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                } else {
                    Divider().padding(.leading, 20)
                    Text("No Gmail account connected.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    Divider().padding(.leading, 20)
                    Button("Sign In With Google") {
                        Task { await model.signIn() }
                    }
                    .disabled(model.isBusy || !GoogleOAuthConfig.isConfigured)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }

                if !GoogleOAuthConfig.isConfigured {
                    Divider().padding(.leading, 20)
                    Text("Set `GoogleOAuthConfig.clientID` before signing in.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    private var mobileRecipientCardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Default Recipient")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Email address", text: $model.defaultRecipient)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focusedField, equals: .defaultRecipient)
                    .onSubmit(saveDefaultRecipient)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider().padding(.leading, 20)

            Button {
                saveDefaultRecipient()
            } label: {
                Text("Save Default Recipient")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var mobileQueueCardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.isQueueSectionExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(queueSummaryTitle)
                        Text(queueSummaryDetail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(model.isQueueSectionExpanded ? .degrees(90) : .zero)
                        .animation(.easeInOut(duration: 0.2), value: model.isQueueSectionExpanded)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if model.isQueueSectionExpanded {
                if model.queuedEmails.isEmpty {
                    Divider().padding(.leading, 20)
                    Text("No pending emails.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                } else {
                    ForEach(model.queuedEmails) { item in
                        Divider().padding(.leading, 20)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(.headline)
                            Text("To: \(item.toEmail)").font(.subheadline)
                            Text(item.urlString).font(.footnote).foregroundStyle(.secondary)
                            if let lastError = item.lastError {
                                Text(lastError).font(.footnote).foregroundStyle(.orange)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                if let index = model.queuedEmails.firstIndex(where: { $0.id == item.id }) {
                                    model.deleteQueuedEmails(at: IndexSet([index]))
                                }
                            }
                        }
                    }
                }

                if model.requiresGmailReconnect {
                    Divider().padding(.leading, 20)
                    Button {
                        Task { await model.signIn() }
                    } label: {
                        Text("Reconnect Gmail").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.isBusy || !GoogleOAuthConfig.isConfigured)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }

                Divider().padding(.leading, 20)
                Button {
                    Task { await model.retryNow() }
                } label: {
                    Text("Send Queued Now").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isBusy || model.queuedEmails.isEmpty || model.requiresGmailReconnect)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
    }

    private var mobileAttributionFooter: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return Text("SendMoi by John Niedermeyer, with a little help from Codex, Claude Code and friends.\nv\(version) (\(build))")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }

    #endif // os(iOS)

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

        return model.isOnline ? "Network looks available. The app retries automatically." : "Offline or unreachable. Items remain queued."
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

    private func saveOnboardingRecipient() {
        guard onboardingShowsRecipientSave else {
            return
        }

        focusedField = nil
        model.setDefaultRecipient(onboardingRecipientDraft)
        onboardingRecipientDraft = model.defaultRecipient
        onboardingRecipientConfirmed = true
    }

}

#if os(iOS)
private struct GroupedCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
    }
}
#endif

private extension View {
    @ViewBuilder
    func sendMoiPageTabViewStyle() -> some View {
        #if os(iOS) || targetEnvironment(macCatalyst)
        self.tabViewStyle(.page(indexDisplayMode: .never))
        #else
        self
        #endif
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
    private var shouldAutoPlay = false

    init(resource: String, ext: String) {
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        queuePlayer.actionAtItemEnd = .none
        self.player = queuePlayer
        #if canImport(UIKit)
        // Prevent the silent demo video from activating the audio session
        // and interrupting system audio playback
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        #endif

        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            return
        }

        Task {
            let item = await Self.makeVideoOnlyItem(url: url)
            looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
            if shouldAutoPlay {
                player.play()
            }
        }
    }

    func play() {
        shouldAutoPlay = true
        player.play()
    }

    func pause() {
        shouldAutoPlay = false
        player.pause()
    }

    private static func makeVideoOnlyItem(url: URL) async -> AVPlayerItem {
        let sourceAsset = AVURLAsset(url: url)
        let composition = AVMutableComposition()

        do {
            let sourceVideoTracks = try await sourceAsset.loadTracks(withMediaType: .video)
            guard
                let sourceVideoTrack = sourceVideoTracks.first,
                let videoOnlyCompositionTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
            else {
                return AVPlayerItem(url: url)
            }

            let duration = try await sourceAsset.load(.duration)
            let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
            let timeRange = CMTimeRange(start: .zero, duration: duration)
            try videoOnlyCompositionTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)
            videoOnlyCompositionTrack.preferredTransform = preferredTransform
            return AVPlayerItem(asset: composition)
        } catch {
            return AVPlayerItem(url: url)
        }
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
private final class LoopingVideoPlayerContainerNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

private struct LoopingVideoPlayerNativeView: NSViewRepresentable {
    let player: AVQueuePlayer

    func makeNSView(context: Context) -> LoopingVideoPlayerContainerNSView {
        let view = LoopingVideoPlayerContainerNSView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ nsView: LoopingVideoPlayerContainerNSView, context: Context) {
        nsView.playerLayer.player = player
    }

    static func dismantleNSView(_ nsView: LoopingVideoPlayerContainerNSView, coordinator: ()) {
        nsView.playerLayer.player = nil
    }
}
#endif
