import Foundation

struct WatchHistoryEntry: Codable, Equatable, Identifiable {
    let media: Media
    var currentTime: Double
    var duration: Double
    var updatedAt: Date
    var season: Int?
    var episode: Int?
    var translationId: Int?

    var id: UUID { media.id }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
    }

    var timeLeftFormatted: String {
        let left = max(duration - currentTime, 0)
        let minutes = Int(left) / 60
        if minutes < 60 {
            return "\(minutes) min left"
        }
        let hours = minutes / 60
        let rem = minutes % 60
        return "\(hours)h \(rem)m left"
    }

    var positionFormatted: String {
        let mins = Int(currentTime) / 60
        let secs = Int(currentTime) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var episodeLabel: String? {
        guard let s = season, let e = episode else { return nil }
        return "S\(s) E\(e)"
    }
}
