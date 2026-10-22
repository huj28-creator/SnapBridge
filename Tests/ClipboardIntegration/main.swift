import AppKit
import ImageIO
import UniformTypeIdentifiers

let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let pasteboard = NSPasteboard.withUniqueName()
defer { pasteboard.releaseGlobally() }

func fixture(orientation: Int) -> Data {
    let context = CGContext(data: nil, width: 160, height: 120, bitsPerComponent: 8,
        bytesPerRow: 640, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.systemGreen.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 160, height: 120))
    context.setFillColor(NSColor.systemRed.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
    precondition(CGImageDestinationFinalize(destination))
    return data as Data
}
func pixels(_ image: CGImage) -> Data {
    var bytes = Data(count: image.width * image.height * 4)
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
}
let originals = [fixture(orientation: 6), fixture(orientation: 1)]
let urls = [directory.appendingPathComponent("Photo one.jpg"), directory.appendingPathComponent("Photo two.jpg")]
for index in urls.indices { try originals[index].write(to: urls[index]) }
precondition(PhotoClipboard.writeBatch(urls, to: pasteboard))
let pasted = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as! [URL]
precondition(pasted == urls)
precondition(pasteboard.pasteboardItems?.count == 2)
for index in pasted.indices {
    let bytes = try Data(contentsOf: pasted[index])
    precondition(bytes == originals[index])
}
print("Batch clipboard: two ordered file attachments, both byte-identical to their originals.")
let clipboard = try PhotoClipboard(jpeg: originals[0])
pasteboard.clearContents()
precondition(pasteboard.writeObjects([clipboard.makeItem()]))
precondition(pasteboard.data(forType: PhotoClipboard.jpegType) == originals[0])
let expected = try PhotoProcessing.fullResolutionImage(originals[0])
for type in [NSPasteboard.PasteboardType.png, .tiff] {
    let encoded = pasteboard.data(forType: type)!
    let source = CGImageSourceCreateWithData(encoded as CFData, nil)!
    let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    precondition(decoded.width == 120 && decoded.height == 160)
    precondition(pixels(decoded) == pixels(expected))
}
print("Single clipboard: original JPEG unchanged; PNG/TIFF preserve oriented full-size pixels exactly.")
