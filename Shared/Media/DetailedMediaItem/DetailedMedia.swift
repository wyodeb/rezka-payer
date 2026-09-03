//
//  DetailedMedia.swift
//  rezka-player
//
//  Created by Vitalii Parovishnyk on 12.10.2022.
//

import Foundation
import OrderedCollections

struct DetailedMedia {
    private(set) var id = UUID()
    
    let mediaId: Int
    
    let title: String
    let titleOriginal: String
    
    let info: OrderedDictionary<String, String>
    let description: String
    
    let translations: OrderedDictionary<Int, String>
    /// Translator ids the site marks premium-only (`b-prem_translator`). An account
    /// without an active subscription gets a superficially valid `success:true` CDN
    /// response for these, but the token is dead on arrival — so default translation
    /// selection should skip these rather than pick one blindly.
    let premiumTranslations: Set<Int>

    private(set) var seasons: [Int: SeasonsData] = [:]
    func seasons(in translation: Int) -> [Int: String]? {
        return seasons[translation]?.seasons
    }
    
    func episodesIn(in season: Int, translation: Int) -> [Episode]? {
        return seasons[translation]?.episodes[season]
    }
    
    let coverUrl: String
    
    mutating func setup(seasons: SeasonsData, for translation: Int) {
        self.seasons[translation] = seasons
    }

    /// The translation to default to: the first non-premium one, since a
    /// non-subscribed account can't actually play a premium translation even
    /// though the site's `get_cdn_series` endpoint reports `success:true` for
    /// it. Falls back to the first translation at all if every one is premium
    /// (rather than picking nothing) — the user can still switch manually.
    var preferredTranslationId: Int? {
        translations.keys.first { !premiumTranslations.contains($0) } ?? translations.keys.first
    }
}

extension DetailedMedia: Codable {}
extension DetailedMedia: Equatable {
    static func == (lhs: DetailedMedia, rhs: DetailedMedia) -> Bool {
        return lhs.id == rhs.id
    }
}
extension DetailedMedia: Identifiable {}

extension DetailedMedia {
    
    static var previewData: DetailedMedia {
        return DetailedMedia(mediaId: .zero, title: "", titleOriginal: "", info: [:], description: "", translations: [:], premiumTranslations: [], seasons: [:], coverUrl: "")
    }
}
