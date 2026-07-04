import Foundation
import SwiftData
import CoreLocation

@Model
final class Restaurant {
    var name: String
    var latitude: Double
    var longitude: Double
    var address: String?
    var mapItemIdentifier: String?

    @Relationship(deleteRule: .cascade, inverse: \Visit.restaurant)
    var visits: [Visit] = []

    init(name: String, latitude: Double, longitude: Double, address: String? = nil, mapItemIdentifier: String? = nil) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.mapItemIdentifier = mapItemIdentifier
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

@Model
final class Visit {
    var date: Date
    var restaurant: Restaurant?
    var isConfirmed: Bool
    var userNote: String?
    var occasion: String?

    @Relationship(deleteRule: .cascade, inverse: \PhotoAsset.visit)
    var photos: [PhotoAsset] = []

    @Relationship(deleteRule: .cascade, inverse: \VoiceNote.visit)
    var voiceNotes: [VoiceNote] = []

    init(date: Date, restaurant: Restaurant? = nil, isConfirmed: Bool = false) {
        self.date = date
        self.restaurant = restaurant
        self.isConfirmed = isConfirmed
    }

    /// Combined searchable text for LLM queries
    var searchableDescription: String {
        var parts: [String] = []
        if let restaurant { parts.append("Restaurant: \(restaurant.name)") }
        parts.append("Date: \(date.formatted(date: .abbreviated, time: .shortened))")
        if let occasion, !occasion.isEmpty { parts.append("Occasion: \(occasion)") }
        if let userNote, !userNote.isEmpty { parts.append("Note: \(userNote)") }
        let transcripts = voiceNotes.compactMap { $0.transcript }.joined(separator: " ")
        if !transcripts.isEmpty { parts.append("Voice notes: \(transcripts)") }
        return parts.joined(separator: " | ")
    }
}

@Model
final class PhotoAsset {
    var localIdentifier: String
    var takenAt: Date
    var latitude: Double?
    var longitude: Double?
    var visit: Visit?

    init(localIdentifier: String, takenAt: Date, latitude: Double? = nil, longitude: Double? = nil) {
        self.localIdentifier = localIdentifier
        self.takenAt = takenAt
        self.latitude = latitude
        self.longitude = longitude
    }
}

@Model
final class VoiceNote {
    var audioFilename: String  // relative to Documents dir
    var transcript: String?
    var recordedAt: Date
    var visit: Visit?

    init(audioFilename: String, recordedAt: Date, transcript: String? = nil) {
        self.audioFilename = audioFilename
        self.recordedAt = recordedAt
        self.transcript = transcript
    }

    var audioURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(audioFilename)
    }
}
