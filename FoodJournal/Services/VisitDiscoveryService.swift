import Foundation
import Photos
import SwiftData
import CoreLocation

@MainActor
final class VisitDiscoveryService {
    let modelContext: ModelContext

    /// How many dining-positive photos a cluster needs before it's accepted as a restaurant
    /// visit. `1` catches quick single-dish meals; raise it to cut false positives further.
    static let minimumDiningPhotosPerCluster = 1

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

        // 5. For each cluster, gate on dining evidence, then look up a restaurant and insert a Visit.
        //    Screening is cached per-photo (see ScreenedPhoto) so rescans don't re-run Vision on
        //    photos we've already looked at — including rejected, non-dining ones.
        var screenCache = try loadScreenCache()
        var newScreens: [(id: String, isDining: Bool)] = []
        var createdCount = 0

        for cluster in clusters {
            // ML gate: only treat this cluster as a restaurant visit if at least one photo
            // actually looks like dining (food, or people around a table). This is what stops
            // every geotagged photo from becoming a "visit". Context photos in the cluster
            // (storefront, menu, group shots) still ride along in the album below.
            var diningMatches = 0
            var looksLikeDining = false
            for asset in cluster.assets {
                let id = asset.localIdentifier
                let isDining: Bool
                if let cached = screenCache[id] {
                    isDining = cached
                } else {
                    isDining = await RestaurantPhotoClassifier.signals(for: asset).isDining
                    screenCache[id] = isDining
                    newScreens.append((id, isDining))
                }
                if isDining {
                    diningMatches += 1
                    if diningMatches >= Self.minimumDiningPhotosPerCluster {
                        looksLikeDining = true
                        break
                    }
                }
            }
            guard looksLikeDining else { continue }

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

        // Persist newly screened photos so future scans skip Vision for them.
        for screen in newScreens {
            modelContext.insert(ScreenedPhoto(localIdentifier: screen.id, isDining: screen.isDining))
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

    /// Preload every prior screening result into a `[localIdentifier: isDining]` map so the
    /// gate can check the cache with a dictionary lookup instead of a per-photo fetch.
    private func loadScreenCache() throws -> [String: Bool] {
        let screened = try modelContext.fetch(FetchDescriptor<ScreenedPhoto>())
        return Dictionary(
            screened.map { ($0.localIdentifier, $0.isDining) },
            uniquingKeysWith: { current, _ in current }
        )
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
            // Backfill fields that may not have been captured when the record was created.
            if existing.websiteHost == nil, let host = candidate.websiteHost {
                existing.websiteHost = host
            }
            if existing.categoryRawValue == nil, let category = candidate.categoryRawValue {
                existing.categoryRawValue = category
            }
            return existing
        }

        let restaurant = Restaurant(
            name: candidate.name,
            latitude: candidate.coordinate.latitude,
            longitude: candidate.coordinate.longitude,
            address: candidate.address,
            mapItemIdentifier: candidate.mapItemIdentifier,
            websiteHost: candidate.websiteHost,
            categoryRawValue: candidate.categoryRawValue
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
