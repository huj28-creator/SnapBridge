import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import SnapBridgeCore

final class PhotoProcessingTests: XCTestCase {
    private func jpeg(width: Int, height: Int, orientation: Int = 1) throws -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.25, green: 0.7, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let result = NSMutableData()
        let destination = CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [
            kCGImageDestinationLossyCompressionQuality: 0.95,
            kCGImagePropertyOrientation: orientation
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return result as Data
    }

    private func dimensions(_ data: Data) throws -> (Int, Int, Int) {
        let source = try PhotoProcessing.source(data)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
        return (properties[kCGImagePropertyPixelWidth] as! Int,
                properties[kCGImagePropertyPixelHeight] as! Int,
                properties[kCGImagePropertyOrientation] as? Int ?? 1)
    }

    func testAlreadySuitableJPEGIsPreservedByteForByte() throws {
        let input = try jpeg(width: 960, height: 640)
        XCTAssertEqual(try PhotoProcessing.prepareJPEG(input), input)
    }

    func testFullCameraResolutionAndJPEGBytesArePreserved() throws {
        let input = try jpeg(width: 4032, height: 3024)
        let output = try PhotoProcessing.prepareJPEG(input)
        let size = try dimensions(output)
        XCTAssertEqual(output, input)
        XCTAssertEqual(size.0, 4032)
        XCTAssertEqual(size.1, 3024)
        XCTAssertEqual(size.2, 1)
    }

    func testOriginalMetadataIsPreservedAndClipboardOrientationIsCorrect() throws {
        let input = try jpeg(width: 160, height: 120, orientation: 6)
        let output = try PhotoProcessing.prepareJPEG(input)
        XCTAssertEqual(output, input)
        let size = try dimensions(output)
        XCTAssertEqual(size.0, 160)
        XCTAssertEqual(size.1, 120)
        XCTAssertEqual(size.2, 6)
        let oriented = try PhotoProcessing.fullResolutionImage(output)
        XCTAssertEqual(oriented.width, 120)
        XCTAssertEqual(oriented.height, 160)
    }

    func testSmallPreviewDoesNotChangeFullResolutionJPEG() throws {
        let input = try jpeg(width: 1200, height: 900)
        let preview = try PhotoProcessing.thumbnail(input, maxPixels: 256)
        XCTAssertEqual(preview.width, 256)
        XCTAssertEqual(preview.height, 192)
        let size = try dimensions(input)
        XCTAssertEqual(size.0, 1200)
        XCTAssertEqual(size.1, 900)
        XCTAssertEqual(try PhotoProcessing.prepareJPEG(input), input)
    }

    func testMalformedImagesAreRejected() {
        XCTAssertThrowsError(try PhotoProcessing.prepareJPEG(Data("not an image".utf8)))
        XCTAssertThrowsError(try PhotoProcessing.thumbnail(Data(), maxPixels: 256))
    }

    func testLandscapeAndBothPortraitRotationsKeepOriginalResolution() throws {
        for orientation in [1, 3, 6, 8] {
            let original = try jpeg(width: 160, height: 120, orientation: orientation)
            XCTAssertEqual(try PhotoProcessing.prepareJPEG(original), original)
            let image = try PhotoProcessing.fullResolutionImage(original)
            let portrait = orientation == 6 || orientation == 8
            XCTAssertEqual(image.width, portrait ? 120 : 160)
            XCTAssertEqual(image.height, portrait ? 160 : 120)
            let preview = try PhotoProcessing.thumbnail(original, maxPixels: 80)
            XCTAssertEqual(preview.width, portrait ? 60 : 80)
            XCTAssertEqual(preview.height, portrait ? 80 : 60)
        }
    }
}
