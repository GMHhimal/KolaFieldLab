//
//  ImageProcessing.swift
//  KolaCare
//
//  Memory-efficient image handling. Camera photos can be 12–48 MP; decoding them
//  fully would cost >100 MB. ImageIO thumbnails decode straight to the target
//  size and apply EXIF orientation in one step.
//

import ImageIO
import UIKit
import UniformTypeIdentifiers

enum ImageProcessing {
    /// Size used for analysis and for the stored scan photo.
    static let analysisMaxPixel = 1024
    /// Size used for list thumbnails.
    static let thumbnailMaxPixel = 320

    /// Decodes and downsamples encoded image data without loading the full bitmap.
    static func downsample(_ data: Data, maxPixelSize: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    static func jpegData(from image: CGImage, quality: CGFloat = 0.8) -> Data? {
        UIImage(cgImage: image).jpegData(compressionQuality: quality)
    }

    /// Returns the analysis-sized photo and a thumbnail, both JPEG encoded.
    static func prepareForStorage(_ image: CGImage) -> (photo: Data?, thumbnail: Data?) {
        let photo = jpegData(from: image, quality: 0.8)
        let thumbnail = photo.flatMap { downsample($0, maxPixelSize: thumbnailMaxPixel) }
            .flatMap { jpegData(from: $0, quality: 0.7) }
        return (photo, thumbnail)
    }

    /// Thumbnail-sized UIImage for lists, decoded off the main thread by callers.
    static func thumbnail(from data: Data, maxPixelSize: Int = thumbnailMaxPixel) -> UIImage? {
        downsample(data, maxPixelSize: maxPixelSize).map { UIImage(cgImage: $0) }
    }
}
