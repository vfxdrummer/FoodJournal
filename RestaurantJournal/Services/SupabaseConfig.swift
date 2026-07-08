import Foundation

/// Supabase project connection details. The publishable key is the *client-safe* key — it's meant
/// to ship in the app, with security enforced server-side by Row-Level Security. The secret key is
/// never here; it lives only in backend (Edge Function / Worker) secrets.
enum SupabaseConfig {
    static let projectURL = URL(string: "https://djjrmnpqyywploerecpr.supabase.co")!
    static let publishableKey = "sb_publishable_J0WKrqu7HTU-rsfEaslG_w_chB14kVA"

    /// Base for the GoTrue auth REST API.
    static var authBase: String { projectURL.absoluteString + "/auth/v1" }

    /// Custom URL scheme + redirect for OAuth callbacks (must be registered in Info.plist and added
    /// to Supabase's allowed Redirect URLs).
    static let oauthScheme = "restaurantjournal"
    static let oauthRedirect = "restaurantjournal://auth-callback"
}
