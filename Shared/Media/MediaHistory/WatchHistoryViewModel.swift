import SwiftUI

@MainActor
class WatchHistoryViewModel: ObservableObject {

    @Published private(set) var entries: [WatchHistoryEntry] = []
    private let store = PlistDataStore<[WatchHistoryEntry]>(filename: "watchhistory")

    /// Set when a Top Shelf tap deep-links into the app; observed by ContentView
    /// to present that title.
    @Published var pendingDeepLinkMedia: Media?

    static let shared = WatchHistoryViewModel()
    private init() {
        Task {
            await load()
            writeTopShelfSnapshot()
            await syncFromRemote()
        }
    }

    private func load() async {
        entries = await store.load() ?? []
    }

    /// Pulls the signed-in Rezka account's own "Досмотреть" list and merges it into
    /// local history: unknown titles are added, and titles where the account is
    /// further along (season/episode-wise, e.g. watched from another device) are
    /// advanced locally. See RezkaHistorySync for exactly what is and isn't synced.
    func syncFromRemote() async {
        guard RezkaAuthApi.isSignedIn,
              let remoteEntries = try? await RezkaHistorySync.shared.fetchContinueWatching() else { return }

        for remote in remoteEntries {
            guard remote.media.rezkaMediaId != nil else { continue }

            if let idx = entries.firstIndex(where: { $0.media.rezkaMediaId == remote.media.rezkaMediaId }) {
                entries[idx].remoteSaveId = remote.saveId

                if let remoteSeason = remote.season, let remoteEpisode = remote.episode,
                   let localSeason = entries[idx].season, let localEpisode = entries[idx].episode,
                   (remoteSeason, remoteEpisode) > (localSeason, localEpisode) {
                    entries[idx].season = remoteSeason
                    entries[idx].episode = remoteEpisode
                    entries[idx].currentTime = 0
                    entries[idx].duration = 0
                    entries[idx].updatedAt = Date()
                }
            } else {
                var newEntry = WatchHistoryEntry(
                    media: remote.media,
                    currentTime: 0,
                    duration: 0,
                    updatedAt: Date(),
                    season: remote.season,
                    episode: remote.episode,
                    translationId: nil
                )
                newEntry.remoteSaveId = remote.saveId
                entries.append(newEntry)
            }
        }

        entries.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    /// Forget which remote save ids our local entries correspond to — call this on
    /// sign-out so a later sign-in (possibly to a different account) doesn't delete
    /// or overwrite someone else's saves under stale ids.
    func clearRemoteAssociations() {
        for i in entries.indices { entries[i].remoteSaveId = nil }
        persist()
    }

    /// - Parameter nextEpisodeTarget: what comes after `season`/`episode`, if known
    ///   (from `DetailedMediaItemViewModel.nextEpisodeIdentifier`). Only consulted
    ///   when this update finishes the episode/movie: a finished movie is always
    ///   stripped from history; a finished series episode advances to this target
    ///   if given, otherwise (last episode of the series) it's stripped too.
    func update(media: Media, currentTime: Double, duration: Double,
                season: Int? = nil, episode: Int? = nil, translationId: Int? = nil,
                nextEpisodeTarget: (season: Int, episode: Int)? = nil) {
        let entry = WatchHistoryEntry(
            media: media,
            currentTime: currentTime,
            duration: duration,
            updatedAt: Date(),
            season: season,
            episode: episode,
            translationId: translationId
        )

        if entry.isFinished {
            if media.isSeries, let next = nextEpisodeTarget {
                applyAdvance(media: media, season: next.season, episode: next.episode, translationId: translationId)
            } else {
                removeLocally(media: media)
            }
            return
        }

        if let idx = entries.firstIndex(where: { $0.media.id == media.id }) {
            entries[idx].currentTime = currentTime
            entries[idx].duration = duration
            entries[idx].updatedAt = entry.updatedAt
            entries[idx].season = season
            entries[idx].episode = episode
            entries[idx].translationId = translationId
        } else {
            entries.insert(entry, at: 0)
        }

        entries.sort { $0.updatedAt > $1.updatedAt }
        persist()
        pushRemoteProgress(media: media, translationId: translationId, season: season, episode: episode, currentTime: currentTime, duration: duration)
    }

    func advanceEpisode(media: Media, season: Int, episode: Int, translationId: Int?) {
        applyAdvance(media: media, season: season, episode: episode, translationId: translationId)
    }

    func remove(media: Media) {
        removeLocally(media: media)
    }

    private func applyAdvance(media: Media, season: Int, episode: Int, translationId: Int?) {
        if let idx = entries.firstIndex(where: { $0.media.id == media.id }) {
            entries[idx].season = season
            entries[idx].episode = episode
            entries[idx].translationId = translationId
            entries[idx].currentTime = 0
            entries[idx].duration = 0
            entries[idx].updatedAt = Date()
        } else {
            let newEntry = WatchHistoryEntry(
                media: media,
                currentTime: 0,
                duration: 0,
                updatedAt: Date(),
                season: season,
                episode: episode,
                translationId: translationId
            )
            entries.insert(newEntry, at: 0)
        }

        entries.sort { $0.updatedAt > $1.updatedAt }
        persist()
        pushRemoteProgress(media: media, translationId: translationId, season: season, episode: episode, currentTime: 0, duration: 0)
    }

    private func removeLocally(media: Media) {
        if let remoteId = entries.first(where: { $0.media.id == media.id })?.remoteSaveId {
            Task { await RezkaHistorySync.shared.removeRemoteSave(id: remoteId) }
        }
        entries.removeAll { $0.media.id == media.id }
        persist()
    }

    private func pushRemoteProgress(media: Media, translationId: Int?, season: Int?, episode: Int?, currentTime: Double, duration: Double) {
        guard let rezkaMediaId = media.rezkaMediaId, let translationId else { return }
        Task {
            await RezkaHistorySync.shared.pushProgress(
                rezkaMediaId: rezkaMediaId,
                translationId: translationId,
                season: season,
                episode: episode,
                currentTime: currentTime,
                duration: duration
            )
        }
    }

    func entry(for media: Media) -> WatchHistoryEntry? {
        entries.first { $0.media.id == media.id }
    }

    /// Resolves a Top Shelf tap (`hdrezka://watch?id=<rezkaMediaId>`) against the
    /// titles we actually know about and, if found, hands it to ContentView to present.
    func handleDeepLink(url: URL) {
        guard let id = TopShelfStore.rezkaMediaId(from: url),
              let entry = entries.first(where: { $0.media.rezkaMediaId == id }) else { return }
        pendingDeepLinkMedia = entry.media
    }

    private func persist() {
        let snapshot = entries
        Task { await store.save(snapshot) }
        writeTopShelfSnapshot()
    }

    private func writeTopShelfSnapshot() {
        let items = entries.compactMap { entry -> TopShelfItemSnapshot? in
            guard let rezkaMediaId = entry.media.rezkaMediaId else { return nil }
            return TopShelfItemSnapshot(
                rezkaMediaId: rezkaMediaId,
                title: entry.media.title,
                coverURLString: entry.media.coverUrl,
                episodeLabel: entry.episodeLabel
            )
        }
        TopShelfStore.write(items)
    }
}
