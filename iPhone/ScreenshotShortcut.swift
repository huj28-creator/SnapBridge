import AppIntents
import Photos

/// Called by an iOS Shortcuts personal automation after a screenshot is saved.
/// The screenshot is read in its original format and sent over the existing
/// authenticated ShotSkiff channel; the app UI is not opened.
struct SendLatestScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Send Latest Screenshot to Mac"
    static let description = IntentDescription(
        "Sends the newest screenshot to your paired Mac over your local network."
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        try await ScreenshotShortcutTransfer.sendLatest()
        return .result()
    }
}

struct ShotSkiffAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendLatestScreenshotIntent(),
            phrases: ["Send latest screenshot with \(.applicationName)"],
            shortTitle: "Send Screenshot",
            systemImageName: "rectangle.on.rectangle"
        )
    }
}

private enum ScreenshotShortcutTransfer {
    static func sendLatest() async throws {
        guard let pairing = KeychainStore.load(PairingRecord.self, key: "paired-mac"),
              let rawID = UserDefaults.standard.string(forKey: "deviceID"),
              let deviceID = UUID(uuidString: rawID) else {
            throw ShortcutTransferError.notPaired
        }

        var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if authorization == .notDetermined {
            authorization = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { continuation.resume(returning: $0) }
            }
        }
        guard authorization == .authorized || authorization == .limited else {
            throw ShortcutTransferError.photosAccess
        }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaSubtype & %d != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        guard let asset = assets.firstObject, let capturedAt = asset.creationDate else {
            throw ShortcutTransferError.noScreenshot
        }

        let data = try await originalImageData(for: asset)
        guard data.count <= BridgeLimits.maxPhotoBytes else { throw WireError.tooLarge }
        let isJPEG = data.starts(with: [0xFF, 0xD8, 0xFF])
        let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        guard isPNG || isJPEG else { throw ShortcutTransferError.invalidImage }

        let channel = FastPhotoChannel()
        let photoID = UUID()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = IntentTransferGate(channel: channel, continuation: continuation)
            channel.onReady = { _ in
                channel.send(WirePacket(
                    header: WireHeader(kind: .photo, id: photoID, createdAt: capturedAt),
                    payload: data
                )) { result in
                    if case .failure(let error) = result { gate.finish(.failure(error)) }
                }
            }
            channel.onPacket = { packet, _ in
                guard packet.header.id == photoID else { return }
                guard packet.header.kind == .received else {
                    if packet.header.kind == .rejected {
                        gate.finish(.failure(ShortcutTransferError.macRejected(packet.header.message ?? "The Mac could not save the screenshot.")))
                    }
                    return
                }
                gate.finish(.success(()))
            }
            channel.onDisconnected = {
                gate.finish(.failure(ShortcutTransferError.connectionLost))
            }
            gate.armTimeout()
            channel.startSender(
                pairing: pairing,
                deviceID: deviceID,
                name: "iPhone"
            )
        }
    }

    private static func originalImageData(for asset: PHAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.version = .original
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if info?[PHImageResultIsDegradedKey] as? Bool == true { return }
                if info?[PHImageCancelledKey] as? Bool == true {
                    continuation.resume(throwing: ShortcutTransferError.noScreenshot)
                    return
                }
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: ShortcutTransferError.noScreenshot)
                }
            }
        }
    }
}

private final class IntentTransferGate {
    private let lock = NSLock()
    private let channel: FastPhotoChannel
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeout: DispatchWorkItem?

    init(channel: FastPhotoChannel, continuation: CheckedContinuation<Void, Error>) {
        self.channel = channel
        self.continuation = continuation
    }

    func armTimeout() {
        let work = DispatchWorkItem { [weak self] in
            self?.finish(.failure(ShortcutTransferError.timeout))
        }
        lock.lock()
        timeout = work
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 12, execute: work)
    }

    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard let continuation else { lock.unlock(); return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        lock.unlock()
        channel.stop()
        continuation.resume(with: result)
    }
}

private enum ShortcutTransferError: LocalizedError {
    case notPaired, photosAccess, noScreenshot, invalidImage, connectionLost, timeout
    case macRejected(String)

    var errorDescription: String? {
        switch self {
        case .notPaired: return "Open ShotSkiff once and pair it with your Mac before using screenshot transfer."
        case .photosAccess: return "Allow ShotSkiff access to Photos once, then retry the screenshot automation."
        case .noScreenshot: return "No saved screenshot was found in Photos."
        case .invalidImage: return "The latest screenshot could not be read as a PNG or JPEG."
        case .connectionLost: return "ShotSkiff lost the local connection before the screenshot reached your Mac."
        case .timeout: return "Your Mac did not confirm the screenshot within 12 seconds. Keep ShotSkiff running on the Mac and try again."
        case .macRejected(let message): return message
        }
    }
}
