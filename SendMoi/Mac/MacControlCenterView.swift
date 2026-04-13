import SwiftUI

struct MacControlCenterView: View {
    @EnvironmentObject private var model: AppModel
    let openSetupGuide: () -> Void
    let showResetConfirmation: () -> Void

    private let sidebarWidth: CGFloat = 300
    private let columnSpacing: CGFloat = 16
    private let sidebarLayoutThreshold: CGFloat = 980

    var body: some View {
        VStack(spacing: 0) {
            MacStatusHeader()
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            GeometryReader { proxy in
                ScrollView {
                    if usesSidebarLayout(for: proxy.size.width) {
                        HStack(alignment: .top, spacing: columnSpacing) {
                            setupColumn
                                .frame(maxWidth: .infinity, alignment: .topLeading)

                            MacQueuePane()
                                .frame(width: sidebarWidth, alignment: .top)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            setupColumn
                            MacQueuePane()
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.02))
    }

    private var setupColumn: some View {
        MacSetupSidebar(
            openSetupGuide: openSetupGuide,
            showResetConfirmation: showResetConfirmation
        )
    }

    private func usesSidebarLayout(for width: CGFloat) -> Bool {
        width >= sidebarLayoutThreshold
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
                    statusMessage: "SendMoi retries automatically when the network and Gmail session are healthy.",
                    isOnline: true
                )
            )
            .frame(width: 640, height: 700)
            .previewDisplayName("With Queue")

            MacControlCenterView(
                openSetupGuide: {},
                showResetConfirmation: {}
            )
            .environmentObject(
                SendMoiPreviewFixtures.appModel(
                    queuedEmails: [],
                    defaultRecipient: "ideas@sendmoi.app",
                    shareSheetAutoSendEnabled: true,
                    session: SendMoiPreviewFixtures.connectedSession,
                    statusMessage: "Signed in as founder@sendmoi.app.",
                    isOnline: true
                )
            )
            .frame(width: 640, height: 560)
            .previewDisplayName("Settings Only")

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
            .frame(width: 640, height: 700)
            .previewDisplayName("Reconnect Required")
        }
    }
}
#endif
