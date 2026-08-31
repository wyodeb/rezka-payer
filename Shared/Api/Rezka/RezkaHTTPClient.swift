//
//  RezkaHTTPClient.swift
//  rezka-player
//

import Foundation

/// Drop-in replacement for `URLSession.shared.data(for:)` used by all Rezka API
/// calls. Before a request goes out it makes sure we're holding a live Anubis
/// challenge cookie for the target host (solving the challenge via
/// `AnubisChallengeSolver` if needed), and if a response still comes back as the
/// challenge page anyway (cookie expired mid-flight, etc.) it solves once and
/// retries the request.
actor RezkaHTTPClient {

    static let shared = RezkaHTTPClient()
    private init() {}

    private var inFlightSolve: Task<Void, Error>?

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        if let host = request.url?.host, !hasValidAuthCookie(forHost: host) {
            try await solveChallenge()
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard Self.looksLikeChallenge(data) else {
            return (data, response)
        }

        try await solveChallenge()
        return try await URLSession.shared.data(for: request)
    }

    private func solveChallenge() async throws {
        if let existing = inFlightSolve {
            try await existing.value
            return
        }

        let task = Task {
            try await AnubisChallengeSolver().solve(server: RezkaConstantsApi.server)
        }
        inFlightSolve = task
        defer { inFlightSolve = nil }
        try await task.value
    }

    private func hasValidAuthCookie(forHost host: String) -> Bool {
        guard let cookies = HTTPCookieStorage.shared.cookies else { return false }
        return cookies.contains { cookie in
            cookie.name.hasSuffix("-anubis-auth")
                && !cookie.value.isEmpty
                && domainMatches(cookie.domain, host: host)
                && (cookie.expiresDate.map { $0 > Date() } ?? true)
        }
    }

    private func domainMatches(_ cookieDomain: String, host: String) -> Bool {
        let trimmed = cookieDomain.hasPrefix(".") ? String(cookieDomain.dropFirst()) : cookieDomain
        return host == trimmed || host.hasSuffix("." + trimmed)
    }

    private static func looksLikeChallenge(_ data: Data) -> Bool {
        guard data.count < 20_000, let html = String(data: data, encoding: .utf8) else { return false }
        return html.contains("id=\"anubis_challenge\"") || html.contains("anubis_version")
    }
}
