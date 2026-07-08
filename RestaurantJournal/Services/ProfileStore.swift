import SwiftUI
import UIKit

/// Holds the user's profile photo, persisted locally. Auto-populated from an OAuth provider's photo
/// when one is available (Google), otherwise set manually by the user. Backend sync arrives with the
/// accounts/Plaid work.
@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published var avatar: UIImage?

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile_avatar.jpg")
    }

    private init() {
        if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
            avatar = image
        }
    }

    func setImage(data: Data) {
        guard let image = UIImage(data: data) else { return }
        avatar = image
        if let jpeg = image.jpegData(compressionQuality: 0.9) {
            try? jpeg.write(to: fileURL)
        }
    }

    /// Download and store an avatar from a URL — but only if the user doesn't already have one, so
    /// a manual pick is never overwritten.
    func fetchIfNeeded(from urlString: String?) {
        guard avatar == nil, let urlString, let url = URL(string: urlString) else { return }
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url) {
                setImage(data: data)
            }
        }
    }

    func clear() {
        avatar = nil
        try? FileManager.default.removeItem(at: fileURL)
    }
}
