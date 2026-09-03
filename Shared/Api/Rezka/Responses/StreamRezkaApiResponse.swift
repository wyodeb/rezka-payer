//
//  StreamRezkaApiResponse.swift
//  rezka-player
//
//  Created by Vitalii Parovishnyk on 23.10.2022.
//

import Foundation
import SwiftSoup

private struct StreamData: Codable {
    let success: Bool
    let message: String
    let url: String?
    let quality: String?
    let subtitle: String?
    let subtitlesList: [String: String]?
    let subtitleDefault: String?
    let thumbnails: String
    
    enum CodingKeys: String, CodingKey {
        case success, message, url, quality, subtitle
        case subtitlesList = "subtitle_lns"
        case subtitleDefault = "subtitle_def"
        case thumbnails
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        success = try values.decode(Bool.self, forKey: .success)
        message = try values.decode(String.self, forKey: .message)
        url = try? values.decode(String.self, forKey: .url) // Changed to try? for safety
        quality = try? values.decode(String.self, forKey: .quality) // absent when success == false
        subtitle = try? values.decode(String.self, forKey: .subtitle)
        subtitlesList = try? values.decode([String: String].self, forKey: .subtitlesList)
        subtitleDefault = try? values.decode(String.self, forKey: .subtitleDefault)
        thumbnails = (try? values.decode(String.self, forKey: .thumbnails)) ?? ""
    }
}

// MARK: - Seasons
struct StreamMedia: Codable {
    var bestQualityId: Media.Quality {
        if let p = p1080u, !p.isEmpty {
            return .p1080u
        } else if let p = p1080, !p.isEmpty {
            return .p1080
        } else if let p = p720, !p.isEmpty {
            return .p720
        } else if let p = p480, !p.isEmpty {
            return .p480
        } else if let p = p360, !p.isEmpty {
            return .p360
        } else {
            // FIXED: Removed assertion crash
            print("⚠️ No valid stream quality found in data.")
            return .unknown
        }
    }
    
    var bestQualityUrl: [String] {
        if let p = p1080u, !p.isEmpty {
            return p
        } else if let p = p1080, !p.isEmpty {
            return p
        } else if let p = p720, !p.isEmpty {
            return p
        } else if let p = p480, !p.isEmpty {
            return p
        } else if let p = p360, !p.isEmpty {
            return p
        } else {
            // FIXED: Removed assertion crash
            print("⚠️ No valid stream URL found in data.")
            return []
        }
    }
    
    var qualities: [Media.Quality]? {
        var qualities = [Media.Quality]()
        let list: [Media.Quality] = [.p1080u, .p1080, .p720, .p480, .p360]
        for q in list {
            if let _ = stream(q) {
                qualities.append(q)
            }
        }
        
        return qualities.isEmpty ? nil : qualities
    }
    
    private let p1080u: [String]?
    private let p1080: [String]?
    private let p720: [String]?
    private let p480: [String]?
    private let p360: [String]?
    
    init(p1080u: [String]? = nil, p1080: [String]? = nil, p720: [String]? = nil, p480: [String]? = nil, p360: [String]? = nil) {
        self.p1080u = p1080u
        self.p1080 = p1080
        self.p720 = p720
        self.p480 = p480
        self.p360 = p360
    }
    
    /// Priority order the site itself falls back through, highest quality first.
    static let qualityFallbackOrder: [Media.Quality] = [.p1080u, .p1080, .p720, .p480, .p360]

    func stream(_ quality: Media.Quality) -> String? {
        mirrors(quality).first
    }

    /// Every distinct CDN mirror URL the site offered for `quality` (e.g.
    /// voidcrystal.org, stream.voidboost.one, ...), in the order the site listed
    /// them. A single mirror's signed token can be dead for a given title/quality
    /// even though the others work, so playback should try each of these before
    /// giving up.
    ///
    /// Each real mirror is actually listed *twice* — once as an HLS URL
    /// (`.../file.mp4:hls:manifest.m3u8`) and once as the same token as a bare
    /// progressive `.../file.mp4` — not as independent fallbacks. The site's own
    /// reference client (github.com/SuperZombi/HdRezkaApi) only ever uses the
    /// plain `.mp4` form and discards the `:hls:` one outright, so that's almost
    /// certainly the one this CDN actually serves reliably; this collapses each
    /// pair down to that one entry instead of the HLS form we'd previously guessed at.
    func mirrors(_ quality: Media.Quality) -> [String] {
        let raw: [String]
        switch quality {
        case .p1080u: raw = p1080u ?? []
        case .p1080: raw = p1080 ?? []
        case .p720: raw = p720 ?? []
        case .p480: raw = p480 ?? []
        case .p360: raw = p360 ?? []
        case .unknown: raw = []
        }
        return Self.dedupedPreferringProgressiveMP4(raw)
    }

    private static func dedupedPreferringProgressiveMP4(_ urls: [String]) -> [String] {
        var order: [String] = []
        var chosen: [String: String] = [:]
        for url in urls {
            let key = url.replacingOccurrences(of: ":hls:manifest.m3u8", with: "")
            if chosen[key] == nil {
                order.append(key)
                chosen[key] = url
            } else if !url.contains(":hls:manifest.m3u8") {
                chosen[key] = url
            }
        }
        return order.compactMap { chosen[$0] }
    }

    /// The next quality down worth trying once every mirror of `quality` has failed.
    func nextLowerQuality(after quality: Media.Quality) -> Media.Quality? {
        guard let index = Self.qualityFallbackOrder.firstIndex(of: quality) else { return nil }
        return Self.qualityFallbackOrder[(index + 1)...].first { !mirrors($0).isEmpty }
    }
    
    func alternativeStream(_ quality: Media.Quality) -> String? {
        switch quality {
        case .p1080u:
            return p1080u?.last
        case .p1080:
            return p1080?.last
        case .p720:
            return p720?.last
        case .p480:
            return p480?.last
        case .p360:
            return p360?.last
        case .unknown:
            // FIXED: Removed assertion crash
            return nil
        }
    }
}

struct StreamRezkaApiResponse: Decodable {
    let streams: StreamMedia
    
    init(from dirtyBase64: String, isJson: Bool = false) throws {
        var cleanedBase64 = dirtyBase64

        if isJson {
            guard let data = dirtyBase64.data(using: .utf8) else {
                print("⚠️ Could not utf8-encode stream body.")
                throw DataError.generate(for: .rezkaConstantsApi, error: .mapping)
            }

            let object: StreamData
            do {
                object = try JSONDecoder().decode(StreamData.self, from: data)
            } catch {
                print("⚠️ Stream JSON decode failed: \(error)")
                throw DataError.generate(for: .rezkaConstantsApi, error: .mapping)
            }

            print("ℹ️ Stream JSON decoded: success=\(object.success) quality=\(object.quality) url.nil=\(object.url == nil) message=\(object.message)")

            guard let url = object.url, !url.isEmpty else {
                print("⚠️ Server message: \(object.message)")
                throw DataError.generate(for: .rezkaConstantsApi, error: .mapping)
            }

            cleanedBase64 = url
        }
        
        cleanedBase64 = cleanedBase64.replacing("#h", with: "")

        let trashList = ["@", "#", "!", "^", "$"]
        var trashItems = [String]()
        for symbol1 in trashList {
            for symbol2 in trashList {
                let trash1 = "\(symbol1)\(symbol2)".toBase64()
                trashItems.append(trash1)
            }
            for symbol2 in trashList {
                for symbol3 in trashList {
                    let trash2 = "\(symbol1)\(symbol2)\(symbol3)".toBase64()
                    trashItems.append(trash2)
                }
            }
        }

        cleanedBase64 = cleanedBase64.split(separator: "//_//").joined()

        trashItems.forEach { trash in
            cleanedBase64 = cleanedBase64.replacing(trash, with: "")
        }

        var p1080u: [String]?
        var p1080: [String]?
        var p720: [String]?
        var p480: [String]?
        var p360: [String]?

        // Detect the new plaintext format: starts with a quality tag like "[360p]".
        let looksLikePlaintext = cleanedBase64.range(of: "^\\s*\\[\\d+p", options: .regularExpression) != nil

        let decoded: String? = looksLikePlaintext ? cleanedBase64 : cleanedBase64.fromBase64()
        if looksLikePlaintext {
            print("ℹ️ Detected plaintext stream payload, skipping base64 decode.")
        }

        let streamsElements = decoded?.split(separator: ",")
        try? streamsElements?.forEach({ stream in
            let items = stream.split(separator: "]")
            let tempQuality = items.first ?? ""
            let tempStreams = items.last ?? ""
            
            var type: Media.Quality = .unknown
            let qualityComponents = tempQuality.split(separator: "[")
            if let quality = qualityComponents.last {
                type = Media.Quality(rawValue: String(quality)) ?? .unknown
            }
            
            guard type != .unknown else {
                // This will still throw a data error for the UI to handle, but won't hard crash the app
                throw DataError.generate(for: .streamRezkaApi, error: .unknownStreamQuality)
            }
            
            let urls = tempStreams.split(separator: " or ").compactMap { String($0) }
            
            switch type {
            case .p1080u:
                p1080u = urls
            case .p1080:
                p1080 = urls
            case .p720:
                p720 = urls
            case .p480:
                p480 = urls
            case .p360:
                p360 = urls
            case .unknown:
                break
            }
        })
        
        let counts = "p1080u=\(p1080u?.count ?? 0) p1080=\(p1080?.count ?? 0) p720=\(p720?.count ?? 0) p480=\(p480?.count ?? 0) p360=\(p360?.count ?? 0)"
        print("ℹ️ Parsed stream qualities: \(counts)")
        if let first480 = p480?.first {
            print("ℹ️ FULL p480 URL[0]: \(first480)")
        }
        if let first360 = p360?.first {
            print("ℹ️ FULL p360 URL[0]: \(first360)")
        }
        if (p1080u ?? []).isEmpty && (p1080 ?? []).isEmpty && (p720 ?? []).isEmpty && (p480 ?? []).isEmpty && (p360 ?? []).isEmpty {
            print("⚠️ After cleanup the payload yielded zero qualities. First 300 chars of cleanedBase64: \(String(cleanedBase64.prefix(300)))")
        }

        self.streams = StreamMedia(p1080u: p1080u, p1080: p1080, p720: p720, p480: p480, p360: p360)
    }
}
