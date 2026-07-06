import SwiftUI
import SwiftData

/// Apple-Photos-style trash: visits you deleted linger here, recoverable, until their grace period
/// runs out. Restore brings a visit back losslessly; Delete Permanently removes it for good.
struct RecentlyDeletedView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<Visit> { $0.deletedAt != nil },
        sort: \Visit.deletedAt,
        order: .reverse
    )
    private var deletedVisits: [Visit]

    @State private var confirmingPurge: Visit?
    @State private var confirmingEmptyAll = false

    var body: some View {
        Group {
            if deletedVisits.isEmpty {
                ContentUnavailableView(
                    "Nothing Deleted",
                    systemImage: "trash",
                    description: Text("Visits you delete appear here for 30 days, so you can restore them before they're gone for good.")
                )
            } else {
                List {
                    Section {
                        ForEach(deletedVisits) { visit in
                            row(for: visit)
                                .swipeActions(edge: .leading) {
                                    Button {
                                        VisitDeletion.restore(visit, in: modelContext)
                                    } label: {
                                        Label("Restore", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        confirmingPurge = visit
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    } footer: {
                        Text("Deleted visits are permanently removed 30 days after deletion.")
                    }
                }
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !deletedVisits.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Empty", role: .destructive) { confirmingEmptyAll = true }
                }
            }
        }
        .confirmationDialog(
            "Delete this visit permanently?",
            isPresented: Binding(
                get: { confirmingPurge != nil },
                set: { if !$0 { confirmingPurge = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmingPurge
        ) { visit in
            Button("Delete Permanently", role: .destructive) {
                VisitDeletion.deletePermanently(visit, in: modelContext)
                confirmingPurge = nil
            }
            Button("Cancel", role: .cancel) { confirmingPurge = nil }
        } message: { _ in
            Text("This can't be undone. Notes and voice memos for this visit will be lost.")
        }
        .confirmationDialog(
            "Empty Recently Deleted?",
            isPresented: $confirmingEmptyAll,
            titleVisibility: .visible
        ) {
            Button("Delete All Permanently", role: .destructive) {
                for visit in deletedVisits {
                    VisitDeletion.deletePermanently(visit, in: modelContext)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All \(deletedVisits.count) deleted visits will be removed for good.")
        }
    }

    @ViewBuilder
    private func row(for visit: Visit) -> some View {
        HStack(spacing: 12) {
            if let photo = visit.coverPhoto {
                PhotoThumbnailView(
                    localIdentifier: photo.localIdentifier,
                    targetSize: CGSize(width: 120, height: 120)
                )
                .frame(width: 55, height: 55)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .opacity(0.6)
            }
            VStack(alignment: .leading, spacing: 4) {
                RestaurantNameLabel(restaurant: visit.restaurant)
                Text(visit.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(remainingText(for: visit))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                VisitDeletion.restore(visit, in: modelContext)
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .tint(.green)
        }
    }

    /// e.g. "Deleted today · 30 days left" — a gentle countdown to the auto-purge.
    private func remainingText(for visit: Visit) -> String {
        guard let deletedAt = visit.deletedAt else { return "" }
        let expiry = deletedAt.addingTimeInterval(VisitDeletion.gracePeriod)
        let daysLeft = max(0, Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0)
        let deletedWhen = deletedAt.formatted(.relative(presentation: .named))
        return "Deleted \(deletedWhen) · \(daysLeft) day\(daysLeft == 1 ? "" : "s") left"
    }
}
