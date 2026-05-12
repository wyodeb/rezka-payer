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

    private let session = URLSession.shared

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

        let (data, response) = try await session.data(for: request)

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
}
