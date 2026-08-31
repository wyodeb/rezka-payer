//
//  TopShelfContentProvider.swift
//  RezkaTopShelf
//
//  Focus the app's icon on the tvOS Home Screen and this renders — same idea as
//  Plex/Apple TV's "Continue Watching" shelf. Reads the snapshot the main app
//  writes to the shared App Group container (this extension runs as its own
//  process and can't see the app's own on-disk history).
//

import TVServices

class TopShelfContentProvider: TVTopShelfContentProvider {

    override func loadTopShelfContent() async -> TVTopShelfContent? {
        let snapshots = TopShelfStore.read()
        guard !snapshots.isEmpty else { return nil }

        let items: [TVTopShelfSectionedItem] = snapshots.compactMap { snapshot in
            guard let deepLink = TopShelfStore.deepLinkURL(forRezkaMediaId: snapshot.rezkaMediaId) else {
                return nil
            }

            let item = TVTopShelfSectionedItem(identifier: "\(snapshot.rezkaMediaId)")
            item.title = snapshot.episodeLabel.map { "\(snapshot.title) — \($0)" } ?? snapshot.title
            if let coverURL = URL(string: snapshot.coverURLString) {
                item.setImageURL(coverURL, for: .screenScale1x)
                item.setImageURL(coverURL, for: .screenScale2x)
            }
            item.imageShape = .poster
            item.displayAction = TVTopShelfAction(url: deepLink)
            item.playAction = TVTopShelfAction(url: deepLink)
            return item
        }

        guard !items.isEmpty else { return nil }

        let collection = TVTopShelfItemCollection(items: items)
        collection.title = "Continue Watching"
        return TVTopShelfSectionedContent(sections: [collection])
    }
}
