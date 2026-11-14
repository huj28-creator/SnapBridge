import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum PhotoProcessing {

    static func source(_ data: Data) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 12000, height <= 12000, width * height <= 50_000_000 else {
            throw WireError.invalidPhoto
        }
        return source
    }

    /// Keep the camera's original JPEG bytes.
    static func prepareJPEG(_ data: Data) throws -> Data {
        guard try fileExtension(data) == "jpg" else { throw WireError.invalidPhoto }
        return data
    }

    static func fileExtension(_ data: Data) throws -> String {
        let imageSource = try source(data)
        guard let typeIdentifier = CGImageSourceGetType(imageSource) as String?,
              let type = UTType(typeIdentifier), type.conforms(to: .image) else {
            throw WireError.invalidPhoto
        }
        if type.conforms(to: .jpeg) { return "jpg" }
        if type.conforms(to: .png) { return "png" }
        throw WireError.invalidPhoto
    }

    static func fullResolutionImage(_ data: Data) throws -> CGImage {
        let source = try source(data)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
        let width = properties[kCGImagePropertyPixelWidth] as! Int
        let height = properties[kCGImagePropertyPixelHeight] as! Int
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        if orientation == 1, let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
            return image
        }
        return try thumbnail(data, maxPixels: max(width, height))
    }

    static func thumbnail(_ data: Data, maxPixels: Int) throws -> CGImage {
        let source = try source(data)
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw WireError.invalidPhoto }
        return image
    }
}
