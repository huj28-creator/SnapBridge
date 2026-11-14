import UIKit
import Combine

struct PendingShot: Identifiable {
    let id: UUID
    let url: URL
    let date: Date
}

final class PhoneModel: ObservableObject {
    let transport = NearbyTransport(role: .camera, displayName: UIDevice.current.name)
    let camera = CameraController()
    @Published private(set) var pending: [PendingShot] = []
    @Published private(set) var lastThumbnail: UIImage?
    @Published private(set) var deliveryStatus = "Take a photo to send it to your Mac"
    @Published private(set) var sending = false
    @Published var error: String?
    private let outbox: URL
    private var inFlight: UUID?
    private var blocked = Set<UUID>()
    private var receiptDeadline: DispatchWorkItem?
    private var subscriptions = Set<AnyCancellable>()
    private let ioQueue = DispatchQueue(label: "local.snapbridge.outbox", qos: .userInitiated)
    private var enqueuingCount = 0
    private var cachedData: [UUID: Data] = [:]
    private var captureStarts: [UUID: TimeInterval] = [:]
    private var transferStarts: [UUID: TimeInterval] = [:]
    private var lastTransferProgress: TimeInterval = 0
    private var isForeground = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init() {
        outbox = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Outbox", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
            let urls = try FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: [.creationDateKey])
            pending = urls.compactMap { url in
                guard url.pathExtension == "jpg", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent)
                else { return nil }
                return PendingShot(id: id, url: url,
                                   date: (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date())
            }.sorted { $0.date < $1.date }
            if let last = pending.last { lastThumbnail = UIImage(contentsOfFile: last.url.path) }
        } catch { self.error = "Could not open the photo queue: \(error.localizedDescription)" }
        camera.onPhoto = { [weak self] photo in
            self?.captureStarts[photo.id] = photo.startedAt
            self?.enqueue(photo.data, id: photo.id, date: photo.date)
        }
        transport.onConnected = { [weak self] in
            guard let self else { return }
            self.inFlight = nil
            self.receiptDeadline?.cancel()
            self.error = nil
            self.flush()
        }
        transport.onReceipt = { [weak self] id in self?.received(id) }
        transport.onTransferProgress = { [weak self] in self?.lastTransferProgress = PerformanceTrace.now() }
        transport.onRejected = { [weak self] id, message in
            guard let self else { return }
            self.blocked.insert(id)
            self.inFlight = nil
            self.sending = false
            self.receiptDeadline?.cancel()
            self.error = message
            self.deliveryStatus = "Photo kept on this iPhone. Tap Retry."
        }
        transport.$connected.dropFirst().sink { [weak self] connected in
            guard let self else { return }
            if !connected {
                self.inFlight = nil
                self.sending = false
                self.receiptDeadline?.cancel()
                if !self.pending.isEmpty { self.deliveryStatus = "\(self.pending.count) photos queued for your Mac" }
            }
        }.store(in: &subscriptions)
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["SNAPBRIDGE_TEST"] == "1" {
            testEvent("started; previouslyPaired=\(transport.pairing != nil)")
            transport.$status.sink { [weak self] in self?.testEvent($0) }.store(in: &subscriptions)
            transport.$error.sink { [weak self] in if let message = $0 { self?.testEvent("ERROR \(message)") } }.store(in: &subscriptions)
            transport.$nearbyMacs.sink { [weak self] macs in
                guard let self, self.transport.pairing == nil, let mac = macs.first,
                      let code = ProcessInfo.processInfo.environment["SNAPBRIDGE_TEST_CODE"] else { return }
                self.transport.pair(with: mac, code: code)
            }.store(in: &subscriptions)
            sendSimulatorPhoto()
        }
        #endif
    }

    func activate() {
        isForeground = true
        endBackgroundTask()
        UIApplication.shared.isIdleTimerDisabled = true
        transport.start()
        camera.start()
        flush()
    }

    func deactivate() {
        isForeground = false
        UIApplication.shared.isIdleTimerDisabled = false
        camera.stop()
        if !pending.isEmpty || enqueuingCount > 0 || camera.capturing {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish photo delivery") { [weak self] in
                guard let self else { return }
                self.transport.pauseForBackground()
                self.endBackgroundTask()
            }
        } else { transport.pauseForBackground() }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    func retry() {
        error = nil
        blocked = []
        transport.clearError()
        transport.reconnect()
        flush()
    }

    private func enqueue(_ data: Data, id: UUID = UUID(), date: Date = Date()) {
        guard pending.count + enqueuingCount < BridgeLimits.maxPendingPhotos else {
            error = "The queue holds 10 photos. Reconnect to your Mac before taking more."
            return
        }
        guard data.count <= BridgeLimits.maxPhotoBytes else { error = WireError.tooLarge.localizedDescription; return }
        let url = outbox.appendingPathComponent("\(id.uuidString).jpg")
        enqueuingCount += 1
        ioQueue.async {
            let start = PerformanceTrace.now()
            do {
                try data.write(to: url, options: .atomic)
                PerformanceTrace.record("phone_outbox_save", id: id, since: start, bytes: data.count)
                DispatchQueue.main.async {
                    self.enqueuingCount -= 1
                    self.pending.append(PendingShot(id: id, url: url, date: date))
                    self.cachedData[id] = data
                    // Bound RAM independently of the ten-photo disk queue.
                    for old in self.pending.dropLast(3) where old.id != self.inFlight {
                        self.cachedData.removeValue(forKey: old.id)
                    }
                    self.error = nil
                    self.deliveryStatus = self.transport.connected ? "Sending to your Mac…" : "Photo queued. Connect to your Mac to send."
                    self.flush()
                }
                if let cg = try? PhotoProcessing.thumbnail(data, maxPixels: 256) {
                    let thumbnail = UIImage(cgImage: cg)
                    DispatchQueue.main.async { self.lastThumbnail = thumbnail }
                }
            } catch {
                DispatchQueue.main.async {
                    self.enqueuingCount -= 1
                    self.captureStarts.removeValue(forKey: id)
                    self.error = "Could not keep this photo: \(error.localizedDescription). Please retake it."
                }
            }
        }
    }

    private func flush() {
        guard transport.connected, inFlight == nil,
              let next = pending.first, !blocked.contains(next.id) else { return }
        inFlight = next.id
        sending = true
        deliveryStatus = "Sending to \(transport.connectedName)…"
        let send: (Data) -> Void = { [weak self] data in
            guard let self, self.inFlight == next.id, self.transport.connected else { return }
            self.transferStarts[next.id] = PerformanceTrace.now()
            self.lastTransferProgress = PerformanceTrace.now()
            self.transport.sendPhoto(id: next.id, data: data, date: next.date) { [weak self] result in
                guard let self, self.inFlight == next.id else { return }
                if case .failure = result {
                    self.inFlight = nil
                    self.sending = false
                    self.receiptDeadline?.cancel()
                    self.deliveryStatus = "Refreshing the connection — photo kept safely"
                    self.transport.recoverStalledTransfer()
                }
            }
            self.scheduleReceiptCheck(id: next.id)
        }
        if let data = cachedData[next.id] { send(data) }
        else {
            ioQueue.async {
                do {
                    let data = try Data(contentsOf: next.url)
                    DispatchQueue.main.async { send(data) }
                } catch {
                    DispatchQueue.main.async {
                        guard self.inFlight == next.id else { return }
                        self.inFlight = nil
                        self.sending = false
                        self.error = error.localizedDescription
                    }
                }
            }
        }
    }

    private func scheduleReceiptCheck(id: UUID) {
        receiptDeadline?.cancel()
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.inFlight == id else { return }
            if PerformanceTrace.now() - self.lastTransferProgress < 4 {
                self.scheduleReceiptCheck(id: id)
                return
            }
            self.inFlight = nil
            self.sending = false
            self.deliveryStatus = "Refreshing the connection — photo kept safely"
            self.transport.recoverStalledTransfer()
        }
        receiptDeadline = deadline
        let remaining = max(0.05, 4 - (PerformanceTrace.now() - lastTransferProgress))
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: deadline)
    }

    private func received(_ id: UUID) {
        guard let shot = pending.first(where: { $0.id == id }) else { return }
        if let start = transferStarts.removeValue(forKey: id) {
            PerformanceTrace.record("transfer_to_mac_receipt", id: id, since: start)
        }
        if let start = captureStarts.removeValue(forKey: id) {
            PerformanceTrace.record("shutter_to_mac_receipt", id: id, since: start)
        }
        ioQueue.async { try? FileManager.default.removeItem(at: shot.url) }
        cachedData.removeValue(forKey: id)
        pending.removeAll { $0.id == id }
        blocked.remove(id)
        if inFlight == id { inFlight = nil; sending = false; receiptDeadline?.cancel() }
        deliveryStatus = "On your Mac. Press ⌘V in your chat."
        error = nil
        #if targetEnvironment(simulator)
        testEvent("RECEIVED \(id.uuidString)")
        #endif
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        flush()
        if !isForeground, pending.isEmpty, enqueuingCount == 0 {
            transport.pauseForBackground()
            endBackgroundTask()
        }
    }

    #if targetEnvironment(simulator)
    private func testEvent(_ message: String) {
        guard ProcessInfo.processInfo.environment["SNAPBRIDGE_TEST"] == "1" else { return }
        let url = outbox.deletingLastPathComponent().appendingPathComponent("SimulatorTest.log")
        let line = "\(Date().timeIntervalSince1970) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: url.path) { try? data.write(to: url) }
        else if let file = try? FileHandle(forWritingTo: url) {
            defer { try? file.close() }
            _ = try? file.seekToEnd()
            try? file.write(contentsOf: data)
        }
    }

    func sendSimulatorPhoto() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1500)).image { context in
            UIColor(red: 0.04, green: 0.12, blue: 0.09, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 1500))
            let text = "ShotSkiff\n\nTransfer test\n\nPhone → Mac\nReady to paste."
            (text as NSString).draw(in: CGRect(x: 100, y: 200, width: 1000, height: 1100), withAttributes: [
                .font: UIFont.systemFont(ofSize: 78, weight: .semibold),
                .foregroundColor: UIColor(red: 0.35, green: 0.91, blue: 0.63, alpha: 1)
            ])
        }
        if let data = image.jpegData(compressionQuality: 0.9) {
            if ProcessInfo.processInfo.environment["SNAPBRIDGE_TEST"] == "1" {
                try? data.write(to: outbox.deletingLastPathComponent().appendingPathComponent("SimulatorExpected.jpg"))
            }
            enqueue(data)
        }
    }
    #endif
}
