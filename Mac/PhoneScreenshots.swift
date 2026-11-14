import Foundation
import ImageIO

/// Opt-in on the Mac by supplying the identifier of an already trusted iPhone.
final class PhoneScreenshots {
    private struct Screenshot: Decodable {
        let id: UUID
        let date: Double
        let image: Data
    }

    private let receive: (UUID, Data, Date) -> Void
    private let queue = DispatchQueue(label: "local.snapbridge.screenshots", qos: .utility)
    private let since = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
    private var process: Process?
    private var pipe: Pipe?
    private var buffer = Data()
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
        while let end = buffer[consumed...].firstIndex(of: 10) {
            let line = buffer[consumed..<end]
            consumed = end + 1
            guard line.count > 2, line.count <= BridgeLimits.maxPhotoBytes * 4 / 3 + 256,
                  let shot = try? JSONDecoder().decode(Screenshot.self, from: line),
                  shot.image.count <= BridgeLimits.maxPhotoBytes,
                  let source = try? PhotoProcessing.source(shot.image),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
                  let exif = properties[kCGImagePropertyExifDictionary] as? NSDictionary,
                  exif[kCGImagePropertyExifUserComment] as? String == "Screenshot"
            else { continue }
            DispatchQueue.main.async { [receive] in
                receive(shot.id, shot.image, Date(timeIntervalSince1970: shot.date))
            }
        }
        if consumed > buffer.startIndex { buffer.removeSubrange(buffer.startIndex..<consumed) }
        if buffer.count > BridgeLimits.maxPhotoBytes * 4 / 3 + 256 { restart() }
    }
}
