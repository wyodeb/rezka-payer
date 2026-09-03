//
//  DetailedMediaRezkaAPIResponse.swift
//  rezka-player
//
//  Created by Vitalii Parovishnyk on 12.10.2022.
//

import Foundation
import SwiftSoup
import OrderedCollections

struct DetailedMediaRezkaAPIResponse: Decodable {
    var detailedMedia: DetailedMedia
    
    init(from html: String) throws {
        let doc = try SwiftSoup.parse(html)
        let item = try doc.body()?.getElementById("main")?.getElementsByClass("b-content__main").first
        
        let mediaIdElement = try item?.getElementsByClass("b-userset__fav_holder").first
        let mediaId = try mediaIdElement?.attr("data-post_id") ?? "0"
        
        let title = try item?.getElementsByClass("b-post__title").first?.text() ?? ""
        let originalTitle = try item?.getElementsByClass("b-post__origtitle").first?.text() ?? ""
        
        var info: OrderedDictionary<String, String> = [:]
        let infoItems = try item?.getElementsByClass("b-post__info").first?.getElementsByTag("tr")
        try infoItems?.forEach({ infoLine in
            let items = try infoLine.getElementsByTag("td")
            if items.count == 2 {
                info[try items.first?.text() ?? ""] = try items.last?.text() ?? ""
            }
            else if let list = try infoLine.getElementsByClass("persons-list-holder").first {
                let spans = try list.getElementsByTag("span")
                let title = try spans.first?.text() ?? ""
                let index = title.index(title.startIndex, offsetBy: title.count)
                let persons = (try items.first?.text() ?? "")[index...]
                info[title] = String(persons)
            }
        })
        
        let defaultTranslation = info["В переводе:"] ?? ""
        
        let desc = try item?.getElementsByClass("b-post__description_text").last?.text() ?? ""
        
        let coverElement = try item?.getElementsByClass("b-sidecover").first
        
        let img = try coverElement?.getElementsByTag("img").first?.attr("src") ?? ""
        
        let (translation, premiumTranslations) = try DetailedMediaRezkaAPIResponse.translations(in: doc, default: defaultTranslation)

        detailedMedia = DetailedMedia(mediaId: Int(mediaId)!, title: title, titleOriginal: originalTitle, info: info, description: desc, translations: translation, premiumTranslations: premiumTranslations, seasons: [:], coverUrl: img)
    }

    private static func translations(in doc: Document, default translation: String) throws -> (OrderedDictionary<Int, String>, Set<Int>) {
        var translations: OrderedDictionary<Int, String> = [:]
        var premium: Set<Int> = []

        let scripts = try doc.getElementsByTag("script")

        scripts.forEach { element in
            let script = element.data()

            for search in ["initCDNSeriesEvents", "initCDNMoviesEvents"] {
                if let pos = script.firstRange(of: search) {
                    let startIndex = script.index(pos.upperBound, offsetBy: 1)
                    let components = String(script[startIndex...]).split(separator: ", ")
                    if components.count > 1, let id = Int(components[1]) {
                        translations[id] = translation
                        break
                    }
                }
            }
        }

        // The site serves at least two different markups for this list depending on
        // the title (confirmed against live pages, not guessed):
        //   <li><a title="Дубляж" class="b-translator__items" data-translator_id="56"
        //       ...>Дубляж</a></li>                              (e.g. Shawshank Redemption)
        //   <li title="Дубляж" class="b-translator__item" data-translator_id="56"
        //       ...>Дубляж</li>                                  (e.g. The Green Mile — no
        //                                                         nested <a> at all)
        // Rather than assume which tag/class carries the attributes, match any element
        // with a data-translator_id at all and read from that same element — works for
        // both variants. Matching only "b-translator__items" (as this code previously
        // did) reads title/data-translator_id off the childless <li> in the second
        // variant, always empty, silently collapsing every translator into one bogus
        // entry and falling back to the single combined-name entry from the info table.
        try doc.getElementById("translators-list")?.select("[data-translator_id]").forEach({ node in
            guard let id = Int(try node.attr("data-translator_id")) else { return }
            let title = try node.attr("title")

            translations[id] = title
            let isPremium = try node.hasClass("b-prem_translator") || (try node.parent()?.hasClass("b-prem_translator")) == true
            if isPremium {
                premium.insert(id)
            }
        })

        return (translations, premium)
    }
}
