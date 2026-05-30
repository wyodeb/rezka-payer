import SwiftUI

@MainActor
class WatchHistoryViewModel: ObservableObject {

    @Published private(set) var entries: [WatchHistoryEntry] = []
    private let store = PlistDataStore<[WatchHistoryEntry]>(filename: "watchhistory")

    static let shared = WatchHistoryViewModel()
    private init() {
        Task { await load() }
    }

    private func load() async {
        entries = await store.load() ?? []
    }

    func update(media: Media, currentTime: Double, duration: Double,
                season: Int? = nil, episode: Int? = nil, translationId: Int? = nil) {
        let entry = WatchHistoryEntry(
            media: media,
            currentTime: currentTime,
            duration: duration,
            updatedAt: Date(),
            season: season,
            episode: episode,
            translationId: translationId
        )

        if let idx = entries.firstIndex(where: { $0.media.id == media.id }) {
            entries[idx] = entry
        } else {
            entries.insert(entry, at: 0)
        }

        entries.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    func remove(media: Media) {
        entries.removeAll { $0.media.id == media.id }
        persist()
    }

    func entry(for media: Media) -> WatchHistoryEntry? {
        entries.first { $0.media.id == media.id }
    }

    private func persist() {
        let snapshot = entries
        Task { await store.save(snapshot) }
    }
}
