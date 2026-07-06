import Foundation
import Vision
import UIKit
import CoreGraphics

/// On-device face work: detect faces, crop them, and compute a Vision feature print used to
/// cluster the same person across photos. No shipped model, no names — the face crop is the identity.
enum FaceProcessing {

    struct Face {
        let cropData: Data          // small face image (for the person icon)
        let featurePrintData: Data  // archived VNFeaturePrintObservation (for clustering)
    }

    /// Detect faces in an image and return a crop + feature print for each.
    static func faces(in cgImage: CGImage) -> [Face] {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        let detect = VNDetectFaceRectanglesRequest()
        do { try handler.perform([detect]) } catch { return [] }

        var results: [Face] = []
        for observation in (detect.results ?? []) {
            guard let crop = crop(cgImage, boundingBox: observation.boundingBox),
                  let featurePrintData = featurePrintData(for: crop),
                  let cropData = pngData(from: crop, maxDimension: 220) else { continue }
            results.append(Face(cropData: cropData, featurePrintData: featurePrintData))
        }
        return results
    }

    // MARK: - Clustering helpers

    static func featurePrint(from data: Data) -> VNFeaturePrintObservation? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }

    /// Distance between two feature prints (smaller = more similar). `nil` on failure.
    static func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
        var distance: Float = 0
        do {
            try a.computeDistance(&distance, to: b)
            return distance
        } catch {
            return nil
        }
    }

    // MARK: - Private

    private static func crop(_ image: CGImage, boundingBox box: CGRect) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        // Vision bounding boxes are normalized with a bottom-left origin; flip Y for CGImage.
        var rect = CGRect(
            x: box.minX * width,
            y: (1 - box.maxY) * height,
            width: box.width * width,
            height: box.height * height
        )
        // Expand to include more of the head/hair for a nicer icon and better matching.
        rect = rect.insetBy(dx: -rect.width * 0.4, dy: -rect.height * 0.5)
        rect = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard rect.width > 24, rect.height > 24 else { return nil }
        return image.cropping(to: rect)
    }

    private static func featurePrintData(for crop: CGImage) -> Data? {
        let handler = VNImageRequestHandler(cgImage: crop, orientation: .up, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()
        do { try handler.perform([request]) } catch { return nil }
        guard let observation = request.results?.first as? VNFeaturePrintObservation else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
    }

    private static func pngData(from cgImage: CGImage, maxDimension: CGFloat) -> Data? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let scale = min(1, maxDimension / max(width, height))
        let size = CGSize(width: width * scale, height: height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
        }
        return image.pngData()
    }
}
