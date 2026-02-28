import Foundation

enum SharedContainer {
    static let appGroupID = "group.com.niederme.mailmoi"
    private static let directoryName = "MailMoi"
    private static var isExtensionProcess: Bool {
        Bundle.main.bundleURL.pathExtension == "appex"
    }

    private static var shouldUseAppGroup: Bool {
        #if os(macOS)
        return isExtensionProcess
        #else
        return true
        #endif
    }

    static func appDirectoryURL() throws -> URL {
        let fileManager = FileManager.default
        let baseURL: URL
        if shouldUseAppGroup,
           let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            baseURL = groupURL
        } else {
            baseURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }

        let appDirectory = baseURL.appendingPathComponent(directoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: appDirectory.path()) {
            try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }
        return appDirectory
    }

    static var sharedDefaults: UserDefaults {
        if shouldUseAppGroup {
            return UserDefaults(suiteName: appGroupID) ?? .standard
        }
        return .standard
    }
}
