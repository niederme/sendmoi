import SwiftUI

struct MacStatusHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SendMoi")
                        .font(.title3.weight(.semibold))

                    Text("Control Center")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        statusPill(
                            title: "Account",
                            value: accountStatus,
                            systemImage: model.session == nil ? "person.crop.circle.badge.xmark" : "person.crop.circle.badge.checkmark"
                        )

                        statusPill(
                            title: "Network",
                            value: model.isOnline ? "Online" : "Offline",
                            systemImage: model.isOnline ? "wifi" : "wifi.slash",
                            tint: model.isOnline ? .green : .orange
                        )

                        statusPill(
                            title: "Queue",
                            value: "\(model.queuedEmails.count) queued",
                            systemImage: "tray.full"
                        )
                    }

                    VStack(alignment: .trailing, spacing: 8) {
                        statusPill(
                            title: "Account",
                            value: accountStatus,
                            systemImage: model.session == nil ? "person.crop.circle.badge.xmark" : "person.crop.circle.badge.checkmark"
                        )

                        HStack(spacing: 8) {
                            statusPill(
                                title: "Network",
                                value: model.isOnline ? "Online" : "Offline",
                                systemImage: model.isOnline ? "wifi" : "wifi.slash",
                                tint: model.isOnline ? .green : .orange
                            )

                            statusPill(
                                title: "Queue",
                                value: "\(model.queuedEmails.count) queued",
                                systemImage: "tray.full"
                            )
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                if model.requiresGmailReconnect {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                Text(model.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(model.requiresGmailReconnect ? .orange : .secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial)
    }

    private var accountStatus: String {
        model.session?.emailAddress ?? "Not Connected"
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
