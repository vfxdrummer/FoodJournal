import Foundation

/// A persisted Supabase auth session.
struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userID: String
    let phone: String?
    var email: String?

    /// Treat as expired a minute early so we refresh before a backend call fails.
    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }

    /// A friendly label for the account (phone, else email, else generic).
    var displayName: String { phone ?? email ?? "Signed in" }
}

enum AuthError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

/// Dependency-free Supabase authentication over the GoTrue REST API. Handles phone OTP now; Apple
/// and Google will layer on via the same session model. The app stays fully usable while
/// `session == nil` — an account is only needed for the (future) card-linking feature.
@MainActor
final class SupabaseAuthService: ObservableObject {
    static let shared = SupabaseAuthService()

    /// Non-nil when signed in. Persisted in the Keychain across launches.
    @Published private(set) var session: AuthSession?

    var isSignedIn: Bool { session != nil }

    private let keychainKey = "supabase.session"

    private init() {
        session = loadSession()
    }

    // MARK: - Phone OTP

    /// Request an SMS one-time code for a phone number in E.164 form (e.g. "+14155551234").
    /// Requires an SMS provider (Twilio) configured in the Supabase dashboard.
    func sendPhoneOTP(to phone: String) async throws {
        try await postVoid(path: "otp", body: ["phone": phone])
    }

    /// Verify the SMS code and establish a session.
    func verifyPhoneOTP(phone: String, code: String) async throws {
        let token = try await postForToken(
            path: "verify",
            body: ["type": "sms", "phone": phone, "token": code]
        )
        apply(token)
    }

    // MARK: - Sign in with Apple

    /// Exchange an Apple identity token (from the native flow) for a Supabase session. `nonce` is
    /// the *raw* nonce whose SHA-256 was sent to Apple.
    func signInWithApple(idToken: String, nonce: String) async throws {
        let token = try await postForToken(
            path: "token?grant_type=id_token",
            body: ["provider": "apple", "id_token": idToken, "nonce": nonce]
        )
        apply(token)
    }

    // MARK: - Sign in with Google (OAuth via ASWebAuthenticationSession)

    /// Open Supabase's Google OAuth flow in a secure web session and establish a session from the
    /// tokens returned to our custom URL scheme. No third-party SDK required.
    func signInWithGoogle() async throws {
        guard var components = URLComponents(string: "\(SupabaseConfig.authBase)/authorize") else {
            throw AuthError.message("Invalid Supabase URL.")
        }
        components.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: SupabaseConfig.oauthRedirect)
        ]
        guard let url = components.url else { throw AuthError.message("Invalid Supabase URL.") }

        let callback = try await WebAuthSession().start(
            url: url,
            callbackScheme: SupabaseConfig.oauthScheme
        )
        try applyOAuthCallback(callback)
    }

    /// Parse tokens from the OAuth redirect (implicit flow: tokens arrive in the URL fragment).
    private func applyOAuthCallback(_ url: URL) throws {
        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment else {
            throw AuthError.message("Sign-in didn't return a session.")
        }
        var params: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                params[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
            }
        }
        if let message = params["error_description"] ?? params["error"] {
            throw AuthError.message(message.replacingOccurrences(of: "+", with: " "))
        }
        guard let accessToken = params["access_token"],
              let refreshToken = params["refresh_token"] else {
            throw AuthError.message("Sign-in didn't return a session.")
        }
        let claims = Self.decodeJWT(accessToken)
        let expiresIn = Int(params["expires_in"] ?? "") ?? 3600
        store(AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            userID: claims?["sub"] as? String ?? "",
            phone: claims?["phone"] as? String,
            email: claims?["email"] as? String
        ))
    }

    /// Decode a JWT payload (base64url) into its claims — used to read the user id/email from the
    /// access token returned by OAuth, where there's no separate user object.
    private static func decodeJWT(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    // MARK: - Session lifecycle

    func signOut() {
        if let token = session?.accessToken {
            Task { try? await postVoid(path: "logout", body: [:], accessToken: token) }
        }
        KeychainStore.delete(keychainKey)
        session = nil
        ProfileStore.shared.clear()
    }

    /// Return a session with a fresh access token, refreshing if it's near expiry. Backend calls
    /// should go through this to avoid 401s.
    @discardableResult
    func validSession() async throws -> AuthSession? {
        guard let current = session else { return nil }
        guard current.isExpired else { return current }
        let token = try await postForToken(
            path: "token?grant_type=refresh_token",
            body: ["refresh_token": current.refreshToken]
        )
        apply(token)
        return session
    }

    // MARK: - Persistence

    private func apply(_ token: TokenResponse) {
        store(token.toSession())
    }

    private func store(_ newSession: AuthSession) {
        if let data = try? JSONEncoder().encode(newSession),
           let json = String(data: data, encoding: .utf8) {
            KeychainStore.save(json, for: keychainKey)
        }
        session = newSession

        // Best-effort avatar: providers stash a photo URL in user_metadata (Google does; Apple and
        // phone don't). Fetched only if the user hasn't set one manually.
        if let claims = Self.decodeJWT(newSession.accessToken),
           let metadata = claims["user_metadata"] as? [String: Any] {
            let avatarURL = (metadata["avatar_url"] as? String) ?? (metadata["picture"] as? String)
            ProfileStore.shared.fetchIfNeeded(from: avatarURL)
        }
    }

    private func loadSession() -> AuthSession? {
        guard let json = KeychainStore.load(keychainKey),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    // MARK: - Networking

    private func makeRequest(path: String, body: [String: String], accessToken: String?) throws -> URLRequest {
        guard let url = URL(string: "\(SupabaseConfig.authBase)/\(path)") else {
            throw AuthError.message("Invalid Supabase URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken ?? SupabaseConfig.publishableKey)",
                         forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.message("No response from server.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AuthError.message(Self.parseError(data) ?? "Request failed (\(http.statusCode)).")
        }
        return data
    }

    private func postVoid(path: String, body: [String: String], accessToken: String? = nil) async throws {
        _ = try await send(makeRequest(path: path, body: body, accessToken: accessToken))
    }

    private func postForToken(path: String, body: [String: String]) async throws -> TokenResponse {
        let data = try await send(makeRequest(path: path, body: body, accessToken: nil))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TokenResponse.self, from: data)
    }

    private static func parseError(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // GoTrue uses a few different error keys across endpoints.
        for key in ["error_description", "msg", "message", "error"] {
            if let value = object[key] as? String { return value }
        }
        return nil
    }
}

/// GoTrue token payload (snake_case decoded via `.convertFromSnakeCase`).
private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int?
    let expiresAt: Int?
    let user: UserPayload

    struct UserPayload: Decodable {
        let id: String
        let phone: String?
        let email: String?
    }

    func toSession() -> AuthSession {
        let expiry: Date
        if let expiresAt {
            expiry = Date(timeIntervalSince1970: TimeInterval(expiresAt))
        } else if let expiresIn {
            expiry = Date().addingTimeInterval(TimeInterval(expiresIn))
        } else {
            expiry = Date().addingTimeInterval(3600)
        }
        return AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiry,
            userID: user.id,
            phone: user.phone?.isEmpty == true ? nil : user.phone,
            email: user.email?.isEmpty == true ? nil : user.email
        )
    }
}
