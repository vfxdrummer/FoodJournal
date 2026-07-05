import SwiftUI
import SwiftData

struct ReviewQueueView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<Visit> { !$0.isConfirmed },
        sort: [SortDescriptor(\Visit.date, order: .reverse)]
    )
    private var unconfirmedVisits: [Visit]

    @State private var isScanning = false
    @State private var scanError: String?

    var body: some View {
        NavigationStack {
            Group {
                if unconfirmedVisits.isEmpty {
                    ContentUnavailableView(
                        "All caught up",
                        systemImage: "checkmark.circle",
                        description: Text("No visits to review. Tap Scan to check for new ones.")
                    )
                } else {
                    List {
                        ForEach(unconfirmedVisits) { visit in
                            ReviewVisitRow(visit: visit, onConfirm: { confirm(visit) }, onReject: { reject(visit) })
                        }
                    }
                }
            }
            .navigationTitle("Review")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: scan) {
                        if isScanning { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(isScanning)
                }
            }
            .alert("Scan failed", isPresented: .constant(scanError != nil), presenting: scanError) { _ in
                Button("OK") { scanError = nil }
            } message: { err in
                Text(err)
            }
        }
    }

    private func scan() {
        isScanning = true
        Task {
            defer { isScanning = false }
            let service = VisitDiscoveryService(modelContext: modelContext)
            do {
                _ = try await service.scanForNewVisits()
            } catch {
                scanError = error.localizedDescription
            }
        }
    }

    private func confirm(_ visit: Visit) {
        visit.isConfirmed = true
        try? modelContext.save()
    }

    private func reject(_ visit: Visit) {
        modelContext.delete(visit)
        try? modelContext.save()
    }
}

private struct ReviewVisitRow: View {
    let visit: Visit
    let onConfirm: () -> Void
    let onReject: () -> Void

    var body: some View {
        NavigationLink(destination: VisitDetailView(visit: visit)) {
            HStack {
                if let firstPhoto = visit.photos.first {
                    PhotoThumbnailView(
                        localIdentifier: firstPhoto.localIdentifier,
                        targetSize: CGSize(width: 120, height: 120)
                    )
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 4) {
                    RestaurantNameLabel(restaurant: visit.restaurant)
                    Text(visit.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(visit.photos.count) photo\(visit.photos.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .swipeActions(edge: .leading) {
            Button(action: onConfirm) {
                Label("Confirm", systemImage: "checkmark")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onReject) {
                Label("Reject", systemImage: "trash")
            }
        }
    }
}
