//
//  SettingsView.swift
//  rezka-player
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(RezkaConstantsApi.baseURLKey) private var baseURL: String = ""
    @AppStorage(RezkaAuthApi.isSignedInKey) private var isSignedIn: Bool = false
    @AppStorage(RezkaAuthApi.savedEmailKey) private var savedEmail: String = ""

    @State private var draft: String = ""
    @State private var savedMessage: String?

    @State private var emailInput: String = ""
    @State private var passwordInput: String = ""
    @State private var authStatus: String?
    @State private var authBusy: Bool = false

    @AppStorage(MediaFilter.hideRuKey) private var hideRuContent: Bool = true

    private let authApi = RezkaAuthApi()

    var body: some View {
        ZStack {
            RezkaBackground()
            settingsForm
        }
    }

    private var settingsForm: some View {
        Form {
            Section {
                TextField("https://rezka.ag", text: $draft)
                    .textContentType(.URL)
                    .autocorrectionDisabled(true)
                    #if !os(tvOS) && !os(macOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
            } header: {
                Text("Base URL")
            } footer: {
                Text("Set the HD Rezka mirror to use. Leave empty to use the default (\(RezkaConstantsApi.defaultServer)).")
            }

            Section {
                Button("Save") {
                    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    baseURL = trimmed
                    savedMessage = trimmed.isEmpty
                        ? "Using default: \(RezkaConstantsApi.defaultServer)"
                        : "Saved: \(RezkaConstantsApi.server)"
                }
                Button("Reset to default", role: .destructive) {
                    baseURL = ""
                    draft = ""
                    savedMessage = "Reset to default: \(RezkaConstantsApi.defaultServer)"
                }

                if let savedMessage = savedMessage {
                    Text(savedMessage)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Toggle("Hide Russia / USSR content", isOn: $hideRuContent)
            } header: {
                Text("Content")
            } footer: {
                Text("Items whose origin country is Russia or the USSR are filtered out of every list and search result. Reopen a list after toggling for changes to take effect.")
            }

            Section {
                if isSignedIn {
                    HStack {
                        Text("Signed in as")
                        Spacer()
                        Text(savedEmail.isEmpty ? "(unknown)" : savedEmail)
                            .foregroundColor(.secondary)
                    }
                    Button("Sign out", role: .destructive) {
                        authApi.signOut()
                        emailInput = ""
                        passwordInput = ""
                        authStatus = "Signed out."
                    }
                } else {
                    TextField("Email", text: $emailInput)
                        .textContentType(.username)
                        .autocorrectionDisabled(true)
                        #if !os(tvOS) && !os(macOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField("Password", text: $passwordInput)
                        .textContentType(.password)

                    Button(authBusy ? "Signing in..." : "Sign in") {
                        signIn()
                    }
                    .disabled(authBusy)
                }

                if let authStatus = authStatus {
                    Text(authStatus)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Account")
            } footer: {
                Text("Sign in to your HD Rezka account to access content tied to your profile. Credentials are sent to the base URL above.")
            }
        }
#if !os(tvOS)
        .scrollContentBackground(.hidden)
#endif
        .listStyle(.grouped)
        .onAppear {
            draft = baseURL
            if isSignedIn, emailInput.isEmpty {
                emailInput = savedEmail
            }
        }
        .navigationTitle("Settings")
    }

    private func signIn() {
        authBusy = true
        authStatus = nil
        let email = emailInput
        let password = passwordInput

        Task {
            do {
                try await authApi.signIn(email: email, password: password)
                await MainActor.run {
                    authBusy = false
                    passwordInput = ""
                    authStatus = "Signed in."
                }
            } catch {
                await MainActor.run {
                    authBusy = false
                    authStatus = error.localizedDescription
                }
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
