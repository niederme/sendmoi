import Foundation

enum RecipientStore {
    private static let historyKey = "savedRecipients"
    private static let defaultKey = "defaultRecipient"
    private static let shareSheetAutoSendKey = "shareSheetAutoSendEnabled"
    private static let onboardingCompletedKey = "hasCompletedOnboarding"
    private static let legacyMigrationCompletedKey = "recipientStoreLegacyMigrationCompleted"
    private static let legacyAppGroupID = "group.com.niederme.mailmoi"
    private static let maxCount = 12

    static func load() -> [String] {
        migrateLegacyDefaultsIfNeeded()
        let values = SharedContainer.sharedDefaults.array(forKey: historyKey) as? [String] ?? []
        return values
    }

    static func loadDefault() -> String {
        migrateLegacyDefaultsIfNeeded()
        return SharedContainer.sharedDefaults.string(forKey: defaultKey) ?? ""
    }

    static func setDefault(_ recipient: String) {
        migrateLegacyDefaultsIfNeeded()
        let normalized = normalize(recipient)
        SharedContainer.sharedDefaults.set(normalized, forKey: defaultKey)
        guard !normalized.isEmpty else {
            return
        }
        record(normalized)
    }

    static func loadShareSheetAutoSendEnabled() -> Bool {
        migrateLegacyDefaultsIfNeeded()
        let defaults = SharedContainer.sharedDefaults
        if defaults.object(forKey: shareSheetAutoSendKey) == nil {
            return false
        }
        return defaults.bool(forKey: shareSheetAutoSendKey)
    }

    static func setShareSheetAutoSendEnabled(_ isEnabled: Bool) {
        migrateLegacyDefaultsIfNeeded()
        SharedContainer.sharedDefaults.set(isEnabled, forKey: shareSheetAutoSendKey)
    }

    static func loadHasCompletedOnboarding() -> Bool {
        migrateLegacyDefaultsIfNeeded()
        return SharedContainer.sharedDefaults.bool(forKey: onboardingCompletedKey)
    }

    static func setHasCompletedOnboarding(_ hasCompleted: Bool) {
        migrateLegacyDefaultsIfNeeded()
        SharedContainer.sharedDefaults.set(hasCompleted, forKey: onboardingCompletedKey)
    }

    static func resetSetup() {
        migrateLegacyDefaultsIfNeeded()
        let defaults = SharedContainer.sharedDefaults
        defaults.removeObject(forKey: historyKey)
        defaults.removeObject(forKey: defaultKey)
        defaults.removeObject(forKey: shareSheetAutoSendKey)
        defaults.removeObject(forKey: onboardingCompletedKey)
    }

    static func record(_ recipient: String) {
        migrateLegacyDefaultsIfNeeded()
        let normalized = normalize(recipient)
        guard !normalized.isEmpty else {
            return
        }

        var current = load().filter { $0 != normalized }
        current.insert(normalized, at: 0)
        current = Array(current.prefix(maxCount))
        SharedContainer.sharedDefaults.set(current, forKey: historyKey)
    }

    private static func normalize(_ recipient: String) -> String {
        recipient.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func migrateLegacyDefaultsIfNeeded() {
        let defaults = SharedContainer.sharedDefaults
        if defaults.bool(forKey: legacyMigrationCompletedKey) {
            return
        }

        let legacyCandidates = legacyDefaultsCandidates()
        if defaults.object(forKey: defaultKey) == nil,
           let legacyDefault = firstLegacyString(forKey: defaultKey, in: legacyCandidates) {
            defaults.set(normalize(legacyDefault), forKey: defaultKey)
        }

        if defaults.object(forKey: historyKey) == nil,
           let legacyHistory = firstLegacyStringArray(forKey: historyKey, in: legacyCandidates) {
            let normalized = legacyHistory
                .map(normalize)
                .filter { !$0.isEmpty }
            var seen = Set<String>()
            let unique = normalized.filter { seen.insert($0).inserted }
            defaults.set(Array(unique.prefix(maxCount)), forKey: historyKey)
        }

        if defaults.object(forKey: shareSheetAutoSendKey) == nil,
           let legacyAutoSend = firstLegacyBool(forKey: shareSheetAutoSendKey, in: legacyCandidates) {
            defaults.set(legacyAutoSend, forKey: shareSheetAutoSendKey)
        }

        if defaults.object(forKey: onboardingCompletedKey) == nil,
           let legacyOnboarding = firstLegacyBool(forKey: onboardingCompletedKey, in: legacyCandidates) {
            defaults.set(legacyOnboarding, forKey: onboardingCompletedKey)
        }

        defaults.set(true, forKey: legacyMigrationCompletedKey)
    }

    private static func legacyDefaultsCandidates() -> [UserDefaults] {
        var candidates: [UserDefaults] = []
        if let legacyAppGroupDefaults = UserDefaults(suiteName: legacyAppGroupID) {
            candidates.append(legacyAppGroupDefaults)
        }
        candidates.append(.standard)
        return candidates
    }

    private static func firstLegacyString(forKey key: String, in candidates: [UserDefaults]) -> String? {
        candidates
            .compactMap { $0.string(forKey: key) }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func firstLegacyStringArray(forKey key: String, in candidates: [UserDefaults]) -> [String]? {
        candidates
            .compactMap { $0.array(forKey: key) as? [String] }
            .first { !$0.isEmpty }
    }

    private static func firstLegacyBool(forKey key: String, in candidates: [UserDefaults]) -> Bool? {
        candidates
            .first(where: { $0.object(forKey: key) != nil })
            .map { $0.bool(forKey: key) }
    }
}
