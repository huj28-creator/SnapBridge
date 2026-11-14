import Foundation
import ImageIO

/// Opt-in on the Mac by supplying the identifier of an already trusted iPhone.
final class PhoneScreenshots {
    private struct Screenshot: Decodable {
        let id: UUID
        let date: Double
        let size: Int
        let readMilliseconds: Double
        let transport: String
        let preview: Bool
    }

    private let receive: (UUID, Data, Date) -> Void
    var onPreview: ((UUID, Data, Date) -> Void)?
    private let queue = DispatchQueue(label: "local.snapbridge.screenshots", qos: .utility)
    private let since = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
    private var process: Process?
    private var pipe: Pipe?
    private var buffer = Data()
    private var nextImage: Screenshot?
    private var lastResponse = Date()
    private var watchdog: DispatchSourceTimer?
    private var running = false

    init(receive: @escaping (UUID, Data, Date) -> Void) {
        self.receive = receive
    }

    func start() {
        queue.async {
            guard !self.running else { return }
            self.running = true
            self.launch()
        }
    }

    func stop() {
        queue.sync {
            running = false
            watchdog?.cancel()
            watchdog = nil
            stopProcess()
        }
    }

    private func stopProcess() {
        pipe?.fileHandleForReading.readabilityHandler = nil
        if let process, process.isRunning { process.terminate() }
        pipe = nil
        process = nil
        buffer.removeAll(keepingCapacity: false)
        nextImage = nil
    }

    private func launch() {
        guard running, process == nil,
              let script = Bundle.main.url(forResource: "watch_screenshots", withExtension: "py"),
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let rawID = try? String(contentsOf: support.appendingPathComponent("SnapBridge/ScreenshotPhone"), encoding: .utf8)
        else { return }
        let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id.range(of: #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$|^[0-9A-Fa-f]{40}$"#, options: .regularExpression) != nil else { return }

        let child = Process()
        let output = Pipe()
        let homebrewPython = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
        let python = homebrewPython.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/python3"
        child.executableURL = URL(fileURLWithPath: python)
        child.arguments = ["-u", script.path, id, String(since)]
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        process = child
        pipe = output
        lastResponse = Date()
        output.fileHandleForReading.readabilityHandler = { [weak self, weak child] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil }
            self?.queue.async { [weak self, weak child] in
                guard let self, let child, self.process === child else { return }
                if chunk.isEmpty { self.restart() }
                else {
                    self.lastResponse = Date()
                    self.consume(chunk)
                }
            }
        }
        do { try child.run() }
        catch {
            stopProcess()
            return
        }
        if watchdog == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 15, repeating: 5)
            timer.setEventHandler { [weak self] in
                guard let self, self.process != nil,
                      Date().timeIntervalSince(self.lastResponse) > 25 else { return }
                self.restart()
            }
            watchdog = timer
            timer.resume()
        }
    }

    private func restart() {
        stopProcess()
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.launch() }
    }

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        var consumed = buffer.startIndex
        while true {
            if nextImage == nil {
                guard buffer.endIndex - consumed >= 4 else { break }
                let headerSize = buffer[consumed..<consumed + 4].reduce(0) { ($0 << 8) | Int($1) }
                if headerSize > 1024 { restart(); return }
                guard buffer.endIndex - consumed >= 4 + headerSize else { break }
                consumed += 4
                if headerSize == 0 { continue }
                let header = buffer[consumed..<consumed + headerSize]
                consumed += headerSize
                guard let shot = try? JSONDecoder().decode(Screenshot.self, from: header),
                      (1...BridgeLimits.maxPhotoBytes).contains(shot.size)
                else { restart(); return }
                nextImage = shot
            }
            guard let shot = nextImage, buffer.endIndex - consumed >= shot.size else { break }
            let image = Data(buffer[consumed..<consumed + shot.size])
            consumed += shot.size
            nextImage = nil
            if shot.preview {
                guard image.count <= 512 * 1024, image.starts(with: [0xff, 0xd8, 0xff]) else { continue }
                let callback = onPreview
                DispatchQueue.main.async { callback?(shot.id, image, Date(timeIntervalSince1970: shot.date)) }
                continue
            }
            guard let source = try? PhotoProcessing.source(image),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
                  let exif = properties[kCGImagePropertyExifDictionary] as? NSDictionary,
                  exif[kCGImagePropertyExifUserComment] as? String == "Screenshot"
            else { continue }
            PerformanceTrace.record("screenshot_read_\(shot.transport)", id: shot.id,
                                    since: PerformanceTrace.now() - shot.readMilliseconds / 1000, bytes: shot.size)
            DispatchQueue.main.async { [receive] in
                receive(shot.id, image, Date(timeIntervalSince1970: shot.date))
            }
        }
        if consumed > buffer.startIndex { buffer.removeSubrange(buffer.startIndex..<consumed) }
    }
}
