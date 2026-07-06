import Foundation
import MapKit

/// Live place/address autocomplete for the "change place" flow. Wraps `MKLocalSearchCompleter` and
/// publishes suggestions as the user types, biased toward a region near the visit. Delegate
/// callbacks arrive on the main thread, so publishing directly is safe.
final class AddressSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var suggestions: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    /// Bias results toward the area around the visit.
    func setRegion(_ region: MKCoordinateRegion) {
        completer.region = region
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        completer.queryFragment = trimmed
        if trimmed.isEmpty { suggestions = [] }
    }

    /// Resolve a suggestion to a full map item (coordinates + address).
    func resolve(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        let request = MKLocalSearch.Request(completion: completion)
        return try? await MKLocalSearch(request: request).start().mapItems.first
    }

    // MARK: - MKLocalSearchCompleterDelegate

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}
