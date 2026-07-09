import Foundation
import SwiftData
import CoreLocation

/// Turns synced card charges into visits: enriches an existing photo-visit at the same place/day, or
/// creates a new photo-less visit. Deduped by Plaid's transaction id, so re-running is safe.
@MainActor
enum CardVisitIngestor {
    /// A charge within this distance of a photo-visit's place, on the same day, is the same meal.
    private static let mergeDistanceMeters: CLLocationDistance = 250

    @discardableResult
    static func ingest(_ transactions: [CardTransaction], in context: ModelContext) -> Int {
        guard !transactions.isEmpty else { return 0 }

        let allVisits = (try? context.fetch(FetchDescriptor<Visit>())) ?? []
        let alreadyLinked = Set(allVisits.compactMap { $0.cardTransactionID })
        let calendar = Calendar.current

        var created = 0

        for txn in transactions {
            if alreadyLinked.contains(txn.transactionId) { continue }
            guard let date = parseDate(txn.date) else { continue }

            // Enrich an existing photo-visit if one lines up.
            if let match = mergeCandidate(for: txn, date: date, among: allVisits, calendar: calendar) {
                match.cardTransactionID = txn.transactionId
                match.amount = txn.amount
                match.currencyCode = txn.isoCurrencyCode
                continue
            }

            // Otherwise, a new photo-less visit.
            let visit = Visit(
                date: date,
                restaurant: resolveRestaurant(for: txn, in: context),
                latitude: txn.latitude,
                longitude: txn.longitude
            )
            visit.cardTransactionID = txn.transactionId
            visit.amount = txn.amount
            visit.currencyCode = txn.isoCurrencyCode
            context.insert(visit)
            created += 1
        }

        try? context.save()
        return created
    }

    /// Undo card ingestion locally (on disconnect or account deletion): remove card-only visits, and
    /// strip the charge info from photo-visits that were merely enriched (keeping the visit).
    static func removeCardData(in context: ModelContext) {
        let visits = (try? context.fetch(FetchDescriptor<Visit>())) ?? []
        for visit in visits where visit.cardTransactionID != nil {
            if visit.photos.isEmpty {
                context.delete(visit)
            } else {
                visit.cardTransactionID = nil
                visit.amount = nil
                visit.currencyCode = nil
            }
        }
        try? context.save()
    }

    // MARK: - Matching

    private static func mergeCandidate(
        for txn: CardTransaction,
        date: Date,
        among visits: [Visit],
        calendar: Calendar
    ) -> Visit? {
        let day = calendar.startOfDay(for: date)
        let sameDay = visits.filter {
            $0.deletedAt == nil
                && $0.cardTransactionID == nil   // don't attach two charges to one visit
                && !$0.photos.isEmpty            // only enrich real photo-visits
                && calendar.startOfDay(for: $0.date) == day
        }
        guard !sameDay.isEmpty else { return nil }

        // Prefer proximity when the charge has coordinates.
        if let lat = txn.latitude, let lon = txn.longitude {
            let origin = CLLocation(latitude: lat, longitude: lon)
            let near = sameDay.compactMap { visit -> (Visit, CLLocationDistance)? in
                guard let coord = visit.restaurant?.coordinate else { return nil }
                let distance = origin.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
                return distance <= mergeDistanceMeters ? (visit, distance) : nil
            }
            if let best = near.min(by: { $0.1 < $1.1 }) { return best.0 }
        }

        // Fall back to a fuzzy merchant-name match.
        let merchant = normalized(txn.merchantName ?? txn.name ?? "")
        guard !merchant.isEmpty else { return nil }
        return sameDay.first { visit in
            guard let name = visit.restaurant?.name else { return false }
            let candidate = normalized(name)
            return candidate == merchant || candidate.contains(merchant) || merchant.contains(candidate)
        }
    }

    private static func resolveRestaurant(for txn: CardTransaction, in context: ModelContext) -> Restaurant? {
        let raw = (txn.merchantName ?? txn.name)?.trimmingCharacters(in: .whitespaces)
        guard let raw, !raw.isEmpty else { return nil }
        let name = cleanedMerchant(raw)

        let descriptor = FetchDescriptor<Restaurant>(predicate: #Predicate { $0.name == name })
        let matches = (try? context.fetch(descriptor)) ?? []
        if let lat = txn.latitude, let lon = txn.longitude {
            if let existing = matches.first(where: {
                abs($0.latitude - lat) < 0.001 && abs($0.longitude - lon) < 0.001
            }) { return existing }
        } else if let existing = matches.first {
            return existing
        }

        let restaurant = Restaurant(name: name, latitude: txn.latitude ?? 0, longitude: txn.longitude ?? 0)
        context.insert(restaurant)
        return restaurant
    }

    // MARK: - Helpers

    private static func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }

    /// Strip common payment-processor prefixes from a raw descriptor. Plaid's `merchant_name` is
    /// usually already clean, so this mostly helps the `name` fallback.
    private static func cleanedMerchant(_ raw: String) -> String {
        var result = raw
        for prefix in ["SQ *", "TST* ", "TST*", "PAYPAL *", "PY *", "SP "] {
            if result.uppercased().hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func normalized(_ string: String) -> String {
        string.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
