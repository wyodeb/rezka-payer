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
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    Text("Settings")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(RezkaPalette.primaryText)

                    baseURLSection
                    contentSection
                    accountSection
                }
                .padding(60)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            draft = baseURL
            if isSignedIn, emailInput.isEmpty {
                emailInput = savedEmail
            }
        }
    }

    private var baseURLSection: some View {
        SettingsSection(
            title: "Base URL",
            footer: "Set the HD Rezka mirror to use. Leave empty to use the default (\(RezkaConstantsApi.defaultServer))."
        ) {
            TextField("https://rezka.ag", text: $draft)
                .textContentType(.URL)
                .autocorrectionDisabled(true)
#if !os(tvOS) && !os(macOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
#endif
                .textFieldStyle(.plain)
                .settingsField()

            HStack(spacing: 16) {
                Button("Save") {
                    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    baseURL = trimmed
                    savedMessage = trimmed.isEmpty
                        ? "Using default: \(RezkaConstantsApi.defaultServer)"
                        : "Saved: \(RezkaConstantsApi.server)"
                }
                .buttonStyle(PillButtonStyle())

                Button("Reset to default") {
                    baseURL = ""
                    draft = ""
                    savedMessage = "Reset to default: \(RezkaConstantsApi.defaultServer)"
                }
                .buttonStyle(PillButtonStyle(isDestructive: true))
            }

            if let savedMessage {
                Text(savedMessage)
                    .font(.footnote)
                    .foregroundStyle(RezkaPalette.secondaryText)
            }
        }
    }

    private var contentSection: some View {
        SettingsSection(
            title: "Content",
            footer: "Items whose origin country is Russia or the USSR are filtered out of every list and search result. Reopen a list after toggling for changes to take effect."
        ) {
            Toggle("Hide Russia / USSR content", isOn: $hideRuContent)
                .tint(RezkaPalette.primaryText)
        }
    }

    private var accountSection: some View {
        SettingsSection(
            title: "Account",
            footer: "Sign in to your HD Rezka account to access content tied to your profile. Watch progress is synced with your account's own \"Continue watching\" list, so it carries over from rezka.ag itself and any other device signed into the same account. Credentials are sent to the base URL above."
        ) {
            if isSignedIn {
                HStack {
                    Text("Signed in as")
                        .foregroundStyle(RezkaPalette.secondaryText)
                    Spacer()
                    Text(savedEmail.isEmpty ? "(unknown)" : savedEmail)
                        .foregroundStyle(RezkaPalette.primaryText)
                }

                Button("Sign out") {
                    authApi.signOut()
                    WatchHistoryViewModel.shared.clearRemoteAssociations()
                    emailInput = ""
                    passwordInput = ""
                    authStatus = "Signed out."
                }
                .buttonStyle(PillButtonStyle(isDestructive: true))
            } else {
                TextField("Email", text: $emailInput)
                    .textContentType(.username)
                    .autocorrectionDisabled(true)
#if !os(tvOS) && !os(macOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
#endif
                    .textFieldStyle(.plain)
                    .settingsField()

                SecureField("Password", text: $passwordInput)
                    .textContentType(.password)
                    .textFieldStyle(.plain)
                    .settingsField()

                Button(authBusy ? "Signing in..." : "Sign in") {
                    signIn()
                }
                .buttonStyle(PillButtonStyle())
                .disabled(authBusy)
            }

            if let authStatus {
                Text(authStatus)
                    .font(.footnote)
                    .foregroundStyle(RezkaPalette.secondaryText)
            }
        }
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
                await WatchHistoryViewModel.shared.syncFromRemote()
            } catch {
                await MainActor.run {
                    authBusy = false
                    authStatus = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Settings-specific styling

private struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(RezkaPalette.tertiaryText)
                .kerning(1.2)

            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .padding(24)
            .glassCard(corner: 24)

            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(RezkaPalette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingsFieldStyle: ViewModifier {
    // Deliberately no .foregroundStyle here: on tvOS, a focused/editing text field
    // draws its own opaque light bezel behind the text, which the system already
    // contrasts correctly. Forcing a light foreground on top of that native bezel
    // is what produced white-on-white text — let the platform own that color.
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RezkaPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(RezkaPalette.surfaceStroke, lineWidth: 1)
            )
    }
}

private extension View {
    func settingsField() -> some View {
        modifier(SettingsFieldStyle())
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
