import SwiftUI
import SwiftData

/// Full-screen, swipeable photo viewer for a visit's album, with a one-tap "Set as cover".
struct PhotoViewerView: View {
    @Bindable var visit: Visit
    let photoIDs: [String]

    @State var selection: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private var isCurrentCover: Bool {
        visit.coverPhoto?.localIdentifier == selection
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                TabView(selection: $selection) {
                    ForEach(photoIDs, id: \.self) { id in
                        LargePhotoView(localIdentifier: id)
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
