import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Original image is ready immediately. Lossless compatibility formats are computed once off the UI thread.
final class PhotoClipboard: NSObject, NSPasteboardItemDataProvider {
    static let jpegType = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
    let original: Data
    let originalType: NSPasteboard.PasteboardType
    let preview: NSImage
    private let queue = DispatchQueue(label: "local.snapbridge.clipboard", qos: .userInitiated)
    private var bitmap: NSBitmapImageRep?
    private var png: Data?
    private var tiff: Data?

    /// File URL items let browsers paste every original image as a separate attachment.
    static func writeBatch(_ urls: [URL], to pasteboard: NSPasteboard) -> Bool {
        guard !urls.isEmpty, urls.count <= 20, urls.allSatisfy(\.isFileURL) else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects(urls.map { $0 as NSURL })
    }

    init(image: Data) throws {
        original = image
        let ext = try PhotoProcessing.fileExtension(image)
        originalType = NSPasteboard.PasteboardType(ext == "png" ? UTType.png.identifier : UTType.jpeg.identifier)
        let thumbnail = try PhotoProcessing.thumbnail(image, maxPixels: 1600)
        preview = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
        super.init()
    }

    convenience init(jpeg: Data) throws { try self.init(image: jpeg) }

    func prewarm() {
        queue.async { [weak self] in _ = self?.representationLocked(.png) }
    }

    func makeItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setData(original, forType: originalType)
        item.setDataProvider(self, forTypes: [.png, .tiff])
        return item
    }

    func data(for type: NSPasteboard.PasteboardType) -> Data? {
        if type == originalType { return original }
        return queue.sync { representationLocked(type) }
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        if let data = data(for: type) { item.setData(data, forType: type) }
    }

    private func representationLocked(_ type: NSPasteboard.PasteboardType) -> Data? {
        if type == originalType { return original }
        if type == .png, let png { return png }
        if type == .tiff, let tiff { return tiff }
        if bitmap == nil {
            guard let image = try? PhotoProcessing.fullResolutionImage(original)
            else { return nil }
            bitmap = NSBitmapImageRep(cgImage: image)
        }
        if type == .png {
            png = bitmap?.representation(using: .png, properties: [:])
            return png
        }
        if type == .tiff {
            tiff = bitmap?.representation(using: .tiff, properties: [.compressionMethod: NSNumber(value: NSBitmapImageRep.TIFFCompression.none.rawValue)])
            return tiff
        }
        return nil
    }
}
