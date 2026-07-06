import Foundation
import SwiftData
import CoreLocation

/// One-time enrichment: reverse-geocodes existing restaurants that were saved before we captured
/// city/region/country, so search ("places I ate in Italy") works retroactively. Throttled to
/// respect the geocoder's rate limits, and resumes across launches — it self-terminates once every
/// restaurant has a country.
@MainActor
enum LocationBackfillService {

    /// Cap per run so we never hammer the geocoder; the rest is picked up on later launches.
    private static let perRunLimit = 60
    private static var isRunning = false

    static func backfillIfNeeded(in context: ModelContext) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let descriptor = FetchDescriptor<Restaurant>(predicate: #Predicate { $0.country == nil })
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        let geocoder = CLGeocoder()
        var processed = 0

        for restaurant in pending {
            if processed >= perRunLimit { break }
            let location = CLLocation(latitude: restaurant.latitude, longitude: restaurant.longitude)
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                if let placemark = placemarks.first {
                    if restaurant.city == nil { restaurant.city = placemark.locality }
                    if restaurant.region == nil { restaurant.region = placemark.administrativeArea }
                    restaurant.country = placemark.country ?? restaurant.country
                    try? context.save()
                }
            } catch {
                // Rate-limited or offline — stop and try again on a future launch.
                break
            }
            processed += 1
            try? await Task.sleep(nanoseconds: 1_200_000_000) // ~1.2s between requests
        }
    }
}
