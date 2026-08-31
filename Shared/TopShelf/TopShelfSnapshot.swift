//
//  TopShelfSnapshot.swift
//  rezka-player
//
//  Compiled into both the main app and the TopShelf extension. The app writes a
//  small "continue watching" snapshot here whenever history changes; the
//  extension (a separate process, can't see the app's own storage) reads it back
//  via the shared App Group container.
//

import Foundation

struct TopShelfItemSnapshot: Codable {
    let rezkaMediaId: Int
    let title: String
    let coverURLString: String
    let episodeLabel: String?
}

enum TopShelfStore {
    static let appGroupId = "group.com.sergiu.hdrezka"
    static let urlScheme = "hdrezka"

    private static let key = "topShelfContinueWatching"
    private static let maxItems = 10

    static func write(_ items: [TopShelfItemSnapshot]) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return }
        guard let data = try? JSONEncoder().encode(Array(items.prefix(maxItems))) else { return }
        defaults.set(data, forKey: key)
    }

    static func read() -> [TopShelfItemSnapshot] {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let data = defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([TopShelfItemSnapshot].self, from: data) else {
            return []
        }
        return items
    }

    static func deepLinkURL(forRezkaMediaId id: Int) -> URL? {
        URL(string: "\(urlScheme)://watch?id=\(id)")
    }

    static func rezkaMediaId(from url: URL) -> Int? {
        guard url.scheme == urlScheme, url.host == "watch",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let idString = components.queryItems?.first(where: { $0.name == "id" })?.value else {
            return nil
        }
        return Int(idString)
    }
}
