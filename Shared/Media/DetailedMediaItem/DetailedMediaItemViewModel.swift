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
            
            guard let currentTranslationId = detailedMedia.translations.keys.first else {
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
