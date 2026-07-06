import Foundation
import SwiftData
import Vision
import UIKit

/// Scans the journal's photos for faces and clusters them into `Person` records using Vision
/// feature prints — so the People tab can rank who you've dined with. Runs on demand with progress,
/// and skips photos it has already scanned.
@MainActor
final class FacePeopleService: ObservableObject {
    @Published var isScanning = false
    @Published var processed = 0
    @Published var total = 0

    /// Feature-print distance below which two faces are treated as the same person. Feature prints
    /// aren't a true face-recognition model, so this needs tuning on real photos — lower = stricter
    /// (more, smaller clusters the user can merge); higher = looser (risks merging different people).
    static var clusterThreshold: Float = 0.65

    func scan(in context: ModelContext) async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        // Photos we haven't scanned for faces yet.
        let scannedIDs = Set(((try? context.fetch(FetchDescriptor<FaceScannedPhoto>())) ?? []).map(\.localIdentifier))
        let allPhotos = (try? context.fetch(FetchDescriptor<PhotoAsset>())) ?? []
        let todo = allPhotos.filter { !scannedIDs.contains($0.localIdentifier) }

        processed = 0
        total = todo.count
        guard !todo.isEmpty else { return }

        // Load existing clusters so new faces join the right person across rescans.
        var clusters: [(person: Person, print: VNFeaturePrintObservation)] = []
        for person in ((try? context.fetch(FetchDescriptor<Person>())) ?? []) {
            if let data = person.representativeFeaturePrintData,
               let print = FaceProcessing.featurePrint(from: data) {
                clusters.append((person, print))
            }
        }

        for photo in todo {
            let localID = photo.localIdentifier
            let visit = photo.visit

            if let cgImage = await loadCGImage(localID: localID) {
                let faces = await Task.detached { FaceProcessing.faces(in: cgImage) }.value
                for face in faces {
                    guard let print = FaceProcessing.featurePrint(from: face.featurePrintData) else { continue }
                    let person = assign(print: print, cropData: face.cropData, featurePrintData: face.featurePrintData,
                                        clusters: &clusters, in: context)
                    context.insert(DetectedFace(
                        photoLocalIdentifier: localID,
                        faceCropData: face.cropData,
                        person: person,
                        visit: visit
                    ))
                }
            }

            context.insert(FaceScannedPhoto(localIdentifier: localID))
            processed += 1
            if processed % 20 == 0 { try? context.save() }
        }
        try? context.save()
    }

    /// Snapshot of a merge, kept so it can be undone. Holds the absorbed clusters' data and their
    /// (still-alive) face records, which just need their `person` pointed back.
    struct MergeUndo {
        struct Group {
            let representativeFaceData: Data?
            let representativeFeaturePrintData: Data?
            let faces: [DetectedFace]
        }
        let groups: [Group]
    }

    /// The most recent merge, available to undo. `nil` once undone or superseded.
    @Published var lastMerge: MergeUndo?

    /// Merge several people into one. The person you've dined with most becomes the keeper.
    func mergeMany(_ people: [Person], in context: ModelContext) {
        let valid = people.filter { !$0.faces.isEmpty }
        guard valid.count >= 2 else { return }
        let survivor = valid.max {
            ($0.diningCount, $0.photoCount) < ($1.diningCount, $1.photoCount)
        }!
        merge(valid.filter { $0.persistentModelID != survivor.persistentModelID }, into: survivor, in: context)
    }

    /// Fold `sources` into `survivor`, recording an undo snapshot.
    func merge(_ sources: [Person], into survivor: Person, in context: ModelContext) {
        var groups: [MergeUndo.Group] = []
        for source in sources where source.persistentModelID != survivor.persistentModelID {
            let faces = source.faces
            groups.append(.init(
                representativeFaceData: source.representativeFaceData,
                representativeFeaturePrintData: source.representativeFeaturePrintData,
                faces: faces
            ))
            for face in faces { face.person = survivor }
            context.delete(source)
        }
        guard !groups.isEmpty else { return }
        lastMerge = MergeUndo(groups: groups)
        try? context.save()
    }

    /// Reverse the last merge: recreate the absorbed people and move their faces back.
    func undoLastMerge(in context: ModelContext) {
        guard let merge = lastMerge else { return }
        for group in merge.groups {
            let person = Person(
                representativeFaceData: group.representativeFaceData,
                representativeFeaturePrintData: group.representativeFeaturePrintData
            )
            context.insert(person)
            for face in group.faces { face.person = person }
        }
        lastMerge = nil
        try? context.save()
    }

    // MARK: - Clustering

    private func assign(
        print: VNFeaturePrintObservation,
        cropData: Data,
        featurePrintData: Data,
        clusters: inout [(person: Person, print: VNFeaturePrintObservation)],
        in context: ModelContext
    ) -> Person {
        var best: (index: Int, distance: Float)?
        for (index, cluster) in clusters.enumerated() {
            if let distance = FaceProcessing.distance(print, cluster.print) {
                if best == nil || distance < best!.distance {
                    best = (index, distance)
                }
            }
        }

        if let best, best.distance < Self.clusterThreshold {
            return clusters[best.index].person
        }

        let person = Person(representativeFaceData: cropData, representativeFeaturePrintData: featurePrintData)
        context.insert(person)
        clusters.append((person, print))
        return person
    }

    private func loadCGImage(localID: String) async -> CGImage? {
        await PhotoThumbnailLoader.loadShareImage(localIdentifier: localID, maxDimension: 1000)?.cgImage
    }
}
