//
//  LeafPixelAnalyzer.swift
//  KolaCare
//
//  Quantifies symptoms by classifying every pixel of a downsampled photo as
//  healthy green, chlorotic (yellow) or necrotic (brown/black) tissue, or background.
//  The result gives an objective "% leaf area affected" severity estimate and a
//  lesion map overlay, and acts as the diagnosis fallback when no CoreML model is bundled.
//
//  The colour thresholds are mirrored in scripts/make_assets.py and were validated
//  against the bundled sample leaves.
//

import CoreGraphics
import Foundation

enum PixelClass: Equatable {
    case background, healthy, chlorotic, necrotic
}

struct LeafAnalysis: @unchecked Sendable {
    let metrics: LeafMetrics
    /// Overlay (same aspect ratio as the input) with amber = yellowing, red = dead tissue.
    let lesionMap: CGImage?
}

enum LeafPixelAnalyzer {
    /// 192 × 192 ≈ 37k pixels: accurate enough for area fractions and runs in a few milliseconds.
    static let sampleSize = 192

    // MARK: Pixel classification

    /// Classifies one pixel. Components are 0…1, already un-premultiplied.
    static func classify(red r: Double, green g: Double, blue b: Double) -> PixelClass {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC
        let brightness = maxC
        let saturation = maxC == 0 ? 0 : delta / maxC

        if brightness < 0.10 { return .background }   // deep shadow / black backdrop

        var hue: Double = 0
        if delta > 0 {
            if maxC == r {
                hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                hue = 60 * ((b - r) / delta + 2)
            } else {
                hue = 60 * ((r - g) / delta + 4)
            }
            if hue < 0 { hue += 360 }
        }

        if (65...170).contains(hue) && saturation >= 0.20 && brightness >= 0.15 { return .healthy }
        if hue >= 40 && hue < 65 && saturation >= 0.30 && brightness >= 0.40 { return .chlorotic }
        if (hue < 40 || hue >= 345) && saturation >= 0.25 && brightness <= 0.65 { return .necrotic }
        return .background
    }

    // MARK: Image analysis

    /// - Parameters:
    ///   - image: the photo, or a Vision-masked version where background pixels are transparent.
    ///   - usedSegmentation: recorded in the metrics for transparency in the UI.
    static func analyze(_ image: CGImage, usedSegmentation: Bool = false) -> LeafAnalysis {
        let width = sampleSize
        let height = max(1, Int((Double(sampleSize) * Double(image.height) / Double(max(image.width, 1))).rounded()))
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        var overlay = [UInt8](repeating: 0, count: bytesPerRow * height)

        var counted = 0, healthy = 0, chlorotic = 0, necrotic = 0
        var luminanceSum = 0.0

        let drew: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                          space: colorSpace, bitmapInfo: bitmapInfo) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return LeafAnalysis(metrics: .empty, lesionMap: nil) }

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.5 else { continue }          // transparent = removed by segmentation
            let r = Double(pixels[index]) / 255 / alpha
            let g = Double(pixels[index + 1]) / 255 / alpha
            let b = Double(pixels[index + 2]) / 255 / alpha
            counted += 1
            luminanceSum += 0.299 * r + 0.587 * g + 0.114 * b

            switch classify(red: min(r, 1), green: min(g, 1), blue: min(b, 1)) {
            case .healthy:
                healthy += 1
            case .chlorotic:
                chlorotic += 1
                paint(&overlay, at: index, red: 255, green: 176, blue: 0)    // amber
            case .necrotic:
                necrotic += 1
                paint(&overlay, at: index, red: 230, green: 20, blue: 60)    // crimson
            case .background:
                break
            }
        }

        let leaf = healthy + chlorotic + necrotic
        let leafDouble = Double(max(leaf, 1))
        let metrics = LeafMetrics(
            leafCoverage: counted == 0 ? 0 : Double(leaf) / Double(counted),
            greenFraction: Double(healthy) / leafDouble,
            chlorosisFraction: Double(chlorotic) / leafDouble,
            necrosisFraction: Double(necrotic) / leafDouble,
            meanLuminance: counted == 0 ? 0 : luminanceSum / Double(counted),
            usedSegmentation: usedSegmentation)

        let lesionMap = (chlorotic + necrotic) > 0
            ? makeImage(from: &overlay, width: width, height: height, bytesPerRow: bytesPerRow)
            : nil
        return LeafAnalysis(metrics: metrics, lesionMap: lesionMap)
    }

    private static func paint(_ buffer: inout [UInt8], at index: Int, red: UInt8, green: UInt8, blue: UInt8) {
        // Premultiplied at ~70 % opacity.
        let alpha: Double = 0.7
        buffer[index] = UInt8(Double(red) * alpha)
        buffer[index + 1] = UInt8(Double(green) * alpha)
        buffer[index + 2] = UInt8(Double(blue) * alpha)
        buffer[index + 3] = UInt8(255 * alpha)
    }

    private static func makeImage(from buffer: inout [UInt8], width: Int, height: Int, bytesPerRow: Int) -> CGImage? {
        buffer.withUnsafeMutableBytes { raw -> CGImage? in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            return context.makeImage()
        }
    }

    // MARK: Heuristic diagnosis

    /// Maps measured symptoms to a generic catalogue entry when no ML model is available.
    static func heuristicDiagnosis(for metrics: LeafMetrics) -> Prediction {
        let affected = metrics.affectedArea
        if affected < 0.06 {
            return Prediction(diseaseID: "general.healthy", confidence: min(0.9, 0.7 + (0.06 - affected) * 3))
        }
        if metrics.necrosisFraction >= metrics.chlorosisFraction * 0.8 {
            return Prediction(diseaseID: "general.leaf_spot", confidence: min(0.85, 0.5 + metrics.necrosisFraction))
        }
        return Prediction(diseaseID: "general.chlorosis", confidence: min(0.85, 0.5 + metrics.chlorosisFraction))
    }
}
