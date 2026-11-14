import AppKit
import SwiftUI
import Combine
import ServiceManagement
import UniformTypeIdentifiers
import ImageIO

@main
struct SnapBridgeMacApp: App {
    @NSApplicationDelegateAdaptor(MacDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

final class MacDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: MacModel!
    private var statusItem: NSStatusItem!
    private var setupWindow: NSWindow?
    private var previewPanel: NSPanel?
    private var previewIsGrid = false
    private var screenshots: PhoneScreenshots?
    private var screenshotSetup: ScreenshotImportSetup?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model = MacModel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.badge.ellipsis", accessibilityDescription: "ShotSkiff")
        statusItem.button?.toolTip = "ShotSkiff — iPhone photos, ready to paste"
        let menu = NSMenu()
        menu.addItem(withTitle: "ShotSkiff", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        addMenuItem("Pair iPhone / Settings…", action: #selector(showSetup), to: menu)
        addMenuItem("Show Latest Photo", action: #selector(showLatest), to: menu)
        addMenuItem("Open Received Photos", action: #selector(openInbox), to: menu)
        addMenuItem("Check for Updates…", action: #selector(checkForUpdates), to: menu)
        menu.addItem(.separator())
        addMenuItem("Quit ShotSkiff", action: #selector(quit), to: menu, key: "q")
        statusItem.menu = menu
        model.onNewPhoto = { [weak self] in self?.showPreview() }
        model.transport.onPairingRequested = { [weak self] in self?.showSetup() }
        model.transport.$connected.sink { [weak self] connected in
            self?.statusItem.button?.image = NSImage(systemSymbolName: connected ? "camera.fill" : "camera.badge.ellipsis",
                                                     accessibilityDescription: "ShotSkiff")
        }.store(in: &subscriptions)
        model.transport.start()
        screenshots = PhoneScreenshots { [weak self] id, data, date in
            self?.model.receive(id: id, data: data, date: date) { _ in }
        }
        screenshots?.onPreview = { [weak self] id, data, date in
            self?.model.showScreenshotPreview(id: id, data: data, date: date)
        }
        if let screenshots {
            screenshotSetup = ScreenshotImportSetup(watcher: screenshots)
            if screenshotSetup?.isEnabled == true { screenshots.start() }
        }
        if !model.transport.hasPairedPhone || CommandLine.arguments.contains("--pair") { showSetup() }
    }

    private func addMenuItem(_ title: String, action: Selector, to menu: NSMenu, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc func showSetup() {
        model.transport.showPairingCode()
        if setupWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "ShotSkiff"
            window.isReleasedWhenClosed = false
            if let screenshotSetup {
                window.contentView = NSHostingView(rootView: MacSetupView(model: model, screenshotSetup: screenshotSetup))
            }
            window.center()
            setupWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        setupWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showLatest() {
        if model.latestImage != nil { model.reopenLatest(); showPreview() } else { showSetup() }
    }
    @objc func openInbox() { NSWorkspace.shared.open(model.inbox) }
    @objc func quit() { NSApp.terminate(nil) }

    @objc func checkForUpdates() {
        guard let url = URL(string: "https://api.github.com/repos/huj28-creator/SnapBridge/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ShotSkiff/0.1.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error {
                    let alert = NSAlert(); alert.messageText = "Update check failed"; alert.informativeText = error.localizedDescription
                    alert.addButton(withTitle: "OK"); alert.runModal(); return
                }
                guard let data,
                      let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
                      let page = URL(string: release.htmlURL) else {
                    let alert = NSAlert(); alert.messageText = "No public release found"; alert.informativeText = "Check the GitHub project page for release information."
                    alert.addButton(withTitle: "OK"); alert.runModal(); return
                }
                let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
                let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
                let alert = NSAlert()
                alert.messageText = latest.compare(current, options: .numeric) == .orderedDescending
                    ? "ShotSkiff \(latest) is available" : "ShotSkiff is up to date"
                let notes = String(release.body.prefix(1800))
                alert.informativeText = "Current version: \(current)\nLatest release: \(latest)\n\n\(notes.isEmpty ? "Release notes are on GitHub." : notes)\n\nUpdates open on GitHub for manual download and installation."
                alert.addButton(withTitle: "View Release")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(page) }
            }
        }.resume()
    }

    func applicationWillTerminate(_ notification: Notification) {
        screenshots?.stop()
    }

    private func showPreview() {
        let wasVisible = previewPanel?.isVisible == true
        if previewPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 400),
                                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Photo received"
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.minSize = NSSize(width: 280, height: 300)
            panel.contentView = NSHostingView(rootView: PhotoPreview(model: model))
            previewPanel = panel
        }
        let count = min(PhotoStore.defaultLimit, model.batchPhotos.count + model.pendingScreenshots.count)
        let isGrid = count > 1
        let expanding = isGrid && !previewIsGrid
        previewPanel?.title = isGrid ? "\(count) photos" : "Photo received"
        if !wasVisible || expanding {
            let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1200, height: 800)
            previewPanel?.setContentSize(isGrid
                ? NSSize(width: min(860, screen.width - 60), height: min(640, screen.height - 80))
                : NSSize(width: 380, height: 450))
        }
        previewIsGrid = isGrid || (wasVisible && previewIsGrid)
        if !wasVisible || expanding {
            let pointer = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
            if let screen {
                let frame = screen.visibleFrame
                let size = previewPanel?.frame.size ?? NSSize(width: 340, height: 400)
                previewPanel?.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                                     y: frame.midY - size.height / 2))
            }
        }
        if !wasVisible { previewPanel?.orderFrontRegardless() }
    }

    func windowWillClose(_ notification: Notification) {
        if let panel = notification.object as? NSPanel, panel === previewPanel { model.closeBatch() }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let body: String
    let htmlURL: String
    enum CodingKeys: String, CodingKey { case tagName = "tag_name", body, htmlURL = "html_url" }
}

struct BatchPhoto: Identifiable {
    let id: UUID
    let url: URL
    let thumbnail: NSImage
}

final class MacModel: ObservableObject {
    struct PendingScreenshot: Identifiable {
        let id: UUID
        let thumbnail: NSImage
    }
    let transport = NearbyTransport(role: .receiver, displayName: Host.current().localizedName ?? "My Mac")
    let inbox: URL
    private let photoStore: PhotoStore
    private var recentReceiptIDs: [String]
    private var latestClipboard: PhotoClipboard?
    private let receiveQueue = DispatchQueue(label: "local.snapbridge.receive", qos: .userInitiated)
    private let detailQueue = DispatchQueue(label: "local.snapbridge.image-detail", qos: .userInitiated)
    private var batch = PhotoBatch()
    @Published private(set) var latestImage: NSImage?
    @Published private(set) var pendingScreenshots: [PendingScreenshot] = []
    private var dismissedScreenshotIDs = Set<UUID>()
    private var groupGeneration = 0
    private var clipboardRefresh: DispatchWorkItem?
    @Published private(set) var latestURL: URL?
    @Published private(set) var receivedCount = 0
    @Published private(set) var copyStatus = "Copied — press ⌘V in your chat"
    @Published private(set) var batchPhotos: [BatchPhoto] = []
    @Published private(set) var focusedPhotoID: UUID?
    @Published private(set) var focusedImage: NSImage?
    @Published var launchError: String?
    var onNewPhoto: (() -> Void)?

    init() {
        inbox = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SnapBridge/Inbox", isDirectory: true)
        photoStore = PhotoStore(directory: inbox)
        recentReceiptIDs = UserDefaults.standard.stringArray(forKey: "recentReceiptIDs") ?? []
        do {
            let photos = try photoStore.prepare()
            receivedCount = photos.count
            if let latest = photos.last {
                latestURL = latest.url
                if let data = try? Data(contentsOf: latest.url), let clipboard = try? PhotoClipboard(image: data) {
                    latestClipboard = clipboard
                    latestImage = clipboard.preview
                }
            }
        } catch { launchError = "Photo storage could not be cleaned up: \(error.localizedDescription)" }
        transport.onPhoto = { [weak self] id, data, date, completion in
            guard let self else { completion(.failure(WireError.invalidPhoto)); return }
            self.receive(id: id, data: data, date: date, completion: completion)
        }
    }

    fileprivate func showScreenshotPreview(id: UUID, data: Data, date: Date) {
        guard !pendingScreenshots.contains(where: { $0.id == id }), !dismissedScreenshotIDs.contains(id) else { return }
        let generation = groupGeneration
        receiveQueue.async { [self] in
            guard !self.photoStore.contains(id), !self.recentReceiptIDs.contains(id.uuidString),
                  let preview = try? PhotoProcessing.thumbnail(data, maxPixels: 720) else { return }
            let image = NSImage(cgImage: preview, size: NSSize(width: preview.width, height: preview.height))
            DispatchQueue.main.async { [self] in
                guard self.groupGeneration == generation else {
                    self.dismissedScreenshotIDs.insert(id)
                    return
                }
                guard self.pendingScreenshots.count < PhotoStore.defaultLimit,
                      !self.pendingScreenshots.contains(where: { $0.id == id }) else { return }
                self.pendingScreenshots.append(PendingScreenshot(id: id, thumbnail: image))
                self.onNewPhoto?()
                let elapsed = Date().timeIntervalSince(date)
                if elapsed >= 0 {
                    PerformanceTrace.record("screenshot_save_to_preview", id: id, since: PerformanceTrace.now() - elapsed)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                    guard let self, self.groupGeneration == generation else { return }
                    self.pendingScreenshots.removeAll { $0.id == id }
                }
            }
        }
    }

    fileprivate func receive(id: UUID, data: Data, date: Date, completion: @escaping (Result<Void, Error>) -> Void) {
        let start = PerformanceTrace.now()
        receiveQueue.async {
            do {
                // Bounded receipts prevent retries from resurrecting deleted old photos.
                if self.photoStore.contains(id) || self.recentReceiptIDs.contains(id.uuidString) {
                    let count = try self.photoStore.retainNewest().count
                    DispatchQueue.main.async { self.receivedCount = count; completion(.success(())) }
                    return
                }
                let clipboard = try PhotoClipboard(image: data)
                let gridThumbnail: NSImage
                if clipboard.originalType == .png {
                    gridThumbnail = clipboard.preview
                } else {
                    let gridImage = try PhotoProcessing.thumbnail(data, maxPixels: 320)
                    gridThumbnail = NSImage(cgImage: gridImage, size: NSSize(width: gridImage.width, height: gridImage.height))
                }
                let retained = try self.photoStore.save(data, id: id, isPNG: clipboard.originalType == .png)
                self.recentReceiptIDs.append(id.uuidString)
                self.recentReceiptIDs = Array(self.recentReceiptIDs.suffix(256))
                UserDefaults.standard.set(self.recentReceiptIDs, forKey: "recentReceiptIDs")
                PerformanceTrace.record("mac_validate_save_preview", id: id, since: start, bytes: data.count)
                DispatchQueue.main.async {
                    let pending = self.pendingScreenshots.first { $0.id == id }
                    if pending != nil { self.pendingScreenshots.removeAll { $0.id == id } }
                    let dismissed = self.dismissedScreenshotIDs.remove(id) != nil
                    self.receivedCount = retained.count
                    if dismissed {
                        let retainedIDs = Set(retained.map(\.id))
                        self.batchPhotos.removeAll { !retainedIDs.contains($0.id) }
                        completion(.success(()))
                        return
                    }
                    self.latestClipboard = clipboard
                    self.latestImage = clipboard.preview
                    self.latestURL = self.photoStore.url(for: id)
                    self.batch.append(id, retained: Set(retained.map(\.id)))
                    self.batchPhotos.removeAll { !self.batch.ids.contains($0.id) }
                    self.batchPhotos.append(BatchPhoto(id: id, url: self.photoStore.url(for: id),
                                                       thumbnail: pending?.thumbnail ?? gridThumbnail))
                    if let focused = self.focusedPhotoID, !self.batch.ids.contains(focused) {
                        self.showGrid()
                    }
                    self.launchError = nil
                    self.updateClipboardAfterArrival()
                    self.onNewPhoto?()
                    PerformanceTrace.record("mac_preview_scheduled", id: id, since: start, bytes: data.count)
                    if clipboard.originalType == .png {
                        let secondsSinceSave = Date().timeIntervalSince(date)
                        if secondsSinceSave >= 0 {
                            PerformanceTrace.record("screenshot_save_to_popup", id: id,
                                                    since: PerformanceTrace.now() - secondsSinceSave)
                        }
                    }
                    completion(.success(()))
                }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }

    func copyLatest() {
        clipboardRefresh?.cancel()
        clipboardRefresh = nil
        guard let latestClipboard else { return }
        let pasteboard = NSPasteboard.general
        if batchPhotos.count > 1 {
            let success = PhotoClipboard.writeBatch(batchPhotos.map(\.url), to: pasteboard)
            copyStatus = success ? "\(batchPhotos.count) photos copied — press ⌘V together" : "Photos saved. Click Copy all to try again."
            return
        }
        pasteboard.clearContents()
        let success = pasteboard.writeObjects([latestClipboard.makeItem()])
        latestClipboard.prewarm()
        copyStatus = success ? "Copied — press ⌘V in your chat" : "Photo saved. Click Copy to try again."
    }

    private func updateClipboardAfterArrival() {
        if batchPhotos.count == 1 || pendingScreenshots.isEmpty {
            copyLatest()
            return
        }
        clipboardRefresh?.cancel()
        let refresh = DispatchWorkItem { [weak self] in self?.copyLatest() }
        clipboardRefresh = refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(90), execute: refresh)
    }

    func closeBatch() {
        groupGeneration += 1
        dismissedScreenshotIDs.formUnion(pendingScreenshots.map(\.id))
        pendingScreenshots = []
        if clipboardRefresh != nil { copyLatest() }
        batch.close()
        batchPhotos = []
        focusedPhotoID = nil
        focusedImage = nil
    }

    func reopenLatest() {
        guard batchPhotos.isEmpty, let url = latestURL, let image = latestImage,
              let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return }
        batch.append(id, retained: [id])
        batchPhotos = [BatchPhoto(id: id, url: url, thumbnail: image)]
    }

    func enlarge(_ photo: BatchPhoto) {
        focusedPhotoID = photo.id
        focusedImage = nil
        detailQueue.async {
            guard let data = try? Data(contentsOf: photo.url),
                  let image = try? PhotoProcessing.thumbnail(data, maxPixels: 2000) else { return }
            let preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            DispatchQueue.main.async { if self.focusedPhotoID == photo.id { self.focusedImage = preview } }
        }
    }

    func showGrid() { focusedPhotoID = nil; focusedImage = nil }

    func copyPhoto(_ photo: BatchPhoto) {
        receiveQueue.async {
            guard let data = try? Data(contentsOf: photo.url), let clipboard = try? PhotoClipboard(image: data) else { return }
            DispatchQueue.main.async {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                _ = pasteboard.writeObjects([clipboard.makeItem()])
                // The pasteboard retains its provider; only one full-size image is cached here.
                self.copyStatus = "One photo copied — press ⌘V"
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchError = nil
        } catch { launchError = "Login setting could not be changed: \(error.localizedDescription)" }
    }
}

private let bridgeGreen = Color(red: 0.35, green: 0.91, blue: 0.63)

struct MacSetupView: View {
    @ObservedObject var model: MacModel
    @ObservedObject var screenshotSetup: ScreenshotImportSetup
    @ObservedObject var transport: NearbyTransport
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var confirmReset = false
    @State private var workflow = "screenshots"

    init(model: MacModel, screenshotSetup: ScreenshotImportSetup) {
        self.model = model
        self.screenshotSetup = screenshotSetup
        transport = model.transport
        _workflow = State(initialValue: model.transport.hasPairedPhone ? "camera" : "screenshots")
    }

    var body: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.up.right.square").font(.system(size: 40, weight: .medium)).foregroundStyle(bridgeGreen)
                VStack(alignment: .leading, spacing: 3) {
                    Text("ShotSkiff").font(.system(size: 29, weight: .semibold, design: .rounded))
                    Text("From your iPhone. Straight to your Mac.").foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text("CHOOSE YOUR WORKFLOW")
                .font(.system(size: 11, weight: .bold)).tracking(1.6).foregroundStyle(.secondary)
            Picker("Workflow", selection: $workflow) {
                Text("Automatic Screenshots").tag("screenshots")
                Text("Camera + Screenshots").tag("camera")
            }
            .pickerStyle(.segmented)

            if workflow == "screenshots" { screenshotWorkflow } else { cameraWorkflow }
          }
          .padding(28)
        }
        .frame(width: 540, height: 690)
        .background(Color(red: 0.075, green: 0.095, blue: 0.09))
        .preferredColorScheme(.dark)
        .alert("Reset paired phones?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset pairing", role: .destructive) { transport.resetPairing() }
        } message: { Text("Phones will need to enter a new code before they can send photos again. Saved photos are kept.") }
    }

    private var screenshotWorkflow: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Use your iPhone’s regular screenshot buttons. No ShotSkiff app is required on the phone.")
                .font(.system(size: 15, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: screenshotSetup.isEnabled ? "checkmark.circle.fill" : "iphone.gen3.radiowaves.left.and.right")
                        .foregroundStyle(screenshotSetup.isEnabled ? bridgeGreen : .secondary)
                    Text(screenshotSetup.isEnabled ? "Screenshot importing is on" : "Connect and trust your iPhone")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text("Connect by USB the first time, unlock your iPhone, and tap Trust This Computer. If already trusted, a reachable Apple Wi-Fi device connection can also work.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if screenshotSetup.phones.isEmpty {
                    Label("No trusted iPhone found yet", systemImage: "exclamationmark.circle")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.orange)
                } else {
                    Picker("iPhone", selection: $screenshotSetup.selectedPhoneID) {
                        Text("Choose an iPhone…").tag("")
                        ForEach(screenshotSetup.phones) { phone in Text(phone.name).tag(phone.id) }
                    }
                    .disabled(screenshotSetup.isEnabled)
                }
                HStack {
                    Button("Refresh iPhones") { screenshotSetup.scan(); screenshotSetup.refreshDependencies() }
                    Spacer()
                    if screenshotSetup.dependencyAvailable {
                        if screenshotSetup.isEnabled {
                            Button("Pause importing") { screenshotSetup.disable() }
                        } else {
                            Button("Enable importing") { screenshotSetup.enable() }
                                .buttonStyle(.borderedProminent)
                                .disabled(screenshotSetup.selectedPhoneID.isEmpty)
                        }
                    } else {
                        Button("Install screenshot support…") { screenshotSetup.installDependency() }
                    }
                }
                Text(screenshotSetup.dependencyMessage).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(screenshotSetup.status).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(screenshotSetup.isEnabled ? bridgeGreen : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            Text("Take a screenshot with the usual side button + volume-up buttons. New images appear in the floating Mac preview, ready to paste or drag. Existing library photos are skipped.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Images stay on your devices. The Mac keeps at most 20 and permanently deletes the oldest when the limit is reached. Every received image replaces the clipboard.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cameraWorkflow: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Circle().fill(transport.connected ? bridgeGreen : .orange).frame(width: 7, height: 7)
                Text(transport.status).font(.system(size: 13, weight: .medium))
            }
            VStack(alignment: .leading, spacing: 14) {
                Text(transport.hasPairedPhone && !transport.showingPairingCode ? "PAIRED · RECONNECTS AUTOMATICALLY" : "PAIR YOUR IPHONE ONCE")
                    .font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(.secondary)
                if transport.hasPairedPhone && !transport.showingPairingCode {
                    Label(transport.pairedPhoneName, systemImage: "checkmark.shield.fill")
                        .font(.system(size: 27, weight: .semibold)).foregroundStyle(bridgeGreen)
                    Text("Your iPhone is remembered. Open its camera whenever you want to send a photo. No code needed.")
                        .font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(transport.pairingCode).font(.system(size: 48, weight: .medium, design: .monospaced)).tracking(9)
                    .textSelection(.enabled)
                    .accessibilityLabel("Pairing code \(transport.pairingCode)")
                    Text("Open ShotSkiff on your iPhone, choose this Mac, and enter this code once. They’ll remember each other.")
                        .font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 16) {
                instruction("1", "Open the camera", "Keep the iPhone app open while you shoot.")
                instruction("2", "Take a photo", "Each shot sends to this Mac automatically.")
                instruction("3", "Paste into your chat", "The photo appears here. Press ⌘V to attach it.")
            }
            if let error = transport.error ?? model.launchError {
                Text(error).font(.footnote).foregroundStyle(.orange).textSelection(.enabled)
            }
            Divider()
            Toggle("Start ShotSkiff when I log in", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in model.setLaunchAtLogin(enabled) }
            HStack {
                Button("Open received photos") { NSWorkspace.shared.open(model.inbox) }
                Spacer()
                Button("Change paired iPhone…") { confirmReset = true }.foregroundStyle(.secondary)
            }
            Text("\(model.receivedCount)/20 photos saved · Oldest deleted automatically")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func instruction(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(bridgeGreen).frame(width: 24, height: 24)
                .background(bridgeGreen.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

struct PhotoPreview: View {
    private struct Tile: Identifiable {
        let id: UUID
        let image: NSImage
        let photo: BatchPhoto?
    }

    @ObservedObject var model: MacModel
    private let columns = [GridItem(.adaptive(minimum: 155, maximum: 240), spacing: 14)]

    private var tiles: [Tile] {
        let ready = model.batchPhotos.map { Tile(id: $0.id, image: $0.thumbnail, photo: $0) }
        let readyIDs = Set(ready.map(\.id))
        let incoming = model.pendingScreenshots.filter { !readyIDs.contains($0.id) }
            .map { Tile(id: $0.id, image: $0.thumbnail, photo: nil) }
        return Array((ready + incoming).suffix(PhotoStore.defaultLimit))
    }

    var body: some View {
        let items = tiles
        let receiving = !model.pendingScreenshots.isEmpty
        VStack(spacing: 14) {
            if let focusedID = model.focusedPhotoID,
               let photo = model.batchPhotos.first(where: { $0.id == focusedID }) {
                HStack {
                    Button { model.showGrid() } label: { Label("All photos", systemImage: "square.grid.2x2") }
                    Spacer()
                    Button("Copy this photo") { model.copyPhoto(photo) }
                }
                if let image = model.focusedImage {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onDrag { NSItemProvider(contentsOf: photo.url) ?? NSItemProvider() }
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            } else if items.count > 1 {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, tile in
                                tileView(tile, number: index + 1).id(tile.id)
                            }
                        }.padding(2)
                    }
                    .onChange(of: items.last?.id) { _, id in
                        if let id { reader.scrollTo(id, anchor: .bottom) }
                    }
                }
            } else if let incoming = items.first, incoming.photo == nil {
                Image(nsImage: incoming.image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let image = model.latestImage, let url = model.latestURL {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
            }
            Label(receiving ? "Receiving \(model.pendingScreenshots.count) original(s)…" : model.copyStatus,
                  systemImage: receiving ? "arrow.down.circle" : "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(bridgeGreen)
            HStack {
                Button(receiving && !model.batchPhotos.isEmpty ? "Copy ready photos" :
                       model.batchPhotos.count > 1 ? "Copy all \(model.batchPhotos.count) photos" : "Copy photo") {
                    model.copyLatest()
                }.keyboardShortcut("c", modifiers: .command)
                Spacer()
                Button("Show in Finder") {
                    let urls = model.batchPhotos.isEmpty ? [model.latestURL].compactMap { $0 } : model.batchPhotos.map(\.url)
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                }
            }.disabled(model.batchPhotos.isEmpty && receiving)
            Text("New shots join this group. Close this window to start a new one.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(16).frame(minWidth: 280, minHeight: 260)
            .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func tileView(_ tile: Tile, number: Int) -> some View {
        let label = VStack(spacing: 8) {
            Image(nsImage: tile.image).resizable().scaledToFit()
                .frame(maxWidth: .infinity).frame(height: 150)
            Text(tile.photo == nil ? "Receiving…" : "Photo \(number)")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }.padding(10).frame(maxWidth: .infinity)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        if let photo = tile.photo {
            Button { model.enlarge(photo) } label: { label }
                .buttonStyle(.plain)
                .accessibilityLabel("Open photo \(number)")
                .onDrag { NSItemProvider(contentsOf: photo.url) ?? NSItemProvider() }
                .contextMenu {
                    Button("Copy this photo") { model.copyPhoto(photo) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([photo.url]) }
                }
        } else {
            label
        }
    }
}
