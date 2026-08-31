//
//  Media.swift
//  rezka-player
//
//  Created by Vitalii Parovishnyk on 18.08.2022.
//

import Foundation
import CryptoKit

let activityTypeViewKey = "com.rezka-player.media.view"
let activityURLKey = "media.url.key"

struct Media {
    enum Quality: String, Codable {
        case p1080u = "1080p Ultra"
        case p1080 = "1080p"
        case p720 = "720p"
        case p480 = "480p"
        case p360 = "360p"
        case unknown
    }

    /// Derived from `url` rather than random, so the same title parsed from two
    /// different listings (search vs. category vs. history) resolves to the same
    /// identity — watch history, bookmarks, and Rezka-account sync all match on this.
    var id: UUID {
        let digest = SHA256.hash(data: Data(url.utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    let title: String
    let url: String
    let descriptionShort: String
    let description: String?
    let coverUrl: String
    let seriesInfo: String?
    let category: Category
    let quality: Quality
    
    var descriptionText: String {
        descriptionShort
    }
    
    var mediaURL: URL {
        URL(string: url)!
    }
    
    var coverURL: URL {
        URL(string: coverUrl)!
    }
    
    var isSeries: Bool {
        seriesInfo != nil
    }
}

extension Media: Codable {}
extension Media: Equatable {}
extension Media: Identifiable {}

extension Media {
    /// Country tokens that, when present in a card's descriptor, mark the item as Russian/USSR origin.
    /// HD Rezka's listing puts the country into `descriptionShort` ("year, country · genres").
    static let blockedCountryTokens: [String] = [
        "Россия", "России", "РФ",
        "СССР",
        "Russia", "Russian Federation",
        "USSR", "Soviet Union"
    ]

    var isFromBlockedCountry: Bool {
        let haystack = descriptionShort.lowercased()
        return Media.blockedCountryTokens.contains { token in
            haystack.contains(token.lowercased())
        }
    }
}

extension Media {
    /// HD Rezka's own numeric post id, e.g. "1843" out of ".../1843-griffiny-1999-latest.html".
    /// This is the `post_id` their account-sync endpoints (send_save, continue-watching) key on.
    var rezkaMediaId: Int? {
        guard let parsedURL = URL(string: url) else { return nil }
        let digits = parsedURL.lastPathComponent.prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }
}

enum MediaFilter {
    static let hideRuKey = "hideRuContent"

    static var hideRuContent: Bool {
        UserDefaults.standard.object(forKey: hideRuKey) as? Bool ?? true
    }
}

extension Media {
    
    static var previewData: [Media] {
        let previewDataURL = Bundle.main.url(forResource: "medias", withExtension: "json")!
        let data = try! Data(contentsOf: previewDataURL)
        
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
        
        let apiResponse = try! jsonDecoder.decode(MediaRezkaAPIResponse.self, from: data)
        return apiResponse.medias
    }
    
    static var previewCategoryArticles: [CategoryMedias] {
        let articles = previewData
        return Category.allCases.map {
            .init(category: $0, articles: articles.shuffled())
        }
    }
}
