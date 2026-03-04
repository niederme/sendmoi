import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focusedField: Field?
    @State private var desktopSelection: DesktopPanel = .overview

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
                .navigationTitle("MailMoi")
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

    private var compactMobileContent: some View {
        Form {
            accountSection
            defaultRecipientSection
            shareSheetSection
            queueSection
            statusMessageView
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

    private var attributionSection: some View {
        Section {
            EmptyView()
        } footer: {
            Text("MailMoi by John Niedermeyer, with a little help from Codex, Claude Code and friends.")
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
                Text("MailMoi")
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
            }
        case .preferences:
            VStack(alignment: .leading, spacing: 18) {
                desktopSectionIntro(
                    title: "Preferences",
                    subtitle: "Set the default recipient and decide how shared items behave before they hit the queue."
                )
                desktopPreferencesCard
                desktopStatusCard
            }
        case .compose:
            VStack(alignment: .leading, spacing: 18) {
                desktopSectionIntro(
                    title: "Compose",
                    subtitle: "Build the draft, enrich it with preview data, and queue it for delivery."
                )
                desktopComposeCard
                desktopStatusCard
            }
        case .queue:
            VStack(alignment: .leading, spacing: 18) {
                desktopSectionIntro(
                    title: "Offline Queue",
                    subtitle: "Items wait here when Gmail is unavailable and send automatically once the app can reach the network."
                )
                desktopQueueCard
                desktopStatusCard
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
                Text("MailMoi")
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
                Text("MailMoi")
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

    private var desktopAttribution: some View {
        Text("MailMoi by John Niedermeyer, with a little help from Codex, Claude Code and friends.")
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

#Preview {
    ContentView()
        .environmentObject(AppModel())
}
