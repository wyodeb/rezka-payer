//
//  RezkaConstantsApi.swift
//  rezka-player
//
//  Created by Vitalii Parovishnyk on 21.10.2022.
//

import Foundation

struct RezkaConstantsApi {
    static let baseURLKey = "rezkaBaseURL"
    static let defaultServer = "https://rezka.ag"
    static let domain = "RezkaAPI"

    static var server: String {
        let raw = UserDefaults.standard.string(forKey: baseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !raw.isEmpty else { return defaultServer }

        var normalized = raw
        if !normalized.lowercased().hasPrefix("http://") && !normalized.lowercased().hasPrefix("https://") {
            normalized = "https://" + normalized
        }
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }
}
