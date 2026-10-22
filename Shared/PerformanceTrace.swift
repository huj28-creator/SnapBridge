import Foundation

enum PerformanceTrace {
    private static let queue = DispatchQueue(label: "local.snapbridge.timings", qos: .utility)
    private static var recent: [[String: Any]] = []
    private static var connectionEvents: [[String: Any]] = []
    private static var loaded = false
    private static let persists = [".snapbridge.mac", ".snapbridge.camera"]
        .contains { (Bundle.main.bundleIdentifier ?? "").hasSuffix($0) }
    static var enabled: Bool { ProcessInfo.processInfo.environment["SNAPBRIDGE_DIAGNOSTICS"] == "1" }
    static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
    static func connection(_ event: String) {
        if enabled { print("SnapBridgeConnection \(event)"); fflush(stdout) }
        guard persists else { return }
        queue.async {
            connectionEvents.append(["at": Date().timeIntervalSince1970, "event": String(event.prefix(256))])
            connectionEvents = Array(connectionEvents.suffix(40))
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SnapBridge", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = try? JSONSerialization.data(withJSONObject: connectionEvents, options: [.sortedKeys]) {
                try? data.write(to: directory.appendingPathComponent("Connection.json"), options: .atomic)
            }
        }
    }

    static func record(_ event: String, id: UUID, since start: TimeInterval, bytes: Int? = nil) {
        let elapsed = (now() - start) * 1000
        let size = bytes.map { " bytes=\($0)" } ?? ""
        if enabled {
            print("SnapBridgePerf \(event) id=\(id.uuidString) ms=\(String(format: "%.2f", elapsed))\(size)")
            fflush(stdout)
        }
        guard persists else { return }
        queue.async {
            if !loaded {
                loaded = true
                let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("SnapBridge/Performance.json")
                if let data = try? Data(contentsOf: url),
                   let saved = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    recent = Array(saved.suffix(20))
                }
            }
            if let index = recent.firstIndex(where: { $0["id"] as? String == id.uuidString }) {
                recent[index][event] = elapsed
                if let bytes { recent[index]["bytes"] = bytes }
            } else {
                var item: [String: Any] = ["id": id.uuidString, "at": Date().timeIntervalSince1970, event: elapsed]
                if let bytes { item["bytes"] = bytes }
                recent.append(item)
                recent = Array(recent.suffix(20))
            }
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SnapBridge", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = try? JSONSerialization.data(withJSONObject: recent, options: [.sortedKeys]) {
                try? data.write(to: directory.appendingPathComponent("Performance.json"), options: .atomic)
            }
        }
    }
}
