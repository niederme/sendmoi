import Foundation

enum RecipientStore {
    private static let historyKey = "savedRecipients"
    private static let defaultKey = "defaultRecipient"
    private static let shareSheetAutoSendKey = "shareSheetAutoSendEnabled"
    private static let onboardingCompletedKey = "hasCompletedOnboarding"
    private static let analyticsEnabledKey = "analyticsEnabled"
    private static let legacyMigrationCompletedKey = "recipientStoreLegacyMigrationCompleted"
    private static let legacyAppGroupID = "group.com.niederme.mailmoi"
    private static let maxCount = 12

    static func load() -> [String] {
        migrateLegacyDefaultsIfNeeded()
        let defaults = SharedContainer.sharedDefaults
        defaults.synchronize()
        let values = defaults.array(forKey: historyKey) as? [String] ?? []
        return values
    }

    static func loadDefault() -> String {
        migrateLegacyDefaultsIfNeeded()
        let defaults = SharedContainer.sharedDefaults
        defaults.synchronize()
        return defaults.string(forKey: defaultKey) ?? ""
    }

    static func setDefault(_ recipient: String) {
        migrateLegacyDefaultsIfNeeded()
        let normalized = normalize(recipient)
        let defaults = SharedContainer.sharedDefaults
        defaults.set(normalized, forKey: defaultKey)
        defaults.synchronize()
        guard !normalized.isEmpty else {
            return
        }
        record(normalized)
    }

    static func loadShareSheetAutoSendEnabled() -> Bool {
        migrateLegacyDefaultsIfNeeded()
        let defaults = SharedContainer.sharedDefaults
        defaults.synchronize()
        if defaults.object(forKey: shareSheetAutoSendKey) == nil {
            return false
        }
        return defaults.bool(forKey: shareSheetAutoSendKey)
    }

    static func setShareSheetAutoSendEnabled(_ isEnabled: Bool) {
        migrateLegacyDefaultsIfNeeded()
        let defaults = SharedContainer.sharedDefaults
        defaults.set(isEnabled, forKey: shareSheetAutoSendKey)
        defaults.synchronize()
    }

    static func loadHasCompletedOnboarding() -> Bool {
        migrateLegacyDefaultsIfNeeded()
        let defaults = SharedContainer.sharedDefaults
        defaults.synchronize()
        return defaults.bool(forKey: onboardingCompletedKey)
    }

    static func setHasCompletedOnboarding(_ hasCompleted: Bool) {
        migrateLegacyDefaultsIfNeeded()
        let defaults = SharedContainer.sharedDefaults
        defaults.set(hasCompleted, forKey: onboardingCompletedKey)
        defaults.synchronize()
    }

    static func loadAnalyticsEnabled() -> Bool {
        let defaults = SharedContainer.sharedDefaults
        defaults.synchronize()
        guard defaults.object(forKey: analyticsEnabledKey) != nil else { return false }
        return defaults.bool(forKey: analyticsEnabledKey)
    }

    static func setAnalyticsEnabled(_ isEnabled: Bool) {
        let defaults = SharedContainer.sharedDefaults
        defaults.set(isEnabled, forKey: analyticsEnabledKey)
        defaults.synchronize()
    }

    static func resetSetup() {
        migrateLegacyDefaultsIfNeeded()
        let defaults = SharedContainer.sharedDefaults
        defaults.removeObject(forKey: historyKey)
        defaults.removeObject(forKey: defaultKey)
        defaults.removeObject(forKey: shareSheetAutoSendKey)
        defaults.removeObject(forKey: onboardingCompletedKey)
        defaults.removeObject(forKey: analyticsEnabledKey)
        defaults.synchronize()
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
        let defaults = SharedContainer.sharedDefaults
        defaults.set(current, forKey: historyKey)
        defaults.synchronize()
    }

    private static func normalize(_ recipient: String) -> String {
        recipient.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func migrateLegacyDefaultsIfNeeded() {
        let defaults = SharedContainer.sharedDefaults
        defaults.synchronize()
        if defaults.bool(forKey: legacyMigrationCompletedKey) {
            return
        }

        var didMutateDefaults = false

        let legacyCandidates = legacyDefaultsCandidates()
        if defaults.object(forKey: defaultKey) == nil,
           let legacyDefault = firstLegacyString(forKey: defaultKey, in: legacyCandidates) {
            defaults.set(normalize(legacyDefault), forKey: defaultKey)
            didMutateDefaults = true
        }

        if defaults.object(forKey: historyKey) == nil,
           let legacyHistory = firstLegacyStringArray(forKey: historyKey, in: legacyCandidates) {
            let normalized = legacyHistory
                .map(normalize)
                .filter { !$0.isEmpty }
            var seen = Set<String>()
            let unique = normalized.filter { seen.insert($0).inserted }
            defaults.set(Array(unique.prefix(maxCount)), forKey: historyKey)
            didMutateDefaults = true
        }

        if defaults.object(forKey: shareSheetAutoSendKey) == nil,
           let legacyAutoSend = firstLegacyBool(forKey: shareSheetAutoSendKey, in: legacyCandidates) {
            defaults.set(legacyAutoSend, forKey: shareSheetAutoSendKey)
            didMutateDefaults = true
        }

        if defaults.object(forKey: onboardingCompletedKey) == nil,
           let legacyOnboarding = firstLegacyBool(forKey: onboardingCompletedKey, in: legacyCandidates) {
            defaults.set(legacyOnboarding, forKey: onboardingCompletedKey)
            didMutateDefaults = true
        }

        defaults.set(true, forKey: legacyMigrationCompletedKey)
        didMutateDefaults = true

        if didMutateDefaults {
            defaults.synchronize()
        }
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
