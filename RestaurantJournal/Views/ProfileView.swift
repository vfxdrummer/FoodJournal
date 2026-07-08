import SwiftUI
import AuthenticationServices
import PhotosUI

/// Account/profile screen. Signed-out is a branded sign-in hero (optional phone/Apple/Google);
/// signed-in shows the account, avatar, and a sign-out. Avatar auto-fills from the provider photo
/// when available, else the user picks one.
struct ProfileView: View {
    @ObservedObject private var auth = SupabaseAuthService.shared
    @ObservedObject private var profile = ProfileStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingPhoneAuth = false
    @State private var appleNonce: String?
    @State private var authError: String?
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Group {
                if let session = auth.session {
                    signedIn(session)
                } else {
                    signedOut
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPhoneAuth) {
                PhoneAuthView()
            }
        }
    }

    // MARK: - Signed out (branded hero)

    private var signedOut: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 32)

                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 5)

                VStack(spacing: 8) {
                    Text("Restaurant Journal")
                        .font(.title.weight(.bold))
                    Text("Sign in to connect a card and import your dining charges.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("You can keep using the journal without an account.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    phoneButton
                    appleButton
                    googleButton
                    if let authError {
                        Text(authError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 8)

                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var phoneButton: some View {
        Button {
            showingPhoneAuth = true
        } label: {
            Label("Continue with phone", systemImage: "phone.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.white)
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            let nonce = AppleSignInSupport.randomNonce()
            appleNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = AppleSignInSupport.sha256(nonce)
        } onCompletion: { result in
            handleApple(result)
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var googleButton: some View {
        Button {
            Task {
                authError = nil
                do {
                    try await auth.signInWithGoogle()
                } catch {
                    authError = error.localizedDescription
                }
            }
        } label: {
            Label("Continue with Google", systemImage: "globe")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.12))
                )
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Signed in

    @ViewBuilder private func signedIn(_ session: AuthSession) -> some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ProfileAvatarView(size: 60)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.body)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Color.accentColor)
                                    .background(Circle().fill(.background))
                            }
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.displayName).font(.headline)
                        Text("Account connected").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if profile.avatar == nil {
                Section {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Add a profile photo", systemImage: "photo.badge.plus")
                    }
                } footer: {
                    Text("We couldn't find a photo automatically — pick one from your library.")
                }
            }

            Section {
                Button(role: .destructive) {
                    auth.signOut()
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    profile.setImage(data: data)
                }
            }
        }
    }

    // MARK: - Apple

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        authError = nil
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = appleNonce
            else {
                authError = "Couldn't read the Apple credential. Please try again."
                return
            }
            Task {
                do {
                    try await auth.signInWithApple(idToken: idToken, nonce: nonce)
                } catch {
                    authError = error.localizedDescription
                }
            }
        case .failure(let error):
            // Don't surface the user simply cancelling the sheet.
            if (error as? ASAuthorizationError)?.code != .canceled {
                authError = error.localizedDescription
            }
        }
    }
}
