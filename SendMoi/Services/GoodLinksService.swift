import Foundation

enum GoodLinksError: LocalizedError {
    case disabled
    case notConfigured
    case invalidURL
    case invalidCallbackURL
    case openURLUnavailable
    case localAPIUnavailable
    case api(String)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "GoodLinks saving is turned off."
        case .notConfigured:
            return "Add the GoodLinks API address and token before saving to GoodLinks."
        case .invalidURL:
            return "GoodLinks needs a valid http or https URL."
        case .invalidCallbackURL:
            return "Could not build the GoodLinks save URL."
        case .openURLUnavailable:
            return "GoodLinks could not be opened on this device."
        case .localAPIUnavailable:
            return "Silent GoodLinks saving requires the local GoodLinks API on a Mac."
        case .api(let message):
            return message
        case .transport(let error):
            return error.localizedDescription
        }
    }
}

struct GoodLinksSettings: Equatable {
    var isEnabled: Bool
    var apiAddress: String
    var apiToken: String
    var tagsText: String
    var starred: Bool
    var read: Bool

    static let defaultAPIAddress = "http://localhost:9428"
    static let defaultTagsText = "sendmoi"

    var tags: [String] {
        Self.normalizedTags(from: tagsText)
    }

    static func normalizedTags(from tagsText: String) -> [String] {
        tagsText
            .split(whereSeparator: { character in
                character == "," || character.isWhitespace || character.isNewline
            })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { tag in
                tag.hasPrefix("#") ? String(tag.dropFirst()) : tag
            }
            .filter { !$0.isEmpty }
    }
}

enum GoodLinksSettingsStore {
    private static let enabledKey = "goodLinks.enabled"
    private static let apiAddressKey = "goodLinks.apiAddress"
    private static let apiTokenKey = "goodLinks.apiToken"
    private static let tagsKey = "goodLinks.tags"
    private static let tagsCustomizedKey = "goodLinks.tagsCustomized"
    private static let starredKey = "goodLinks.starred"
    private static let readKey = "goodLinks.read"

    static func load() -> GoodLinksSettings {
        let defaults = SharedContainer.sharedDefaults
        defaults.synchronize()
        let storedTagsText = defaults.string(forKey: tagsKey)
        let hasCustomizedTags = defaults.bool(forKey: tagsCustomizedKey)
        let resolvedTagsText: String
        if storedTagsText == nil ||
            (storedTagsText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true && !hasCustomizedTags) {
            resolvedTagsText = GoodLinksSettings.defaultTagsText
        } else {
            resolvedTagsText = storedTagsText ?? GoodLinksSettings.defaultTagsText
        }

        return GoodLinksSettings(
            isEnabled: defaults.bool(forKey: enabledKey),
            apiAddress: defaults.string(forKey: apiAddressKey) ?? GoodLinksSettings.defaultAPIAddress,
            apiToken: defaults.string(forKey: apiTokenKey) ?? "",
            tagsText: resolvedTagsText,
            starred: defaults.bool(forKey: starredKey),
            read: defaults.bool(forKey: readKey)
        )
    }

    static func save(_ settings: GoodLinksSettings) {
        let defaults = SharedContainer.sharedDefaults
        defaults.set(settings.isEnabled, forKey: enabledKey)
        defaults.set(settings.apiAddress.trimmingCharacters(in: .whitespacesAndNewlines), forKey: apiAddressKey)
        defaults.set(settings.apiToken.trimmingCharacters(in: .whitespacesAndNewlines), forKey: apiTokenKey)
        defaults.set(settings.tagsText.trimmingCharacters(in: .whitespacesAndNewlines), forKey: tagsKey)
        defaults.set(true, forKey: tagsCustomizedKey)
        defaults.set(settings.starred, forKey: starredKey)
        defaults.set(settings.read, forKey: readKey)
        defaults.synchronize()
    }

    static func reset() {
        let defaults = SharedContainer.sharedDefaults
        defaults.removeObject(forKey: enabledKey)
        defaults.removeObject(forKey: apiAddressKey)
        defaults.removeObject(forKey: apiTokenKey)
        defaults.removeObject(forKey: tagsKey)
        defaults.removeObject(forKey: tagsCustomizedKey)
        defaults.removeObject(forKey: starredKey)
        defaults.removeObject(forKey: readKey)
        defaults.synchronize()
    }
}

final class GoodLinksService {
    private let decoder = JSONDecoder()

    func testLocalAPI(settings: GoodLinksSettings) async throws {
        let url = try apiURL(settings: settings, path: "links", requiresEnabledSetting: false)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        request.setValue("Bearer \(settings.apiToken.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        _ = try await send(request)
    }

    func saveUsingLocalAPI(item: QueuedEmail, settings: GoodLinksSettings) async throws {
        let url = try apiURL(settings: settings, path: "links")
        let payload = GoodLinksSaveRequest(
            url: try validatedHTTPURLString(item.urlString),
            title: clipped(cleaned(item.title), limit: 200),
            summary: clipped(preferredSummary(from: item), limit: 400),
            tags: settings.tags.isEmpty ? nil : settings.tags,
            read: settings.read ? true : nil,
            starred: settings.starred ? true : nil
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("Bearer \(settings.apiToken.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        _ = try await send(request)
    }

    func saveUsingLocalAPI(job: GoodLinksSyncJob, settings: GoodLinksSettings) async throws {
        let url = try apiURL(settings: settings, path: "links", requiresEnabledSetting: false)
        let payload = GoodLinksSaveRequest(
            url: try validatedHTTPURLString(job.urlString),
            title: clipped(cleaned(job.title), limit: 200),
            summary: clipped(preferredSummary(summary: job.summary, excerpt: job.excerpt), limit: 400),
            tags: job.tags.isEmpty ? nil : job.tags,
            read: job.read ? true : nil,
            starred: job.starred ? true : nil
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("Bearer \(settings.apiToken.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        _ = try await send(request)
    }

    func callbackURL(item: QueuedEmail, settings: GoodLinksSettings) throws -> URL {
        var components = URLComponents()
        components.scheme = "goodlinks"
        components.host = "x-callback-url"
        components.path = "/save"

        var queryItems = [
            URLQueryItem(name: "quick", value: "1"),
            URLQueryItem(name: "url", value: try validatedHTTPURLString(item.urlString))
        ]

        let title = clipped(cleaned(item.title), limit: 200)
        if !title.isEmpty {
            queryItems.append(URLQueryItem(name: "title", value: title))
        }

        let summary = clipped(preferredSummary(from: item), limit: 400)
        if !summary.isEmpty {
            queryItems.append(URLQueryItem(name: "summary", value: summary))
        }

        if !settings.tags.isEmpty {
            queryItems.append(URLQueryItem(name: "tags", value: settings.tags.joined(separator: " ")))
        }

        if settings.starred {
            queryItems.append(URLQueryItem(name: "starred", value: "1"))
        }

        if settings.read {
            queryItems.append(URLQueryItem(name: "read", value: "1"))
        }

        components.queryItems = queryItems
        guard let url = components.url else {
            throw GoodLinksError.invalidCallbackURL
        }
        return url
    }

    private func apiURL(
        settings: GoodLinksSettings,
        path: String,
        requiresEnabledSetting: Bool = true
    ) throws -> URL {
        guard !requiresEnabledSetting || settings.isEnabled else {
            throw GoodLinksError.disabled
        }

        let address = settings.apiAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = settings.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, !token.isEmpty else {
            throw GoodLinksError.notConfigured
        }

        guard let baseURL = URL(string: address) else {
            throw GoodLinksError.notConfigured
        }

        return baseURL
            .appendingPathComponent("api", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
            .appendingPathComponent(path, isDirectory: false)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoodLinksError.api("GoodLinks returned an unexpected response.")
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                if let errorResponse = try? decoder.decode(GoodLinksAPIErrorResponse.self, from: data) {
                    throw GoodLinksError.api(errorResponse.error)
                }
                throw GoodLinksError.api("GoodLinks returned status \(httpResponse.statusCode).")
            }

            return data
        } catch let error as GoodLinksError {
            throw error
        } catch {
            throw GoodLinksError.transport(error)
        }
    }

    private func validatedHTTPURLString(_ urlString: String) throws -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw GoodLinksError.invalidURL
        }
        return trimmed
    }

    private func preferredSummary(from item: QueuedEmail) -> String {
        preferredSummary(summary: item.summary, excerpt: item.excerpt)
    }

    private func preferredSummary(summary: String?, excerpt: String) -> String {
        if let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return cleaned(summary)
        }
        return cleaned(excerpt)
    }

    private func cleaned(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func clipped(_ value: String, limit: Int) -> String {
        guard value.count > limit else {
            return value
        }
        return String(value.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct GoodLinksSaveRequest: Encodable {
    let url: String
    let title: String?
    let summary: String?
    let tags: [String]?
    let read: Bool?
    let starred: Bool?

    enum CodingKeys: String, CodingKey {
        case url
        case title
        case summary
        case tags
        case read
        case starred
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        if let title, !title.isEmpty {
            try container.encode(title, forKey: .title)
        }
        if let summary, !summary.isEmpty {
            try container.encode(summary, forKey: .summary)
        }
        if let tags, !tags.isEmpty {
            try container.encode(tags, forKey: .tags)
        }
        if let read {
            try container.encode(read, forKey: .read)
        }
        if let starred {
            try container.encode(starred, forKey: .starred)
        }
    }
}

private struct GoodLinksAPIErrorResponse: Decodable {
    let error: String
}
