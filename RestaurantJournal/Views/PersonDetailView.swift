import SwiftUI
import SwiftData

/// A person's shared history: their face, how many times you've dined together, and every place —
/// plus a Merge action to fix an over-split cluster.
struct PersonDetailView: View {
    @Bindable var person: Person
    let faceService: FacePeopleService

    @Environment(\.modelContext) private var modelContext
    @State private var showingMerge = false

    private var places: [Visit] {
        person.uniqueVisits.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        FaceIcon(data: person.representativeFaceData, size: 96)
                        Text("Dined together \(person.diningCount) time\(person.diningCount == 1 ? "" : "s")")
                            .font(.headline)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("Places you've dined together") {
                ForEach(places) { visit in
                    NavigationLink(destination: VisitDetailView(visit: visit)) {
                        HStack {
                            RestaurantNameLabel(restaurant: visit.restaurant)
                            Spacer()
                            Text(visit.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Person")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingMerge = true
                } label: {
                    Label("Merge", systemImage: "person.2.badge.gearshape")
                }
            }
        }
        .sheet(isPresented: $showingMerge) {
            MergePersonSheet(target: person, faceService: faceService)
        }
    }
}

/// Pick another person who is actually the same individual; their faces fold into the target.
private struct MergePersonSheet: View {
    @Bindable var target: Person
    let faceService: FacePeopleService

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var people: [Person]

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 12)]

    private var others: [Person] {
        people
            .filter { $0.persistentModelID != target.persistentModelID && !$0.faces.isEmpty }
            .sorted { $0.diningCount > $1.diningCount }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if others.isEmpty {
                    ContentUnavailableView("No one to merge", systemImage: "person.2",
                                           description: Text("There are no other people to merge in."))
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(others) { person in
                            Button {
                                faceService.merge([person], into: target, in: modelContext)
                                dismiss()
                            } label: {
                                VStack(spacing: 4) {
                                    FaceIcon(data: person.representativeFaceData, size: 72)
                                    Text("\(person.diningCount)×")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Same person as…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
