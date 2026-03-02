import Foundation

enum SharedContainer {
    static let appGroupID = "group.com.niederme.mailmoi"
    private static let directoryName = "MailMoi"
    private static let sharedMediaDirectoryName = "SharedMedia"
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
        if shouldUseAppGroup {
            return UserDefaults(suiteName: appGroupID) ?? .standard
        }
        return .standard
    }

    private static func sharedMediaDirectoryURL() throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = try appDirectoryURL().appendingPathComponent(sharedMediaDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: directoryURL.path()) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL
    }
}
