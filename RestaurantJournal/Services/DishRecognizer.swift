import Foundation
import Photos
import Vision
import UIKit

/// Runs Vision image classification on a visit's photos to find the food shots and guess the dish
/// ("Pizza", "Salad", "Coffee"). Results are cached per photo for the app session, so reopening a
/// visit is instant.
@MainActor
final class DishRecognizer: ObservableObject {
    /// localIdentifier → dish labels. `nil` = not analyzed yet, `[]` = analyzed, no food.
    @Published private(set) var results: [String: [String]] = [:]

    private static var cache: [String: [String]] = [:]
    private var inFlight: Set<String> = []

    func recognize(_ localIdentifiers: [String]) {
        for id in localIdentifiers {
            if results[id] != nil || inFlight.contains(id) { continue }
            if let cached = Self.cache[id] { results[id] = cached; continue }
            inFlight.insert(id)
            Task {
                let labels = await Self.dishLabels(for: id)
                Self.cache[id] = labels
                self.results[id] = labels
                self.inFlight.remove(id)
            }
        }
    }

    // MARK: - Vision

    private static func dishLabels(for localIdentifier: String) async -> [String] {
        guard let cgImage = await loadCGImage(localIdentifier) else { return [] }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
                let request = VNClassifyImageRequest()
                guard (try? handler.perform([request])) != nil,
                      let observations = request.results else {
                    continuation.resume(returning: [])
                    return
                }
                var labels: [String] = []
                for observation in observations
                where observation.hasMinimumPrecision(0.35, forRecall: 0.3) {
                    let identifier = observation.identifier.lowercased()
                    if genericTerms.contains(identifier) { continue }
                    guard foodStems.contains(where: identifier.contains) else { continue }
                    let pretty = prettify(observation.identifier)
                    if !labels.contains(pretty) { labels.append(pretty) }
                    if labels.count == 2 { break }
                }
                continuation.resume(returning: labels)
            }
        }
    }

    private static func loadCGImage(_ localIdentifier: String) async -> CGImage? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isSynchronous = false

        return await withCheckedContinuation { continuation in
            var didResume = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 299, height: 299),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if didResume { return }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if degraded && image != nil { return } // wait for the full-quality result
                didResume = true
                continuation.resume(returning: image?.cgImage)
            }
        }
    }

    private static func prettify(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    /// Generic labels to ignore — we want the dish, not "food" or "plate".
    private static let genericTerms: Set<String> = [
        "food", "meal", "dish", "plate", "platter", "cuisine", "tableware", "cutlery",
        "dishware", "produce", "ingredient", "recipe", "dessert",
    ]

    /// Food/dish word stems — a classification label must contain one of these to count as a meal.
    private static let foodStems: [String] = [
        "pizza", "burger", "hamburger", "cheeseburger", "sandwich", "taco", "burrito", "quesadilla",
        "nacho", "sushi", "sashimi", "ramen", "noodle", "pasta", "spaghetti", "lasagna", "salad",
        "soup", "steak", "chicken", "wing", "fries", "fry", "rice", "curry", "pho", "dumpling",
        "dim sum", "bread", "bagel", "croissant", "pastry", "muffin", "pretzel", "pancake", "waffle",
        "egg", "omelet", "bacon", "sausage", "hotdog", "hot dog", "seafood", "shrimp", "lobster",
        "crab", "oyster", "fish", "salmon", "barbecue", "bbq", "ribs", "cake", "pie", "donut",
        "doughnut", "cookie", "brownie", "ice cream", "icecream", "gelato", "chocolate", "cheese",
        "guacamole", "salsa", "hummus", "falafel", "kebab", "gyro", "dosa", "pad thai", "poke",
        "coffee", "espresso", "latte", "cappuccino", "cortado", "tea", "matcha", "smoothie", "juice",
        "beer", "wine", "cocktail", "margarita", "martini", "sangria", "mimosa", "milkshake",
    ]
}
