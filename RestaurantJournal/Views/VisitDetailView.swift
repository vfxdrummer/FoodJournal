import SwiftUI
import SwiftData

struct VisitDetailView: View {
    @Bindable var visit: Visit
    @Environment(\.modelContext) private var modelContext

    @State private var showingRecorder = false
    @State private var showingEditPlace = false
    @State private var showingShare = false
    @State private var viewerPhotoID: String?
    @StateObject private var player = AudioPlayerService()

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        Form {
            Section("Place") {
                if let r = visit.restaurant {
                    RestaurantNameLabel(restaurant: r, logoSize: 24)
                    if let addr = r.address { Text(addr).font(.caption).foregroundStyle(.secondary) }
                    if let apple = r.appleMapsURL {
                        Link(destination: apple) {
                            Label("Open in Apple Maps", systemImage: "map")
                        }
                    }
                    if let google = r.googleMapsURL {
                        Link(destination: google) {
                            Label("Open in Google Maps", systemImage: "mappin.and.ellipse")
                        }
                    }
                } else {
                    Text("Unknown restaurant").foregroundStyle(.secondary)
                }
                Text(visit.date.formatted(date: .complete, time: .shortened))
                    .font(.caption)

                Button {
                    showingEditPlace = true
                } label: {
                    Label(visit.restaurant == nil ? "Set place" : "Wrong place? Change it",
                          systemImage: "mappin.and.ellipse")
                }
            }

            Section("Occasion") {
                TextField("e.g. Sarah's birthday, after the game", text: Binding(
                    get: { visit.occasion ?? "" },
                    set: { visit.occasion = $0.isEmpty ? nil : $0 }
                ))
            }

            Section("Notes") {
                TextField("Anything worth remembering?", text: Binding(
                    get: { visit.userNote ?? "" },
                    set: { visit.userNote = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(3...6)
            }

            Section("Voice notes") {
                ForEach(visit.voiceNotes, id: \.audioFilename) { note in
                    HStack(alignment: .top, spacing: 12) {
                        Button {
                            player.toggle(note.audioURL)
                        } label: {
                            Image(systemName: player.isPlaying(note.audioURL) ? "stop.circle.fill" : "play.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.tint)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Transcript", text: Binding(
                                get: { note.transcript ?? "" },
                                set: {
                                    note.transcript = $0.isEmpty ? nil : $0
                                    try? modelContext.save()
                                }
                            ), axis: .vertical)
                            .lineLimit(1...6)
                            Text(note.recordedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteVoiceNotes)

                Button {
                    showingRecorder = true
                } label: {
                    Label("Record voice note", systemImage: "mic.circle.fill")
                }
            }

            if !visit.photos.isEmpty {
                Section("Photos") {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(visit.photos, id: \.localIdentifier) { photo in
                            // A clear 1:1 square defines a deterministic cell size (width == height),
                            // with the photo overlaid and clipped. This avoids the unbounded
                            // ".aspectRatio(.fill)" that can trigger a UICollectionView layout loop.
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    PhotoThumbnailView(
                                        localIdentifier: photo.localIdentifier,
                                        targetSize: CGSize(width: 300, height: 300)
                                    )
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(alignment: .topLeading) {
                                    if visit.coverPhoto?.localIdentifier == photo.localIdentifier {
                                        Image(systemName: "star.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.white)
                                            .padding(4)
                                            .background(Color.accentColor, in: Circle())
                                            .padding(4)
                                    }
                                }
                                .contentShape(RoundedRectangle(cornerRadius: 6))
                                .onTapGesture { viewerPhotoID = photo.localIdentifier }
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
            }
        }
        .navigationTitle(visit.restaurant?.name ?? "Visit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingShare = true
                } label: {
                    Label("Recommend", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showingRecorder) {
            VoiceRecorderSheet(visit: visit)
        }
        .sheet(isPresented: $showingEditPlace) {
            EditPlaceView(visit: visit)
        }
        .sheet(isPresented: $showingShare) {
            ShareRecommendationView(visit: visit)
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { viewerPhotoID != nil },
                set: { if !$0 { viewerPhotoID = nil } }
            )
        ) {
            if let id = viewerPhotoID {
                PhotoViewerView(
                    visit: visit,
                    photoIDs: visit.photos.map(\.localIdentifier),
                    selection: id
                )
            }
        }
        .onChange(of: visit.occasion) { _, _ in try? modelContext.save() }
        .onChange(of: visit.userNote) { _, _ in try? modelContext.save() }
        .onDisappear { player.stop() }
    }

    private func deleteVoiceNotes(_ offsets: IndexSet) {
        player.stop()
        for index in offsets {
            let note = visit.voiceNotes[index]
            try? FileManager.default.removeItem(at: note.audioURL)
            modelContext.delete(note)
        }
        try? modelContext.save()
    }
}
