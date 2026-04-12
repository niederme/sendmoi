import SwiftUI

struct MacStatusHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SendMoi")
                    .font(.title3.weight(.semibold))

                Text("Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    accountPill
                    networkPill
                    queuePill
                }

                VStack(alignment: .trailing, spacing: 8) {
                    accountPill
                    HStack(spacing: 8) {
                        networkPill
                        queuePill
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial)
    }

    private var accountPill: some View {
        statusPill(
            title: "Account",
            value: model.session?.emailAddress ?? "Not Connected",
            systemImage: model.session == nil ? "person.crop.circle.badge.xmark" : "person.crop.circle.badge.checkmark",
            tint: model.session == nil ? .orange : .accentColor
        )
    }

    private var networkPill: some View {
        statusPill(
            title: "Network",
            value: model.isOnline ? "Online" : "Offline",
            systemImage: model.isOnline ? "wifi" : "wifi.slash",
            tint: model.isOnline ? .green : .orange
        )
    }

    private var queuePill: some View {
        let count = model.queuedEmails.count
        let hasIssue = model.requiresGmailReconnect || count > 0
        return statusPill(
            title: "Queue",
            value: count == 0 ? "Clear" : "\(count) waiting",
            systemImage: count == 0 ? "tray" : "tray.full",
            tint: hasIssue ? .orange : .secondary
        )
    }

    private func statusPill(
        title: String,
        value: String,
        systemImage: String,
        tint: Color = .accentColor
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.05))
        )
    }
}
