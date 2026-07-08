import SwiftUI

/// The user's avatar wherever it appears. Shows the chosen/fetched photo when there is one; other-
/// wise falls back to the app's logo icon (which is what a signed-out user always sees, since
/// signing out clears any stored photo).
struct ProfileAvatarView: View {
    @ObservedObject private var profile = ProfileStore.shared
    var size: CGFloat = 30

    var body: some View {
        Group {
            if let image = profile.avatar {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("BrandMark")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
    }
}
