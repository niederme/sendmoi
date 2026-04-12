import SwiftUI

struct MacControlCenterView: View {
    @EnvironmentObject private var model: AppModel
    let openSetupGuide: () -> Void
    let showResetConfirmation: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            MacStatusHeader()
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            contentSplit
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.02))
    }

    private var contentSplit: some View {
        Group {
            if model.queuedEmails.isEmpty {
                HStack(spacing: 0) {
                    MacSetupSidebar(
                        openSetupGuide: openSetupGuide,
                        showResetConfirmation: showResetConfirmation,
                        preferredMaxContentWidth: 420
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    Divider()

                    MacQueuePane()
                        .frame(width: 320)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                HStack(spacing: 0) {
                    MacQueuePane()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    Divider()

                    MacSetupSidebar(
                        openSetupGuide: openSetupGuide,
                        showResetConfirmation: showResetConfirmation
                    )
                    .frame(width: 340)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }
}

#if DEBUG
@MainActor
private struct MacControlCenterView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MacControlCenterView(
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
            .frame(width: 1120, height: 720)
            .previewDisplayName("Healthy Queue")

            MacControlCenterView(
                openSetupGuide: {},
                showResetConfirmation: {}
            )
            .environmentObject(
                SendMoiPreviewFixtures.appModel(
                    queuedEmails: SendMoiPreviewFixtures.reconnectQueue,
                    defaultRecipient: "reading@sendmoi.app",
                    shareSheetAutoSendEnabled: false,
                    session: SendMoiPreviewFixtures.connectedSession,
                    statusMessage: "Reconnect Gmail to restore send permission. Queued items will send after you reconnect.",
                    isOnline: false,
                    requiresGmailReconnect: true
                )
            )
            .frame(width: 1120, height: 720)
            .previewDisplayName("Reconnect Required")
        }
    }
}
#endif
