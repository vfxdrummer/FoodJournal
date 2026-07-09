import Foundation

enum PlaidError: LocalizedError {
    case notSignedIn
    case message(String)
    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Please sign in first."
        case .message(let text): return text
        }
    }
}

/// A cached dining charge from `card_transactions` (read via PostgREST with RLS).
struct CardTransaction: Codable, Identifiable {
    let id: String
    let transactionId: String
    let name: String?
    let merchantName: String?
    let amount: Double?
    let isoCurrencyCode: String?
    let date: String
    let category: String?
    let latitude: Double?
    let longitude: Double?
    let pending: Bool
}

/// Client for the Plaid Edge Functions. All Plaid credentials live server-side; the app only ever
/// holds the user's Supabase session token.
@MainActor
final class PlaidService {
    static let shared = PlaidService()
    private init() {}

    private var functionsBase: String { SupabaseConfig.projectURL.absoluteString + "/functions/v1" }
    private var restBase: String { SupabaseConfig.projectURL.absoluteString + "/rest/v1" }

    /// Full connect flow: create a Hosted Link token → present Plaid Link in a browser → exchange
    /// the result for an access token → sync. Returns the number of dining charges imported.
    func connectCard() async throws -> Int {
        let link = try await createLinkToken()
        guard let url = URL(string: link.hostedLinkUrl) else { throw PlaidError.message("Bad link URL.") }
        _ = try await WebAuthSession().start(url: url, callbackScheme: SupabaseConfig.oauthScheme)
        try await exchange(linkToken: link.linkToken)
        return try await sync()
    }

    // MARK: - Endpoints

    private struct LinkTokenResponse: Decodable { let linkToken: String; let hostedLinkUrl: String }
    private struct SyncResponse: Decodable { let added: Int }
    private struct OKResponse: Decodable {}

    private func createLinkToken() async throws -> LinkTokenResponse {
        try await callFunction("plaid-create-link-token")
    }

    func exchange(linkToken: String) async throws {
        let _: OKResponse = try await callFunction("plaid-exchange-token", body: ["link_token": linkToken])
    }

    @discardableResult
    func sync() async throws -> Int {
        let result: SyncResponse = try await callFunction("plaid-sync-transactions")
        return result.added
    }

    /// Revoke linked card(s) and remove their server-side data.
    func disconnectCard() async throws {
        let _: OKResponse = try await callFunction("plaid-remove-item")
    }

    /// The user's dining transactions, most recent first.
    func fetchDiningTransactions() async throws -> [CardTransaction] {
        guard let session = try await SupabaseAuthService.shared.validSession() else {
            throw PlaidError.notSignedIn
        }
        guard let url = URL(string: "\(restBase)/card_transactions?select=*&order=date.desc") else {
            throw PlaidError.message("Bad URL.")
        }
        var request = URLRequest(url: url)
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PlaidError.message("Couldn't load transactions.")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([CardTransaction].self, from: data)
    }

    // MARK: - Networking

    private func callFunction<T: Decodable>(_ name: String, body: [String: Any] = [:]) async throws -> T {
        guard let session = try await SupabaseAuthService.shared.validSession() else {
            throw PlaidError.notSignedIn
        }
        guard let url = URL(string: "\(functionsBase)/\(name)") else { throw PlaidError.message("Bad URL.") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PlaidError.message("No response.") }
        guard (200..<300).contains(http.statusCode) else {
            let message = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String
            throw PlaidError.message(message ?? "Request failed (\(http.statusCode)).")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}
