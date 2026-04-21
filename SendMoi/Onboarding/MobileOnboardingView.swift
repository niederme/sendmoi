import SwiftUI

struct MobileOnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    @Binding var onboardingStep: Int
    @Binding var onboardingRecipientDraft: String
    @Binding var onboardingRecipientConfirmed: Bool
    @Binding var onboardingPulse: Bool
    @Binding var onboardingPinSlide: Int

    let finish: () -> Void
    let skip: () -> Void
    let goBack: () -> Void
    let handlePrimaryAction: () -> Void
    let showAccountSheet: () -> Void
    let saveRecipient: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: mainSpacing) {
                        stepCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, verticalPadding)
                    .padding(.bottom, pinnedActionsInset)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }

                pinnedActions
            }
            .background(background.ignoresSafeArea())
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

    private var stepCard: some View {
        Group {
            if onboardingStep == 0 {
                stepDetail
                    .padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    stepDetail

                    if onboardingStep == 2 && model.session == nil && !GoogleOAuthConfig.isConfigured {
                        Text("Google OAuth is not configured yet, so Gmail sign-in is disabled until `GoogleOAuthConfig.clientID` is set.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(stepCardPadding)
                .background(
                    RoundedRectangle(cornerRadius: stepCardCornerRadius)
                        .fill(cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: stepCardCornerRadius)
                        .stroke(cardStroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.09), radius: 18, y: 10)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            if onboardingStep == 2 && model.session != nil {
                Button("Back") {
                    goBack()
                }
                .onboardingSecondaryButtonStyle()
                .buttonBorderShape(.capsule)
                .controlSize(.large)

                Spacer(minLength: 0)

                Button("Done") {
                    finish()
                }
                .onboardingPrimaryButtonStyle(tint: brandAccent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            } else {
                Button("Skip") {
                    skip()
                }
                .onboardingSecondaryButtonStyle()
                .buttonBorderShape(.capsule)
                .controlSize(.large)

                Spacer(minLength: 10)

                inlinePagination

                Spacer(minLength: 10)

                HStack(spacing: 12) {
                    if onboardingStep > 0 {
                        Button {
                            goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .onboardingSecondaryButtonStyle()
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .frame(width: 46, height: 46)
                    }

                    if onboardingStep < 2 {
                        Button {
                            handlePrimaryAction()
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .onboardingPrimaryButtonStyle(tint: brandAccent)
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
                    }
                }
            }
        }
    }

    private var inlinePagination: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index == onboardingStep ? inlinePaginationActive : inlinePaginationInactive)
                    .frame(width: index == onboardingStep ? 14 : 6, height: 4)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: onboardingStep)
    }

    @ViewBuilder
    private var stepDetail: some View {
        switch onboardingStep {
        case 0:
            VStack(alignment: .leading, spacing: 0) {
                flowPreview
                    .padding(.top, firstStepTopSpacing)
                    .padding(.bottom, firstStepMediaToCopySpacing)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Send anything to your\nGmail inbox, with just two taps.")
                        .font(.system(size: firstStepHeadlineFontSize, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)

                    Text("SendMoi makes it easy to send links to your Gmail inbox without losing them in tabs, bookmarks, or chats.")
                        .font(.system(size: firstStepSubheadingFontSize, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: firstStepCopyMaxWidth)
                .frame(maxWidth: .infinity)
            }
        case 1:
            VStack(alignment: .leading, spacing: 14) {
                Text("Pin SendMoi in your Share Sheet")
                    .font(.system(size: 28, weight: .bold))

                Text("Do this once and SendMoi stays one tap away.")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.secondary)

                TabView(selection: $onboardingPinSlide) {
                    ForEach(pinSlides) { slide in
                        RoundedRectangle(cornerRadius: 24)
                            .fill(insetCardFill)
                            .overlay {
                                Image(slide.imageName)
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFit()
                                    .padding(14)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(cardStroke, lineWidth: 1)
                            )
                            .tag(slide.id)
                    }
                }
                .frame(height: 360)
                .sendMoiPageTabViewStyle()

                Text("Step \(onboardingPinSlide + 1) of \(pinSlides.count)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    ForEach(pinSlides) { slide in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                onboardingPinSlide = slide.id
                            }
                        } label: {
                            Capsule()
                                .fill(slide.id == onboardingPinSlide ? brandAccent : mutedTrack)
                                .frame(width: slide.id == onboardingPinSlide ? 16 : 6, height: 5)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(pinSlides[onboardingPinSlide].title)
                        .font(.system(size: 20, weight: .semibold))

                    Text(pinSlides[onboardingPinSlide].detail)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        default:
            finishStep
        }
    }

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.session == nil {
                Text("Connect Gmail to finish setup.")
                    .font(.system(size: firstStepHeadlineFontSize, weight: .bold))

                featureRow(
                    iconName: "lock.shield.fill",
                    title: "Secure sign-in",
                    detail: "Google handles the login. SendMoi never sees your password or inbox."
                )

                featureRow(
                    iconName: "envelope.badge.fill",
                    title: "Skip if you want",
                    detail: "You can use the app now and connect Gmail later."
                )

                Button("Connect Gmail") {
                    showAccountSheet()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!GoogleOAuthConfig.isConfigured)

                Text("Or tap Skip below and connect later from Account. · [Privacy Policy](https://send.moi/privacy)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .tint(brandAccent)
            } else {
                Text("Ready to go.")
                    .font(.system(size: firstStepHeadlineFontSize, weight: .bold))

                Text("Gmail is connected. Add a default recipient now, or leave it blank and choose in the share sheet each time.")
                    .font(.system(size: firstStepSubheadingFontSize, weight: .medium))
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
                            showAccountSheet()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(insetCardFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(cardStroke, lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Default recipient")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    #if os(iOS)
                    TextField("Email address (optional)", text: $onboardingRecipientDraft)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(saveRecipient)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(insetCardFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(cardStroke, lineWidth: 1)
                        )
                    #else
                    TextField("Email address (optional)", text: $onboardingRecipientDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveRecipient)
                    #endif

                    if showsRecipientSave {
                        Button("Save") {
                            saveRecipient()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }

                if showsAutoSendToggle {
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

    private var flowPreview: some View {
        HStack {
            Spacer(minLength: 0)
            demoPhoneFrame
            Spacer(minLength: 0)
        }
    }

    private var demoPhoneFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 29, style: .continuous)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.52 : 0.24))
                .overlay(
                    RoundedRectangle(cornerRadius: 29, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    brandSecondary.opacity(colorScheme == .dark ? 0.95 : 0.7),
                                    Color(red: 0.49804, green: 0.24706, blue: 0.97647).opacity(colorScheme == .dark ? 0.95 : 0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.92 : 0.95))

                LoopingVideoPlayerView(resourceName: "sendmoi-demo-hero", resourceExtension: "mp4")
                    .aspectRatio(1206.0 / 2622.0, contentMode: .fit)
                    .frame(width: demoPhoneWidth - 14, height: demoPhoneHeight - 18)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .padding(.top, 9)

                Capsule()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: demoPhoneWidth * 0.34, height: 8)
                    .padding(.top, 7)
            }
            .padding(8)
        }
        .frame(width: demoPhoneWidth + 16, height: demoPhoneHeight + 16)
        .shadow(color: .black.opacity(0.32), radius: 16, y: 9)
    }

    private func featureRow(iconName: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(brandAccentSoft)

                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(brandAccent)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: featureTitleFontSize, weight: .semibold))

                Text(detail)
                    .font(.system(size: featureDetailFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var pinSlides: [OnboardingPinSlide] {
        [
            OnboardingPinSlide(
                id: 0,
                imageName: "OnboardingPinStep1",
                title: "1. Open Share and tap More",
                detail: "From the first app row in the share sheet, open More to edit your app list."
            ),
            OnboardingPinSlide(
                id: 1,
                imageName: "OnboardingPinStep2",
                title: "2. Add SendMoi to Favorites",
                detail: "Tap the green plus next to SendMoi so it appears in Favorites."
            ),
            OnboardingPinSlide(
                id: 2,
                imageName: "OnboardingPinStep3",
                title: "3. Keep SendMoi enabled",
                detail: "Make sure SendMoi stays toggled on, then tap Done."
            )
        ]
    }

    private var pinnedActions: some View {
        actions
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 14)
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

    private var showsAutoSendToggle: Bool {
        let normalizedSavedRecipient = model.defaultRecipient
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedDraft = onboardingRecipientDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return !model.defaultRecipient.isEmpty && normalizedDraft == normalizedSavedRecipient
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [auroraHighlight, .clear],
                center: .topTrailing,
                startRadius: 24,
                endRadius: 320
            )
            .offset(x: -34, y: -190)

            LinearGradient(
                colors: [auroraAccent, .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: 420, height: 320)
            .blur(radius: 52)
            .rotationEffect(.degrees(-16))
            .offset(x: -168, y: 286)
        }
    }

    private var backgroundColors: [Color] {
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

    private var auroraHighlight: Color {
        colorScheme == .dark ? brandSecondary.opacity(0.26) : Color.white.opacity(0.78)
    }

    private var auroraAccent: Color {
        colorScheme == .dark ? brandDeep.opacity(0.30) : brandSecondary.opacity(0.18)
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.09) : Color.white.opacity(0.8)
    }

    private var insetCardFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.86)
    }

    private var cardStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.primary.opacity(0.1)
    }

    private var brandAccent: Color {
        Color(red: 0.16863, green: 0.49804, blue: 1.0)
    }

    private var brandSecondary: Color {
        Color(red: 0.21961, green: 0.44706, blue: 1.0)
    }

    private var brandDeep: Color {
        Color(red: 0.07059, green: 0.18824, blue: 0.47843)
    }

    private var brandAccentSoft: Color {
        brandAccent.opacity(colorScheme == .dark ? 0.24 : 0.16)
    }

    private var mutedTrack: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.primary.opacity(0.12)
    }

    private var inlinePaginationActive: Color {
        colorScheme == .dark ? Color.white.opacity(0.42) : Color.primary.opacity(0.28)
    }

    private var inlinePaginationInactive: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.primary.opacity(0.14)
    }

    private var usesSmallPhoneLayout: Bool {
        #if os(iOS)
        UIScreen.main.bounds.height <= 812
        #else
        false
        #endif
    }

    private var mainSpacing: CGFloat {
        usesSmallPhoneLayout ? 14 : 16
    }

    private var verticalPadding: CGFloat {
        usesSmallPhoneLayout ? 12 : 14
    }

    private var stepCardPadding: CGFloat {
        usesSmallPhoneLayout ? 16 : 18
    }

    private var stepCardCornerRadius: CGFloat {
        usesSmallPhoneLayout ? 22 : 24
    }

    private var firstStepHeadlineFontSize: CGFloat {
        usesSmallPhoneLayout ? 24 : 28
    }

    private var firstStepSubheadingFontSize: CGFloat {
        usesSmallPhoneLayout ? 17 : 18
    }

    private var firstStepMediaToCopySpacing: CGFloat {
        usesSmallPhoneLayout ? 18 : 22
    }

    private var firstStepTopSpacing: CGFloat {
        usesSmallPhoneLayout ? 6 : 10
    }

    private var firstStepCopyMaxWidth: CGFloat {
        usesSmallPhoneLayout ? 306 : 326
    }

    private var pinnedActionsInset: CGFloat {
        usesSmallPhoneLayout ? 102 : 110
    }

    private var featureTitleFontSize: CGFloat {
        usesSmallPhoneLayout ? 16 : 18
    }

    private var featureDetailFontSize: CGFloat {
        usesSmallPhoneLayout ? 15 : 16
    }

    private var demoPhoneWidth: CGFloat {
        usesSmallPhoneLayout ? 202 : 218
    }

    private var demoPhoneHeight: CGFloat {
        demoPhoneWidth / (1206.0 / 2622.0)
    }
}

private struct OnboardingPinSlide: Identifiable {
    let id: Int
    let imageName: String
    let title: String
    let detail: String
}
