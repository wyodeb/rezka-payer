//
//  rezka_playerApp.swift
//  Shared
//
//  Created by Vitalii Parovishnyk on 16.08.2022.
//

import SwiftUI

@main
struct rezka_playerApp: App {
    init() {
        RezkaAuthApi.restoreSessionCookies()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    WatchHistoryViewModel.shared.handleDeepLink(url: url)
                }
        }
    }
}
