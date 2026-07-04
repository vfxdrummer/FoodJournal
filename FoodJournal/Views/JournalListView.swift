import SwiftUI
import SwiftData

struct JournalListView: View {
    @Query(
        filter: #Predicate<Visit> { $0.isConfirmed },
        sort: [SortDescriptor(\Visit.date, order: .reverse)]
    )
    private var visits: [Visit]

    var body: some View {
        NavigationStack {
            Group {
                if visits.isEmpty {
                    ContentUnavailableView(
                        "Your journal is empty",
                        systemImage: "book.closed",
                        description: Text("Confirm visits in the Review tab and they'll show up here.")
                    )
                } else {
                    List {
                        ForEach(visits) { visit in
                            NavigationLink(destination: VisitDetailView(visit: visit)) {
                                HStack {
                                    if let photo = visit.photos.first {
                                        PhotoThumbnailView(
                                            localIdentifier: photo.localIdentifier,
                                            targetSize: CGSize(width: 120, height: 120)
                                        )
                                        .frame(width: 55, height: 55)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(visit.restaurant?.name ?? "Unknown place")
                                            .font(.headline)
                                        if let occ = visit.occasion, !occ.isEmpty {
                                            Text(occ).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Text(visit.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Journal")
        }
    }
}
