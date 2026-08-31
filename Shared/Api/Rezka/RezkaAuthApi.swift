//
//  RezkaAuthApi.swift
//  rezka-player
//

import Foundation

private struct LoginResponse: Decodable {
    let success: Bool
    let message: String?
}

enum RezkaAuthError: Error, LocalizedError {
    case missingCredentials
    case badResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "Email and password are required."
        case .badResponse: return "Bad response from server."
        case .server(let msg): return msg
        }
    }
}

struct RezkaAuthApi {

    static let isSignedInKey = "rezkaIsSignedIn"
    static let savedEmailKey = "rezkaSavedEmail"
    private static let sessionCookiesKey = "rezkaSessionCookies"

    func signIn(email: String, password: String) async throws {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty, !trimmedPassword.isEmpty else {
            throw RezkaAuthError.missingCredentials
        }

        guard let url = URL(string: "\(RezkaConstantsApi.server)/ajax/login/") else {
            throw RezkaAuthError.badResponse
        }

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "login_name", value: trimmedEmail),
            URLQueryItem(name: "login_password", value: trimmedPassword),
            URLQueryItem(name: "login_not_save", value: "0"),
        ]

        var request = URLRequest(url: url)
        request.httpMethod = ApiConstants.HttpMethod.post.rawValue
        request.httpBody = components.query?.data(using: .utf8)
        request.setValue(ApiConstants.userAgent, forHTTPHeaderField: ApiConstants.userAgentKey)
        request.addValue(ApiConstants.formContentType, forHTTPHeaderField: ApiConstants.contentTypeKey)
        request.addValue(ApiConstants.AcceptTypeJson, forHTTPHeaderField: ApiConstants.AcceptTypeKey)
        request.setValue(RezkaConstantsApi.server, forHTTPHeaderField: "Referer")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")

        let (data, response) = try await RezkaHTTPClient.shared.send(request)

        guard let http = response as? HTTPURLResponse else {
            throw RezkaAuthError.badResponse
        }

        guard (200...299).contains(http.statusCode) else {
            throw RezkaAuthError.server("HTTP \(http.statusCode)")
        }

        let decoded = try? JSONDecoder().decode(LoginResponse.self, from: data)
        if let decoded = decoded {
            if decoded.success {
                UserDefaults.standard.set(true, forKey: RezkaAuthApi.isSignedInKey)
                UserDefaults.standard.set(trimmedEmail, forKey: RezkaAuthApi.savedEmailKey)
                RezkaAuthApi.persistSessionCookies()
                return
            } else {
                throw RezkaAuthError.server(decoded.message ?? "Login failed.")
            }
        }

        throw RezkaAuthError.server(String(decoding: data, as: UTF8.self))
    }

    func signOut() {
        UserDefaults.standard.set(false, forKey: RezkaAuthApi.isSignedInKey)
        UserDefaults.standard.removeObject(forKey: RezkaAuthApi.savedEmailKey)
        UserDefaults.standard.removeObject(forKey: RezkaAuthApi.sessionCookiesKey)

        guard let host = URL(string: RezkaConstantsApi.server)?.host else { return }
        let storage = HTTPCookieStorage.shared
        storage.cookies?
            .filter { ($0.domain).contains(host) || host.contains($0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) }
            .forEach { storage.deleteCookie($0) }
    }

    static var isSignedIn: Bool {
        UserDefaults.standard.bool(forKey: isSignedInKey)
    }

    static var savedEmail: String {
        UserDefaults.standard.string(forKey: savedEmailKey) ?? ""
    }

    /// `HTTPCookieStorage.shared` is not reliably surviving a full app relaunch
    /// (the PHPSESSID cookie the login response sets has no Max-Age at all, and in
    /// practice the persistent dle_user_id/dle_password cookies weren't coming back
    /// either) — so instead of depending on ambient cookie-jar persistence, we snapshot
    /// the auth cookies ourselves at sign-in and explicitly restore them at launch.
    static func persistSessionCookies() {
        guard let host = URL(string: RezkaConstantsApi.server)?.host else { return }
        let relevant = HTTPCookieStorage.shared.cookies?.filter { domainMatches($0.domain, host: host) } ?? []

        let serialized: [[String: Any]] = relevant.compactMap { cookie in
            guard let properties = cookie.properties else { return nil }
            var dict = [String: Any]()
            for (key, value) in properties {
                dict[key.rawValue] = value
            }
            return dict
        }

        UserDefaults.standard.set(serialized, forKey: sessionCookiesKey)
    }

    /// Call once at app launch, before any authenticated request, to restore the
    /// session saved by `persistSessionCookies()`.
    static func restoreSessionCookies() {
        guard let saved = UserDefaults.standard.array(forKey: sessionCookiesKey) as? [[String: Any]] else { return }

        for dict in saved {
            var properties = [HTTPCookiePropertyKey: Any]()
            for (key, value) in dict {
                properties[HTTPCookiePropertyKey(key)] = value
            }
            if let cookie = HTTPCookie(properties: properties) {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
    }

    private static func domainMatches(_ cookieDomain: String, host: String) -> Bool {
        let trimmed = cookieDomain.hasPrefix(".") ? String(cookieDomain.dropFirst()) : cookieDomain
        return host == trimmed || host.hasSuffix("." + trimmed)
    }
}
