import SwiftUI
import SwiftData

/// A round face-crop icon for a person, with a symbol fallback.
struct FaceIcon: View {
    let data: Data?
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.quaternary, lineWidth: 0.5))
    }
}

/// People you've dined with — face icons ranked by how many visits you share, no names needed.
struct PeopleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var people: [Person]
    @StateObject private var faceService = FacePeopleService()

    @State private var isSelecting = false
    @State private var selected: Set<PersistentIdentifier> = []
    @State private var showUndoBanner = false
    @State private var mergedCount = 0

    private var rankedPeople: [Person] {
        people
            .filter { !$0.faces.isEmpty }
            .sorted {
                $0.diningCount != $1.diningCount
                    ? $0.diningCount > $1.diningCount
                    : $0.photoCount > $1.photoCount
            }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !isSelecting {
                    scanBar
                    Divider()
                }

                if rankedPeople.isEmpty {
                    ContentUnavailableView(
                        "No people yet",
                        systemImage: "person.2",
                        description: Text("Tap “Find people” to detect who you've dined with — no names needed, just faces.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 20) {
                            ForEach(rankedPeople) { person in
                                cellContainer(person)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(isSelecting ? "\(selected.count) selected" : "People")
            .toolbar { toolbarContent }
            .overlay(alignment: .bottom) { undoBanner }
            .animation(.default, value: isSelecting)
        }
    }

    private let gridColumns = [GridItem(.adaptive(minimum: 96), spacing: 16)]

    // MARK: - Cells

    @ViewBuilder
    private func cellContainer(_ person: Person) -> some View {
        let id = person.persistentModelID
        if isSelecting {
            Button {
                toggle(id)
            } label: {
                cell(for: person, isSelected: selected.contains(id))
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(destination: PersonDetailView(person: person, faceService: faceService)) {
                cell(for: person, isSelected: false)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4).onEnded { _ in enterSelection(with: id) }
            )
        }
    }

    private func cell(for person: Person, isSelected: Bool) -> some View {
        FaceIcon(data: person.representativeFaceData, size: 88)
            .overlay {
                if isSelected {
                    Circle().stroke(Color.accentColor, lineWidth: 3)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isSelecting {
                    Text("\(person.diningCount)")
                        .font(.caption).bold()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor, in: Capsule())
                        .overlay(Capsule().stroke(Color(.systemBackground), lineWidth: 1.5))
                }
            }
            .overlay(alignment: .topLeading) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .white)
                        .background(Circle().fill(.black.opacity(0.25)))
                }
            }
            .opacity(isSelecting && !isSelected ? 0.55 : 1)
    }

    // MARK: - Toolbar & banner

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { exitSelection() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Merge (\(selected.count))") { performMerge() }
                    .disabled(selected.count < 2)
            }
        } else if !rankedPeople.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Select") { isSelecting = true }
            }
        }
    }

    @ViewBuilder
    private var undoBanner: some View {
        if showUndoBanner {
            HStack(spacing: 12) {
                Text("Merged \(mergedCount) faces into one")
                    .font(.subheadline)
                Spacer()
                Button("Undo") {
                    faceService.undoLastMerge(in: modelContext)
                    withAnimation { showUndoBanner = false }
                }
                .font(.subheadline.bold())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.quaternary, lineWidth: 0.5))
            .padding(.horizontal)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Actions

    private func enterSelection(with id: PersistentIdentifier) {
        isSelecting = true
        selected = [id]
    }

    private func toggle(_ id: PersistentIdentifier) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func exitSelection() {
        isSelecting = false
        selected = []
    }

    private func performMerge() {
        let toMerge = rankedPeople.filter { selected.contains($0.persistentModelID) }
        guard toMerge.count >= 2 else { return }
        mergedCount = toMerge.count
        faceService.mergeMany(toMerge, in: modelContext)
        exitSelection()
        withAnimation { showUndoBanner = true }
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            withAnimation { showUndoBanner = false }
        }
    }

    @ViewBuilder
    private var scanBar: some View {
        VStack(spacing: 8) {
            if faceService.isScanning {
                ProgressView(value: Double(faceService.processed), total: Double(max(faceService.total, 1)))
                Text("Scanning photos for faces… \(faceService.processed)/\(faceService.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await faceService.scan(in: modelContext) }
                } label: {
                    Label(rankedPeople.isEmpty ? "Find people" : "Update people", systemImage: "person.crop.square.badge.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
