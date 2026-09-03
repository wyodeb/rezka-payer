//
//  DetailedMediaItemViewModel.swift
//  rezka-player
//
//  Created by Vitalii Parovishnyk on 12.10.2022.
//

import SwiftUI
import OrderedCollections

@MainActor
class DetailedMediaItemViewModel: ObservableObject {
    
    @Published var phase = DataFetchPhase<DetailedMedia>.fetching
    @Published private(set) var isFetching = true
    
    private let rezkaAPI = MediaRezkaApi()
    
    private let cache: DiskCache<[DetailedMedia]> = .init(filename: "xcadmediacache", expirationInterval: 5 * 60)
    
    let media: Media
    private let placeholderDetailedMedia: DetailedMedia
    private var detailedMedia: DetailedMedia {
        phase.value ?? placeholderDetailedMedia
    }
    
    init(media: Media) {
        self.media = media
        self.placeholderDetailedMedia = DetailedMedia(
            mediaId: 0,
            title: media.title,
            titleOriginal: "",
            info: [:],
            description: media.description ?? media.descriptionShort,
            translations: [:],
            premiumTranslations: [],
            seasons: [:],
            coverUrl: media.coverUrl
        )
    }
    
    var title: String {
        detailedMedia.title
    }
    
    var originalTitle: String {
        detailedMedia.titleOriginal
    }
    
    var coverUrl: URL? {
        URL(string: detailedMedia.coverUrl)
    }
    
    var info: OrderedDictionary<String, String> {
        detailedMedia.info
    }
    
    var description: String {
        detailedMedia.description
    }
    
    private(set) var currentTranslation = 0
    
    var currentTranslationTitle: String? {
        detailedMedia.translations.isEmpty == false ? detailedMedia.translations[currentTranslation] : nil
    }
    
    private(set) var currentSeason: Int?
    var currentSeasonTitle: String {
        guard let currentSeason = currentSeason else {
            return "-"
        }
        
        return season?.seasons[currentSeason] ?? "-"
    }
    
    var seasonsInCurrentTranslation: [Int: String]? {
        return detailedMedia.seasons(in: currentTranslation)
    }
    
    private(set) var currentEpisode: Int?
    var currentEpisodeTitle: String {
        episode?.title ?? "-"
    }
    
    private(set) var currentQuality = Media.Quality.unknown
    
    func setQuality(_ quality: Media.Quality) {
        currentQuality = quality
        phase = .success(detailedMedia)
    }
    
    private(set) var streams: StreamMedia?
    var stream: String {
        streams?.stream(currentQuality) ?? ""
    }

    /// Every CDN mirror for the current quality, in fallback order. Used by the
    /// player to retry a dead mirror/token instead of failing outright.
    func streamMirrors(startingAt quality: Media.Quality? = nil) -> [String] {
        streams?.mirrors(quality ?? currentQuality) ?? []
    }

    func nextLowerQuality(after quality: Media.Quality) -> Media.Quality? {
        streams?.nextLowerQuality(after: quality)
    }
    
    func loadDetailedMedia() async {
        if Task.isCancelled { return }
        if let medias = await cache.value(forKey: "detailed_media_\(media.id)"), let media = medias.first {
            phase = .success(media)
        } else {
            phase = .fetching
        }
        
        await loadData()
    }
    
    private func loadData() async {
        isFetching = true
        do {
            let detailedMedia = try await rezkaAPI.fetchDetails(from: media)
            if Task.isCancelled { return }
            
            guard let currentTranslationId = detailedMedia.preferredTranslationId else {
                phase = .failure(DataError.generate(for: .rezkaConstantsApi, error: .empty))
                return
            }
            
            let savedEntry = WatchHistoryViewModel.shared.entry(for: media)

            if media.isSeries {
                currentSeason = savedEntry?.season ?? 1
                currentEpisode = savedEntry?.episode ?? 1
            }

            phase = .success(detailedMedia)

            let translationToUse = savedEntry?.translationId ?? currentTranslationId
            let resolvedTranslation = detailedMedia.translations.keys.contains(translationToUse) ? translationToUse : currentTranslationId
            try? await setCurrentTranslation(id: resolvedTranslation, mediaId: detailedMedia.mediaId)

            await cache.setValue([detailedMedia], forKey: "detailed_media_\(media.id)")
            try? await cache.saveToDisk()

            isFetching = false
            
        } catch {
            if Task.isCancelled { return }
            phase = .failure(error)
            isFetching = false
        }
    }
    
    var translations: OrderedDictionary<Int, String> {
        detailedMedia.translations
    }

    func isPremiumTranslation(_ id: Int) -> Bool {
        detailedMedia.premiumTranslations.contains(id)
    }
    
    var season: SeasonsData? {
        detailedMedia.seasons[currentTranslation]
    }
    
    var episodes: [Episode]? {
        guard let currentSeason = currentSeason else {
            return nil
        }
        
        return season?.episodes[currentSeason]
    }
    
    var episode: Episode? {
        episodes?.first{ $0.id == currentEpisode }
    }
    
    func setCurrentTranslation(id: Int, mediaId: Int? = nil) async throws {
        currentTranslation = id
        
        try await updateStreams(of: mediaId ?? detailedMedia.mediaId)
        phase = .success(detailedMedia)
    }
    
    func setCurrentSeason(id: Int) async throws {
        currentSeason = id
        
        try await updateStreams(of: detailedMedia.mediaId)
        
        phase = .success(detailedMedia)
    }
    
    func setCurrentEpisode(id: Int) async throws {
        currentEpisode = id
        
        try await updateStreams(of: detailedMedia.mediaId)
        
        phase = .success(detailedMedia)
    }
    
    /// Re-fetches the current translation/quality's stream token without the signed-in
    /// account attached — a fallback for once a normal (logged-in) fetch's URLs have
    /// actually failed to play, not tried up front, so registered-only perks like 4K
    /// stay available whenever the logged-in fetch does work. Returns whether it
    /// produced any playable mirror at all.
    func refetchStreamAnonymously() async -> Bool {
        guard let refetched = try? await rezkaAPI.stream(
            mediaId: detailedMedia.mediaId,
            translationId: currentTranslation,
            season: currentSeason,
            episode: currentEpisode,
            anonymous: true
        ) else { return false }

        streams = refetched
        let available = refetched.qualities ?? []
        if currentQuality == .unknown || !available.contains(currentQuality) {
            currentQuality = refetched.bestQualityId
        }
        return !streamMirrors().isEmpty
    }

    private func updateStreams(of mediaId: Int) async throws {
        streams = try await rezkaAPI.stream(mediaId: mediaId, translationId: currentTranslation, season: currentSeason, episode: currentEpisode)

        let available = streams?.qualities ?? []
        if currentQuality == .unknown || !available.contains(currentQuality) {
            currentQuality = streams?.bestQualityId ?? .unknown
        }
    }

    // MARK: - Series auto-advance

    var hasNextEpisode: Bool {
        nextEpisodeTarget() != nil
    }

    /// Season/episode of what comes after the currently-selected episode, if any —
    /// exposed so callers (e.g. saving watch history on player dismiss) can advance
    /// or strip a finished entry without duplicating season/episode-list traversal.
    var nextEpisodeIdentifier: (season: Int, episode: Int)? {
        nextEpisodeTarget().map { (season: $0.season, episode: $0.episodeId) }
    }

    @discardableResult
    func advanceToNextEpisode() async throws -> Bool {
        guard let target = nextEpisodeTarget() else { return false }
        if target.season != currentSeason {
            currentSeason = target.season
        }
        try await setCurrentEpisode(id: target.episodeId)
        return true
    }

    private func nextEpisodeTarget() -> (season: Int, episodeId: Int)? {
        guard media.isSeries,
              let currentSeason = currentSeason,
              let currentEpisode = currentEpisode,
              let seasonData = season else { return nil }

        if let eps = seasonData.episodes[currentSeason],
           let idx = eps.firstIndex(where: { $0.id == currentEpisode }),
           idx + 1 < eps.count {
            return (currentSeason, eps[idx + 1].id)
        }

        let seasonKeys = seasonData.seasons.keys.sorted()
        if let curIdx = seasonKeys.firstIndex(of: currentSeason),
           curIdx + 1 < seasonKeys.count {
            let nextSeason = seasonKeys[curIdx + 1]
            if let first = seasonData.episodes[nextSeason]?.first {
                return (nextSeason, first.id)
            }
        }
        return nil
    }
}
