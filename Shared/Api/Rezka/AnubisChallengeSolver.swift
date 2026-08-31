//
//  AnubisChallengeSolver.swift
//  rezka-player
//

import Foundation
import CryptoKit
import SwiftSoup

/// Solves the Anubis anti-bot proof-of-work challenge (https://anubis.techaro.lol)
/// that rezka.ag now serves in front of every request. Anubis blocks a client until
/// it finds a `nonce` such that SHA-256(challenge.randomData + nonce) has enough
/// leading zero bits, then trades that answer for a session cookie via a
/// `pass-challenge` request.
///
/// A real browser solves this by running Anubis's own JS in a Web Worker, but
/// there's no WebKit on tvOS to host that JS. Instead this reimplements the exact
/// same proof-of-work natively (verified against Anubis's `sha256-webcrypto.mjs`
/// worker source) and replays the same `pass-challenge` request the JS would make,
/// so it works identically on tvOS, iOS, and macOS.
struct AnubisChallengeSolver {

    enum SolveError: Error {
        case notChallenged
        case couldNotFindNonce
        case passChallengeFailed
    }

    private struct ChallengeRules: Decodable {
        let difficulty: Int
    }

    private struct ChallengeDetails: Decodable {
        let id: String
        let randomData: String
    }

    private struct ChallengePayload: Decodable {
        let rules: ChallengeRules
        let challenge: ChallengeDetails
    }

    func solve(server: String, maxAttempts: Int = 5_000_000) async throws {
        guard let requestURL = URL(string: server) else {
            throw DataError.generate(for: .rezkaConstantsApi, error: .bad)
        }

        var request = URLRequest(url: requestURL)
        request.setValue(ApiConstants.userAgent, forHTTPHeaderField: ApiConstants.userAgentKey)

        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(decoding: data, as: UTF8.self)
        let document = try SwiftSoup.parse(html)

        guard let challengeRaw = try document.select("#anubis_challenge").first()?.data(),
              let challengeData = challengeRaw.data(using: .utf8) else {
            throw SolveError.notChallenged
        }

        let basePrefix = decodeJSONString(try document.select("#anubis_base_prefix").first()?.data())
        let payload = try JSONDecoder().decode(ChallengePayload.self, from: challengeData)

        let startedAt = Date()
        guard let solution = try await Task.detached(priority: .userInitiated, operation: {
            Self.findNonce(randomData: payload.challenge.randomData, difficulty: payload.rules.difficulty, maxAttempts: maxAttempts)
        }).value else {
            throw SolveError.couldNotFindNonce
        }
        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)

        guard var components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
            throw SolveError.passChallengeFailed
        }
        components.path = "\(basePrefix)/.within.website/x/cmd/anubis/api/pass-challenge"
        components.queryItems = [
            URLQueryItem(name: "id", value: payload.challenge.id),
            URLQueryItem(name: "response", value: solution.hash),
            URLQueryItem(name: "nonce", value: "\(solution.nonce)"),
            URLQueryItem(name: "redir", value: "\(server)/"),
            URLQueryItem(name: "elapsedTime", value: "\(elapsedMs)"),
        ]

        guard let passURL = components.url else {
            throw SolveError.passChallengeFailed
        }

        var passRequest = URLRequest(url: passURL)
        passRequest.setValue(ApiConstants.userAgent, forHTTPHeaderField: ApiConstants.userAgentKey)

        let (_, response) = try await URLSession.shared.data(for: passRequest)
        guard let http = response as? HTTPURLResponse, (200...399).contains(http.statusCode) else {
            throw SolveError.passChallengeFailed
        }
    }

    private func decodeJSONString(_ raw: String?) -> String {
        guard let raw, let data = raw.data(using: .utf8) else { return "" }
        return (try? JSONDecoder().decode(String.self, from: data)) ?? ""
    }

    private static func findNonce(randomData: String, difficulty: Int, maxAttempts: Int) -> (hash: String, nonce: Int)? {
        let fullZeroBytes = difficulty / 2
        let hasHalfByte = difficulty % 2 != 0
        let prefixBytes = Array(randomData.utf8)

        for nonce in 0..<maxAttempts {
            var input = prefixBytes
            input.append(contentsOf: Array(String(nonce).utf8))
            let digest = Array(SHA256.hash(data: input))

            var matches = true
            for i in 0..<fullZeroBytes where digest[i] != 0 {
                matches = false
                break
            }
            if matches, hasHalfByte, (digest[fullZeroBytes] >> 4) != 0 {
                matches = false
            }

            if matches {
                let hex = digest.map { String(format: "%02x", $0) }.joined()
                return (hex, nonce)
            }
        }
        return nil
    }
}
