import Foundation
import Photos
import SwiftData
import CoreLocation

@MainActor
final class VisitDiscoveryService {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Scan the Photos library, cluster, look up restaurants, insert unconfirmed Visits.
    /// - Returns: number of new visits created.
    @discardableResult
    func scanForNewVisits() async throws -> Int {
        // 1. Request photo library authorization
        let status = await requestPhotoAuth()
        guard status == .authorized || status == .limited else {
            throw DiscoveryError.photoAuthDenied
        }

        // 2. Find latest already-imported photo date to scan only newer photos
        let latestImportedDate = try latestPhotoDate()

        // 3. Fetch new assets
        let assets = PhotoClusteringService.fetchAssets(since: latestImportedDate)
        guard !assets.isEmpty else { return 0 }

        // 4. Cluster
        let clusters = PhotoClusteringService.cluster(assets)

        // 5. For each cluster, look up a restaurant candidate and insert a Visit
        var createdCount = 0
        for cluster in clusters {
            let candidates = await RestaurantLookupService.lookup(near: cluster.centroid)
            guard let best = candidates.first else { continue }

            let restaurant = try findOrCreateRestaurant(candidate: best)
            let visit = Visit(date: cluster.startDate, restaurant: restaurant, isConfirmed: false)
            modelContext.insert(visit)

            for asset in cluster.assets {
                let photo = PhotoAsset(
                    localIdentifier: asset.localIdentifier,
                    takenAt: asset.creationDate ?? cluster.startDate,
                    latitude: asset.location?.coordinate.latitude,
                    longitude: asset.location?.coordinate.longitude
                )
                photo.visit = visit
                modelContext.insert(photo)
            }
            createdCount += 1
        }

        try modelContext.save()
        return createdCount
    }

    // MARK: - Helpers

    private func requestPhotoAuth() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func latestPhotoDate() throws -> Date? {
        var descriptor = FetchDescriptor<PhotoAsset>(
            sortBy: [SortDescriptor(\.takenAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.takenAt
    }

    private func findOrCreateRestaurant(candidate: RestaurantCandidate) throws -> Restaurant {
        // Match by name + rough location
        let name = candidate.name
        let descriptor = FetchDescriptor<Restaurant>(
            predicate: #Predicate { $0.name == name }
        )
        let matches = try modelContext.fetch(descriptor)

        if let existing = matches.first(where: { r in
            let dLat = r.latitude - candidate.coordinate.latitude
            let dLon = r.longitude - candidate.coordinate.longitude
            return abs(dLat) < 0.0005 && abs(dLon) < 0.0005
        }) {
            return existing
        }

        let restaurant = Restaurant(
            name: candidate.name,
            latitude: candidate.coordinate.latitude,
            longitude: candidate.coordinate.longitude,
            address: candidate.address,
            mapItemIdentifier: candidate.mapItemIdentifier
        )
        modelContext.insert(restaurant)
        return restaurant
    }

    enum DiscoveryError: LocalizedError {
        case photoAuthDenied
        var errorDescription: String? {
            switch self {
            case .photoAuthDenied: return "Photo library access is required to discover restaurant visits."
            }
        }
    }
}
