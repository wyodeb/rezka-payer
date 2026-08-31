//
//  RezkaHistorySync.swift
//  rezka-player
//

import Foundation
import SwiftSoup

/// Syncs watch progress against the signed-in HD Rezka account's own "Досмотреть"
/// (continue watching) list — the same one rezka.ag's website itself uses, reverse
/// engineered from their site JS (`ajax/send_save/`, `/continue/`,
/// `engine/ajax/cdn_saves_remove.php`).
///
/// The `/continue/` listing only exposes title/episode/date, not exact resume
/// seconds, so sync is asymmetric by necessity: precise position is pushed
/// one-way (device → Rezka, so their web player resumes correctly too), while
/// title/episode is merged both ways (if another device got further, this app
/// jumps to that episode; precise local seconds stay authoritative in-app).
struct RezkaHistorySync {

    struct RemoteEntry {
        let saveId: Int
        let media: Media
        let season: Int?
        let episode: Int?
    }

    static let shared = RezkaHistorySync()

    func pushProgress(rezkaMediaId: Int, translationId: Int, season: Int?, episode: Int?, currentTime: Double, duration: Double) async {
        guard RezkaAuthApi.isSignedIn else { return }
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        guard let url = URL(string: "\(RezkaConstantsApi.server)/ajax/send_save/?t=\(timestamp)") else { return }

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "post_id", value: "\(rezkaMediaId)"),
            URLQueryItem(name: "translator_id", value: "\(translationId)"),
            URLQueryItem(name: "season", value: "\(season ?? 0)"),
            URLQueryItem(name: "episode", value: "\(episode ?? 0)"),
            URLQueryItem(name: "current_time", value: "\(Int(currentTime))"),
            URLQueryItem(name: "duration", value: "\(Int(duration))"),
        ]

        var request = URLRequest(url: url)
        request.httpMethod = ApiConstants.HttpMethod.post.rawValue
        request.httpBody = components.query?.data(using: .utf8)
        request.setValue(ApiConstants.userAgent, forHTTPHeaderField: ApiConstants.userAgentKey)
        request.addValue(ApiConstants.formContentType, forHTTPHeaderField: ApiConstants.contentTypeKey)
        request.addValue(ApiConstants.AcceptTypeJson, forHTTPHeaderField: ApiConstants.AcceptTypeKey)

        _ = try? await RezkaHTTPClient.shared.send(request)
    }

    func removeRemoteSave(id: Int) async {
        guard RezkaAuthApi.isSignedIn,
              let url = URL(string: "\(RezkaConstantsApi.server)/engine/ajax/cdn_saves_remove.php") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = ApiConstants.HttpMethod.post.rawValue
        request.httpBody = "id=\(id)".data(using: .utf8)
        request.setValue(ApiConstants.userAgent, forHTTPHeaderField: ApiConstants.userAgentKey)
        request.addValue(ApiConstants.formContentType, forHTTPHeaderField: ApiConstants.contentTypeKey)

        _ = try? await RezkaHTTPClient.shared.send(request)
    }

    func fetchContinueWatching() async throws -> [RemoteEntry] {
        guard RezkaAuthApi.isSignedIn,
              let url = URL(string: "\(RezkaConstantsApi.server)/continue/") else { return [] }

        var request = URLRequest(url: url)
        request.setValue(ApiConstants.userAgent, forHTTPHeaderField: ApiConstants.userAgentKey)

        let (data, response) = try await RezkaHTTPClient.shared.send(request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return []
        }

        return try Self.parse(html: String(decoding: data, as: UTF8.self))
    }

    private static func parse(html: String) throws -> [RemoteEntry] {
        let document = try SwiftSoup.parse(html)
        let rows = try document.select("div.b-videosaves__list_item[id^=videosave-]")

        return try rows.array().compactMap { row -> RemoteEntry? in
            let idAttr = try row.attr("id")
            guard let saveId = Int(idAttr.replacingOccurrences(of: "videosave-", with: "")) else {
                return nil
            }

            guard let link = try row.select("div.td.title a").first() else { return nil }
            let href = try link.attr("href")
            let title = try link.text()
            let coverUrl = try link.attr("data-cover_url")

            guard !href.isEmpty, !coverUrl.isEmpty,
                  URL(string: href) != nil, URL(string: coverUrl) != nil else {
                return nil
            }

            let infoText = (try? row.select("div.td.info").first()?.text()) ?? ""
            let (season, episode) = parseSeasonEpisode(from: infoText)

            let media = Media(
                title: title,
                url: href,
                descriptionShort: "",
                description: nil,
                coverUrl: coverUrl,
                seriesInfo: season != nil ? infoText : nil,
                category: category(fromMediaURL: href),
                quality: .unknown
            )

            return RemoteEntry(saveId: saveId, media: media, season: season, episode: episode)
        }
    }

    private static func parseSeasonEpisode(from text: String) -> (season: Int?, episode: Int?) {
        guard let seasonRange = text.range(of: #"\d+\s*сезон"#, options: .regularExpression),
              let episodeRange = text.range(of: #"\d+\s*серия"#, options: .regularExpression) else {
            return (nil, nil)
        }
        let season = Int(text[seasonRange].filter(\.isNumber))
        let episode = Int(text[episodeRange].filter(\.isNumber))
        return (season, episode)
    }

    private static func category(fromMediaURL urlString: String) -> Category {
        guard let parsedURL = URL(string: urlString) else { return .general }
        let first = parsedURL.pathComponents.dropFirst().first ?? ""
        return Category(rawValue: first) ?? .general
    }
}
