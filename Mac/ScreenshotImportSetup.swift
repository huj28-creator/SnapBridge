import Foundation
import Combine
import AppKit
import ServiceManagement

struct TrustedPhone: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

@MainActor
final class ScreenshotImportSetup: ObservableObject {
    @Published private(set) var phones: [TrustedPhone] = []
    @Published var selectedPhoneID = ""
    @Published private(set) var isEnabled = false
    @Published private(set) var status = "Automatic screenshot importing is off."
    @Published private(set) var isScanning = false
    @Published private(set) var dependencyAvailable = false
    @Published private(set) var dependencyMessage = ""

    private let watcher: PhoneScreenshots
    private let supportDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/SnapBridge", isDirectory: true)
    private var selectedFile: URL { supportDirectory.appendingPathComponent("ScreenshotPhone") }
    private let queue = DispatchQueue(label: "local.snapbridge.setup", qos: .userInitiated)

    init(watcher: PhoneScreenshots) {
        self.watcher = watcher
        let saved = (try? String(contentsOf: selectedFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        selectedPhoneID = saved
        isEnabled = !saved.isEmpty
        if isEnabled { status = "Screenshot importing is enabled for your saved iPhone." }
        refreshDependencies()
        scan()
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        status = "Looking for trusted iPhones…"
        queue.async { [weak self] in
            let found = Self.detectPhones()
            DispatchQueue.main.async {
                guard let self else { return }
                self.phones = found
                self.isScanning = false
                if found.isEmpty {
                    self.status = "No trusted iPhone found. Connect it by USB, unlock it, and tap Trust This Computer if asked."
                } else if !self.selectedPhoneID.isEmpty && !found.contains(where: { $0.id == self.selectedPhoneID }) {
                    self.status = "Your saved iPhone is not reachable. Reconnect it by USB or its trusted Wi-Fi connection."
                } else {
                    self.status = self.isEnabled ? "Ready. New screenshots from the selected iPhone appear on this Mac." : "Choose an iPhone, then enable importing."
                }
            }
        }
    }

    func refreshDependencies() {
        let hasPython = ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"].contains { FileManager.default.isExecutableFile(atPath: $0) }
        let hasID = Self.tool(named: "idevice_id") != nil
        let hasLibrary = ["/opt/homebrew/lib/libimobiledevice-1.0.dylib", "/usr/local/lib/libimobiledevice-1.0.dylib"].contains { FileManager.default.fileExists(atPath: $0) }
        dependencyAvailable = hasPython && hasID && hasLibrary
        dependencyMessage = dependencyAvailable ? "Screenshot support is ready." : "Screenshot importing needs Python 3 and Homebrew’s libimobiledevice. ShotSkiff does not install these without your approval."
    }

    func enable() {
        guard dependencyAvailable else {
            status = "Install the listed screenshot components first, then choose Check Again."
            return
        }
        guard let phone = phones.first(where: { $0.id == selectedPhoneID }) else {
            status = "Choose a currently connected trusted iPhone first."
            return
        }
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            try Data(phone.id.utf8).write(to: selectedFile, options: .atomic)
            let startsAtLogin = ensureLaunchAtLogin()
            watcher.start()
            isEnabled = true
            if startsAtLogin {
                status = "Ready. ShotSkiff will start at login and reconnect to \(phone.name); existing photos are skipped."
            }
        } catch {
            status = "Could not save the iPhone selection: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func ensureLaunchAtLogin() -> Bool {
        if SMAppService.mainApp.status != .enabled {
            do { try SMAppService.mainApp.register() }
            catch {
                status = "Screenshot importing is active, but automatic startup needs approval in System Settings → General → Login Items."
                return false
            }
        }
        if SMAppService.mainApp.status == .requiresApproval {
            status = "Screenshot importing is active, but approve ShotSkiff in System Settings → General → Login Items."
            return false
        }
        let enabled = SMAppService.mainApp.status == .enabled
        if !enabled {
            status = "Screenshot importing is active, but ShotSkiff is not enabled in System Settings → General → Login Items."
        }
        return enabled
    }

    func disable() {
        watcher.stop()
        try? FileManager.default.removeItem(at: selectedFile)
        isEnabled = false
        status = "Automatic screenshot importing is paused. Your received images are kept."
    }

    func installDependency() {
        let missingPython = !["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"].contains { FileManager.default.isExecutableFile(atPath: $0) }
        let missingLibrary = !["/opt/homebrew/lib/libimobiledevice-1.0.dylib", "/usr/local/lib/libimobiledevice-1.0.dylib"].contains { FileManager.default.fileExists(atPath: $0) }
        var packages: [String] = []
        if missingLibrary { packages.append("libimobiledevice") }
        if missingPython { packages.append("python") }
        guard !packages.isEmpty else { refreshDependencies(); return }
        let installCommand = "brew install " + packages.joined(separator: " ")
        let alert = NSAlert()
        alert.messageText = "Install screenshot support?"
        alert.informativeText = "ShotSkiff will run Homebrew’s official `\(installCommand)` command with your approval. It reads screenshots only from the iPhone you select. Nothing is installed if you cancel."
        alert.addButton(withTitle: "Install with Homebrew")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            status = "Homebrew is not installed. Install it from brew.sh, then return and choose Check Again."
            NSWorkspace.shared.open(URL(string: "https://brew.sh")!)
            return
        }
        status = "Homebrew is installing screenshot support…"
        queue.async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brew)
            process.arguments = ["install"] + packages
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.refreshDependencies()
                    self.status = process.terminationStatus == 0 && self.dependencyAvailable
                        ? "Screenshot support installed. Connect or refresh your iPhone list, then enable importing."
                        : "Installation did not finish. Check Homebrew and Python 3, then choose Check Again."
                }
            } catch {
                DispatchQueue.main.async { self?.status = "Homebrew could not start: \(error.localizedDescription)" }
            }
        }
    }

    nonisolated private static func detectPhones() -> [TrustedPhone] {
        guard let ideviceID = tool(named: "idevice_id"),
              let ids = run(ideviceID, ["-l"]) else { return [] }
        let values = ids.split(whereSeparator: \.isNewline).map(String.init)
        return values.compactMap { id in
            guard id.range(of: #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$|^[0-9A-Fa-f]{40}$"#, options: .regularExpression) != nil else { return nil }
            let name = tool(named: "ideviceinfo").flatMap { run($0, ["-u", id, "-k", "DeviceName"]) }?.trimmingCharacters(in: .whitespacesAndNewlines)
            return TrustedPhone(id: id, name: (name?.isEmpty == false ? name! : "iPhone"))
        }
    }

    nonisolated private static func tool(named name: String) -> String? {
        ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    nonisolated private static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
