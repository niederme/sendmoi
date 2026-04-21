import SwiftUI

struct OnboardingFlowView: View {
    @EnvironmentObject private var model: AppModel

    let isDesktopLayout: Bool
    let finish: () -> Void

    @State private var onboardingStep = 0
    @State private var onboardingRecipientDraft = ""
    @State private var onboardingRecipientConfirmed = false
    @State private var onboardingPulse = false
    @State private var onboardingPinSlide = 0
    @State private var showsOnboardingAccountSheet = false

    var body: some View {
        Group {
            if isDesktopLayout {
                MacOnboardingWizardView(
                    onboardingStep: $onboardingStep,
                    onboardingRecipientDraft: $onboardingRecipientDraft,
                    onboardingRecipientConfirmed: $onboardingRecipientConfirmed,
                    finish: finish,
                    skip: skip,
                    goBack: goBack,
                    handlePrimaryAction: handlePrimaryAction,
                    showAccountSheet: showAccountSheet,
                    saveRecipient: saveRecipient
                )
            } else {
                MobileOnboardingView(
                    onboardingStep: $onboardingStep,
                    onboardingRecipientDraft: $onboardingRecipientDraft,
                    onboardingRecipientConfirmed: $onboardingRecipientConfirmed,
                    onboardingPulse: $onboardingPulse,
                    onboardingPinSlide: $onboardingPinSlide,
                    finish: finish,
                    skip: skip,
                    goBack: goBack,
                    handlePrimaryAction: handlePrimaryAction,
                    showAccountSheet: showAccountSheet,
                    saveRecipient: saveRecipient
                )
            }
        }
        .task {
            if onboardingRecipientDraft.isEmpty {
                onboardingRecipientDraft = model.defaultRecipient
            }
        }
        .sheet(isPresented: $showsOnboardingAccountSheet) {
            OnboardingGmailSheet {
                onboardingStep = 2
                onboardingRecipientDraft = model.defaultRecipient
                onboardingRecipientConfirmed = false
            }
            .environmentObject(model)
        }
    }

    private func handlePrimaryAction() {
        if isDesktopLayout {
            handleDesktopPrimaryAction()
        } else {
            handleMobilePrimaryAction()
        }
    }

    private func handleDesktopPrimaryAction() {
        switch onboardingStep {
        case 0:
            onboardingStep = 1
        case 1:
            guard model.session != nil else {
                showsOnboardingAccountSheet = true
                return
            }
            onboardingStep = 2
        default:
            finish()
        }
    }

    private func handleMobilePrimaryAction() {
        if onboardingStep < 2 {
            onboardingStep += 1
        } else if model.session == nil {
            showsOnboardingAccountSheet = true
        } else {
            finish()
        }
    }

    private func goBack() {
        guard onboardingStep > 0 else {
            return
        }

        onboardingStep -= 1
    }

    private func showAccountSheet() {
        showsOnboardingAccountSheet = true
    }

    private func saveRecipient() {
        let normalizedSavedRecipient = model.defaultRecipient
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedDraft = onboardingRecipientDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedDraft.isEmpty else {
            return
        }

        if onboardingRecipientConfirmed && normalizedDraft == normalizedSavedRecipient {
            return
        }

        model.setDefaultRecipient(onboardingRecipientDraft)
        onboardingRecipientDraft = model.defaultRecipient
        onboardingRecipientConfirmed = true
    }

    private func skip() {
        finish()
    }
}
