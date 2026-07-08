import Foundation
import CryptoKit

/// Nonce helpers for Sign in with Apple. Apple wants a SHA-256 *hashed* nonce in the request; the
/// backend (Supabase) is given the original *raw* nonce and re-hashes it to verify — this binds the
/// returned identity token to our request and prevents replay.
enum AppleSignInSupport {
    static func randomNonce(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            if SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms) != errSecSuccess {
                randoms = (0..<16).map { _ in UInt8.random(in: 0...255) }
            }
            for byte in randoms where remaining > 0 {
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
