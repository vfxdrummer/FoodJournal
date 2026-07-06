import Foundation

extension Restaurant {
    /// An official Google Maps link to the place, by name + address. Opens the Google Maps app or
    /// web to the business without needing a Google Places API key.
    var googleMapsURL: URL? {
        var query = name
        if let address, !address.isEmpty {
            query += ", \(address)"
        }
        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: query)
        ]
        return components?.url
    }

    /// An Apple Maps link to the place — a labeled pin at the stored coordinates, falling back to
    /// the address text. Opens the Maps app on iOS.
    var appleMapsURL: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        var items = [URLQueryItem(name: "q", value: name)]
        if latitude != 0 || longitude != 0 {
            items.append(URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"))
        } else if let address, !address.isEmpty {
            items.append(URLQueryItem(name: "address", value: address))
        }
        components?.queryItems = items
        return components?.url
    }
}
