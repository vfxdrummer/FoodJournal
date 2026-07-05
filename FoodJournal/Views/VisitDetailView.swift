import SwiftUI
import SwiftData

struct VisitDetailView: View {
    @Bindable var visit: Visit
    @Environment(\.modelContext) private var modelContext

    @State private var showingRecorder = false

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
                } else {
                    Text("Unknown restaurant").foregroundStyle(.secondary)
                }
                Text(visit.date.formatted(date: .complete, time: .shortened))
                    .font(.caption)
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.transcript ?? "(no transcript)")
                            .font(.body)
                        Text(note.recordedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
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
                            PhotoThumbnailView(
                                localIdentifier: photo.localIdentifier,
                                targetSize: CGSize(width: 300, height: 300)
                            )
                            .aspectRatio(1, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }

            if !visit.isConfirmed {
                Section {
                    Button("Confirm this visit") {
                        visit.isConfirmed = true
                        try? modelContext.save()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(visit.restaurant?.name ?? "Visit")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingRecorder) {
            VoiceRecorderSheet(visit: visit)
        }
        .onChange(of: visit.occasion) { _, _ in try? modelContext.save() }
        .onChange(of: visit.userNote) { _, _ in try? modelContext.save() }
    }
}
