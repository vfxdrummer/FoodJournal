import SwiftUI
import SwiftData
import Photos
import AVKit

/// Full-screen, swipeable viewer for a visit's album (photos and videos), with a one-tap "Set as cover".
struct PhotoViewerView: View {
    @Bindable var visit: Visit
    let photoIDs: [String]

    @State var selection: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private var isCurrentCover: Bool {
        visit.coverPhoto?.localIdentifier == selection
    }

    private func isVideo(_ id: String) -> Bool {
        visit.photos.first { $0.localIdentifier == id }?.isVideo ?? false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                TabView(selection: $selection) {
                    ForEach(photoIDs, id: \.self) { id in
                        Group {
                            if isVideo(id) {
                                VideoPageView(localIdentifier: id, isCurrent: id == selection)
                            } else {
                                LargePhotoView(localIdentifier: id)
                            }
                        }
                        .tag(id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: photoIDs.count > 1 ? .automatic : .never))
                .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        visit.coverPhotoLocalIdentifier = selection
                        try? modelContext.save()
                    } label: {
                        Label(isCurrentCover ? "Cover photo" : "Set as cover",
                              systemImage: isCurrentCover ? "star.fill" : "star")
                    }
                    .disabled(isCurrentCover)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

/// A single photo shown fit-to-screen at high quality, with pinch + double-tap to zoom.
private struct LargePhotoView: View {
    let localIdentifier: String

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var steadyScale: CGFloat = 1

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in scale = max(1, steadyScale * value) }
                            .onEnded { _ in
                                steadyScale = scale
                                if scale <= 1 { withAnimation { scale = 1; steadyScale = 1 } }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation {
                            scale = scale > 1 ? 1 : 2.5
                            steadyScale = scale
                        }
                    }
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: localIdentifier) {
            scale = 1; steadyScale = 1
            image = await PhotoThumbnailLoader.loadShareImage(localIdentifier: localIdentifier, maxDimension: 1800)
        }
    }
}

/// A single video played full-screen. Auto-plays when it's the current page; pauses otherwise.
private struct VideoPageView: View {
    let localIdentifier: String
    let isCurrent: Bool

    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: localIdentifier) {
            player = await loadPlayer()
            if isCurrent { player?.play() }
        }
        .onChange(of: isCurrent) { _, current in
            if current { player?.play() } else { player?.pause() }
        }
        .onDisappear { player?.pause() }
    }

    private func loadPlayer() async -> AVPlayer? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return nil }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                if let item {
                    continuation.resume(returning: AVPlayer(playerItem: item))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
