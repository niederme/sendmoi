import SwiftUI

struct MacStatusHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Text("SendMoi")
            .font(.title2.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.thinMaterial)
    }

    private var accountPill: some View {
        statusPill(
            title: "Account",
            value: model.session?.emailAddress ?? "Not Connected",
            systemImage: accountSystemImage,
            tint: accountTint
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

    private var accountSystemImage: String {
        if model.requiresGmailReconnect {
            return "exclamationmark.triangle.fill"
        }
        return model.session == nil ? "person.crop.circle.badge.xmark" : "person.crop.circle.badge.checkmark"
    }

    private var accountTint: Color {
        if model.requiresGmailReconnect || model.session == nil {
            return .orange
        }
        return .accentColor
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
