import Foundation

enum SharedContainer {
    static let appGroupID = "group.com.niederme.sendmoi"
    private static let directoryName = "SendMoi"
    private static let sharedMediaDirectoryName = "SharedMedia"

    static func appDirectoryURL() throws -> URL {
        let fileManager = FileManager.default
        let baseURL = try preferredBaseURL(fileManager: fileManager)

        let appDirectory = baseURL.appendingPathComponent(directoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: appDirectory.path()) {
            try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }
        migrateLegacyApplicationSupportDirectoryIfNeeded(to: appDirectory, fileManager: fileManager)
        return appDirectory
    }

    static func storeSharedMedia(data: Data, fileExtension: String) throws -> URL {
        let sanitizedExtension = fileExtension
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .lowercased()
        let resolvedExtension = sanitizedExtension.isEmpty ? "jpg" : sanitizedExtension
        let fileURL = try sharedMediaDirectoryURL()
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension(resolvedExtension)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    static func removeManagedMediaIfPresent(urlString: String?) {
        guard isManagedMediaURLString(urlString),
              let urlString,
              let fileURL = URL(string: urlString) else {
            return
        }

        try? FileManager.default.removeItem(at: fileURL)
    }

    static func isManagedMediaURLString(_ urlString: String?) -> Bool {
        guard let urlString,
              let fileURL = URL(string: urlString),
              fileURL.isFileURL,
              let sharedMediaDirectoryURL = try? sharedMediaDirectoryURL().standardizedFileURL else {
            return false
        }

        let sharedMediaPath = sharedMediaDirectoryURL.path
        let filePath = fileURL.standardizedFileURL.path
        return filePath == sharedMediaPath || filePath.hasPrefix(sharedMediaPath + "/")
    }

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    private static func sharedMediaDirectoryURL() throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = try appDirectoryURL().appendingPathComponent(sharedMediaDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: directoryURL.path()) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL
    }

    private static func preferredBaseURL(fileManager: FileManager) throws -> URL {
        if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID),
           groupURL.path.contains("/Library/Group Containers/") {
            return groupURL
        }

        let manualGroupURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
            .appendingPathComponent(appGroupID, isDirectory: true)
        if fileManager.fileExists(atPath: manualGroupURL.path()) {
            return manualGroupURL
        }

        return try applicationSupportBaseURL(fileManager: fileManager)
    }

    private static func applicationSupportBaseURL(fileManager: FileManager) throws -> URL {
        try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    private static func migrateLegacyApplicationSupportDirectoryIfNeeded(to appDirectory: URL, fileManager: FileManager) {
        guard appDirectory.path.contains("/Library/Group Containers/") else {
            return
        }

        guard let legacyDirectory = try? applicationSupportBaseURL(fileManager: fileManager)
            .appendingPathComponent(directoryName, isDirectory: true),
            legacyDirectory.standardizedFileURL != appDirectory.standardizedFileURL,
            fileManager.fileExists(atPath: legacyDirectory.path()) else {
            return
        }

        let legacyContents = (try? fileManager.contentsOfDirectory(
            at: legacyDirectory,
            includingPropertiesForKeys: nil
        )) ?? []

        for legacyItem in legacyContents {
            let destination = appDirectory.appendingPathComponent(legacyItem.lastPathComponent, isDirectory: false)
            guard !fileManager.fileExists(atPath: destination.path()) else {
                continue
            }
            try? fileManager.moveItem(at: legacyItem, to: destination)
        }

        let remainingContents = (try? fileManager.contentsOfDirectory(
            at: legacyDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        if remainingContents.isEmpty {
            try? fileManager.removeItem(at: legacyDirectory)
        }
    }
}

enum SendRateLimiter {
    private static let storageKey = "send-rate-ledger"
    private static let elevatedSenderEmails: Set<String> = [
        // Add your Gmail address here to use the elevated tester limits.
    ]
    private static let productionPolicy = SendRateLimitPolicy(
        maxInFiveMinutes: 20,
        maxInHour: 50,
        maxInDay: 150
    )
    private static let elevatedPolicy = SendRateLimitPolicy(
        maxInFiveMinutes: 100,
        maxInHour: 250,
        maxInDay: 1_000
    )
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func validateSendAllowed(for session: GmailSession, now: Date = .now) throws {
        let senderKey = normalizedSenderKey(for: session)
        let policy = policy(for: senderKey)
        let ledger = loadLedger(pruningBefore: now)
        let events = ledger.eventsBySender[senderKey] ?? []
        let nextAllowedAt = blockedUntil(for: events, policy: policy, now: now)

        if let nextAllowedAt {
            let waitDescription = waitTimeDescription(from: now, until: nextAllowedAt)
            throw GmailAPIError.rateLimitExceeded(
                "SendMoi send limit reached for this account. Try again in \(waitDescription)."
            )
        }
    }

    static func recordSuccessfulSend(for session: GmailSession, now: Date = .now) {
        let senderKey = normalizedSenderKey(for: session)
        var ledger = loadLedger(pruningBefore: now)
        ledger.eventsBySender[senderKey, default: []].append(now)
        saveLedger(ledger)
    }

    private static func policy(for senderKey: String) -> SendRateLimitPolicy {
        elevatedSenderEmails.contains(senderKey) ? elevatedPolicy : productionPolicy
    }

    private static func normalizedSenderKey(for session: GmailSession) -> String {
        guard let emailAddress = session.emailAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !emailAddress.isEmpty else {
            return "unknown-sender"
        }
        return emailAddress
    }

    private static func blockedUntil(
        for events: [Date],
        policy: SendRateLimitPolicy,
        now: Date
    ) -> Date? {
        let candidates = [
            nextAllowedAt(
                for: events,
                limit: policy.maxInFiveMinutes,
                window: 300,
                now: now
            ),
            nextAllowedAt(
                for: events,
                limit: policy.maxInHour,
                window: 3_600,
                now: now
            ),
            nextAllowedAt(
                for: events,
                limit: policy.maxInDay,
                window: 86_400,
                now: now
            )
        ].compactMap { $0 }

        return candidates.max()
    }

    private static func nextAllowedAt(
        for events: [Date],
        limit: Int,
        window: TimeInterval,
        now: Date
    ) -> Date? {
        guard limit > 0 else {
            return now
        }

        let windowStart = now.addingTimeInterval(-window)
        let recentEvents = events
            .filter { $0 >= windowStart }
            .sorted()

        guard recentEvents.count >= limit else {
            return nil
        }

        let blockingIndex = recentEvents.count - limit
        return recentEvents[blockingIndex].addingTimeInterval(window)
    }

    private static func waitTimeDescription(from now: Date, until nextAllowedAt: Date) -> String {
        let seconds = max(60, Int(ceil(nextAllowedAt.timeIntervalSince(now))))

        if seconds < 3_600 {
            let minutes = Int(ceil(Double(seconds) / 60.0))
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }

        let hours = seconds / 3_600
        let remainingSeconds = seconds % 3_600
        let remainingMinutes = Int(ceil(Double(remainingSeconds) / 60.0))

        if remainingMinutes == 60 {
            let roundedHours = hours + 1
            return roundedHours == 1 ? "1 hour" : "\(roundedHours) hours"
        }

        if remainingMinutes == 0 {
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }

        let hourLabel = hours == 1 ? "1 hour" : "\(hours) hours"
        let minuteLabel = remainingMinutes == 1 ? "1 minute" : "\(remainingMinutes) minutes"
        return "\(hourLabel) \(minuteLabel)"
    }

    private static func loadLedger(pruningBefore now: Date) -> SendRateLedger {
        let ledger: SendRateLedger
        if let data = SharedContainer.sharedDefaults.data(forKey: storageKey),
           let decoded = try? decoder.decode(SendRateLedger.self, from: data) {
            ledger = decoded
        } else {
            ledger = SendRateLedger()
        }

        var prunedLedger = ledger
        prunedLedger.prune(before: now.addingTimeInterval(-86_400))
        return prunedLedger
    }

    private static func saveLedger(_ ledger: SendRateLedger) {
        guard let data = try? encoder.encode(ledger) else {
            return
        }

        SharedContainer.sharedDefaults.set(data, forKey: storageKey)
    }
}

private struct SendRateLimitPolicy {
    let maxInFiveMinutes: Int
    let maxInHour: Int
    let maxInDay: Int
}

private struct SendRateLedger: Codable {
    var eventsBySender: [String: [Date]] = [:]

    mutating func prune(before cutoff: Date) {
        eventsBySender = eventsBySender.reduce(into: [:]) { partialResult, entry in
            let recentEvents = entry.value.filter { $0 >= cutoff }
            if !recentEvents.isEmpty {
                partialResult[entry.key] = recentEvents
            }
        }
    }
}
