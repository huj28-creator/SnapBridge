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
    private var screenshots: PhoneScreenshots?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model = MacModel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.badge.ellipsis", accessibilityDescription: "SnapBridge")
        statusItem.button?.toolTip = "SnapBridge — iPhone photos, ready to paste"
        let menu = NSMenu()
        menu.addItem(withTitle: "SnapBridge", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        addMenuItem("Pair iPhone / Settings…", action: #selector(showSetup), to: menu)
        addMenuItem("Show Latest Photo", action: #selector(showLatest), to: menu)
        addMenuItem("Open Received Photos", action: #selector(openInbox), to: menu)
        menu.addItem(.separator())
        addMenuItem("Quit SnapBridge", action: #selector(quit), to: menu, key: "q")
        statusItem.menu = menu
        model.onNewPhoto = { [weak self] in self?.showPreview() }
        model.transport.onPairingRequested = { [weak self] in self?.showSetup() }
        model.transport.$connected.sink { [weak self] connected in
            self?.statusItem.button?.image = NSImage(systemSymbolName: connected ? "camera.fill" : "camera.badge.ellipsis",
                                                     accessibilityDescription: "SnapBridge")
        }.store(in: &subscriptions)
        model.transport.start()
        screenshots = PhoneScreenshots { [weak self] id, data, date in
            self?.model.receive(id: id, data: data, date: date) { _ in }
        }
        screenshots?.onPreview = { [weak self] id, data, date in
            self?.model.showScreenshotPreview(id: id, data: data, date: date)
        }
        screenshots?.start()
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
            window.title = "SnapBridge"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MacSetupView(model: model))
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
        let count = model.batchPhotos.count
        previewPanel?.title = count > 1 ? "\(count) photos received" : "Photo received"
        if !wasVisible || count == 2 {
            let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1200, height: 800)
            previewPanel?.setContentSize(count > 1
                ? NSSize(width: min(860, screen.width - 60), height: min(640, screen.height - 80))
                : NSSize(width: 380, height: 450))
        }
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        if let screen {
            let frame = screen.visibleFrame
            let size = previewPanel?.frame.size ?? NSSize(width: 340, height: 400)
            previewPanel?.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                                 y: frame.midY - size.height / 2))
        }
        previewPanel?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        if let panel = notification.object as? NSPanel, panel === previewPanel { model.closeBatch() }
    }
}

struct BatchPhoto: Identifiable {
    let id: UUID
    let url: URL
    let thumbnail: NSImage
}

final class MacModel: ObservableObject {
    let transport = NearbyTransport(role: .receiver, displayName: Host.current().localizedName ?? "My Mac")
    let inbox: URL
    private let photoStore: PhotoStore
    private var recentReceiptIDs: [String]
    private var latestClipboard: PhotoClipboard?
    private let receiveQueue = DispatchQueue(label: "local.snapbridge.receive", qos: .userInitiated)
    private var batch = PhotoBatch()
    @Published private(set) var latestImage: NSImage?
    @Published private(set) var screenshotPreview: NSImage?
    private var screenshotPreviewID: UUID?
    private var dismissedScreenshotID: UUID?
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
        guard id != screenshotPreviewID, id != dismissedScreenshotID else { return }
        receiveQueue.async {
            guard !self.photoStore.contains(id), !self.recentReceiptIDs.contains(id.uuidString),
                  let preview = try? PhotoProcessing.thumbnail(data, maxPixels: 720) else { return }
            let image = NSImage(cgImage: preview, size: NSSize(width: preview.width, height: preview.height))
            DispatchQueue.main.async {
                self.screenshotPreviewID = id
                self.screenshotPreview = image
                self.onNewPhoto?()
                let elapsed = Date().timeIntervalSince(date)
                if elapsed >= 0 {
                    PerformanceTrace.record("screenshot_save_to_preview", id: id, since: PerformanceTrace.now() - elapsed)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                    guard let self, self.screenshotPreviewID == id else { return }
                    self.screenshotPreview = nil
                    self.screenshotPreviewID = nil
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
                    if self.screenshotPreviewID == id {
                        self.screenshotPreview = nil
                        self.screenshotPreviewID = nil
                    }
                    self.latestClipboard = clipboard
                    self.latestImage = clipboard.preview
                    self.latestURL = self.photoStore.url(for: id)
                    self.receivedCount = retained.count
                    self.batch.append(id, retained: Set(retained.map(\.id)))
                    self.batchPhotos.removeAll { !self.batch.ids.contains($0.id) }
                    self.batchPhotos.append(BatchPhoto(id: id, url: self.photoStore.url(for: id), thumbnail: gridThumbnail))
                    self.focusedPhotoID = nil
                    self.focusedImage = nil
                    self.launchError = nil
                    self.copyLatest()
                    if self.dismissedScreenshotID == id {
                        self.dismissedScreenshotID = nil
                    } else {
                        self.onNewPhoto?()
                    }
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

    func closeBatch() {
        dismissedScreenshotID = screenshotPreviewID
        screenshotPreviewID = nil
        screenshotPreview = nil
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
        receiveQueue.async {
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
    @ObservedObject var transport: NearbyTransport
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var confirmReset = false

    init(model: MacModel) { self.model = model; transport = model.transport }

    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack(spacing: 14) {
                Image(systemName: "camera.aperture").font(.system(size: 40, weight: .medium)).foregroundStyle(bridgeGreen)
                VStack(alignment: .leading, spacing: 3) {
                    Text("SnapBridge").font(.system(size: 29, weight: .semibold, design: .rounded))
                    Text("From your phone. Ready to paste.").foregroundStyle(.secondary)
                }
                Spacer()
            }
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
                    Text("Open SnapBridge on your iPhone, choose this Mac, and enter this code once. They’ll remember each other.")
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
            Toggle("Start SnapBridge when I log in", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in model.setLaunchAtLogin(enabled) }
            HStack {
                Button("Open received photos") { NSWorkspace.shared.open(model.inbox) }
                Spacer()
                Button("Change paired iPhone…") { confirmReset = true }.foregroundStyle(.secondary)
            }
            Text("\(model.receivedCount)/20 photos saved · Oldest photos deleted automatically")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(30).frame(width: 520)
        .background(Color(red: 0.075, green: 0.095, blue: 0.09))
        .preferredColorScheme(.dark)
        .alert("Reset paired phones?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset pairing", role: .destructive) { transport.resetPairing() }
        } message: { Text("Phones will need to enter a new code before they can send photos again. Saved photos are kept.") }
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
    @ObservedObject var model: MacModel
    private let columns = [GridItem(.adaptive(minimum: 155, maximum: 240), spacing: 14)]

    var body: some View {
        VStack(spacing: 14) {
            if let preview = model.screenshotPreview {
                Image(nsImage: preview).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let focusedID = model.focusedPhotoID,
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
            } else if model.batchPhotos.count > 1 {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(Array(model.batchPhotos.enumerated()), id: \.element.id) { index, photo in
                                Button { model.enlarge(photo) } label: {
                                    VStack(spacing: 8) {
                                        Image(nsImage: photo.thumbnail).resizable().scaledToFit()
                                            .frame(maxWidth: .infinity).frame(height: 150)
                                        Text("Photo \(index + 1)").font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }.padding(10).frame(maxWidth: .infinity)
                                        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain).id(photo.id)
                                    .accessibilityLabel("Open photo \(index + 1)")
                                    .onDrag { NSItemProvider(contentsOf: photo.url) ?? NSItemProvider() }
                                    .contextMenu {
                                        Button("Copy this photo") { model.copyPhoto(photo) }
                                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([photo.url]) }
                                    }
                            }
                        }.padding(2)
                    }
                    .onChange(of: model.batchPhotos.last?.id) { _, id in
                        if let id { reader.scrollTo(id, anchor: .bottom) }
                    }
                }
            } else if let image = model.latestImage, let url = model.latestURL {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
            }
            Label(model.screenshotPreview == nil ? model.copyStatus : "Receiving original…",
                  systemImage: model.screenshotPreview == nil ? "checkmark.circle.fill" : "arrow.down.circle")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(bridgeGreen)
            HStack {
                Button(model.batchPhotos.count > 1 ? "Copy all \(model.batchPhotos.count) photos" : "Copy photo") {
                    model.copyLatest()
                }.keyboardShortcut("c", modifiers: .command)
                Spacer()
                Button("Show in Finder") {
                    let urls = model.batchPhotos.isEmpty ? [model.latestURL].compactMap { $0 } : model.batchPhotos.map(\.url)
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                }
            }.disabled(model.screenshotPreview != nil)
            Text("New shots join this group. Close this window to start a new one.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(16).frame(minWidth: 280, minHeight: 260)
            .preferredColorScheme(.dark)
    }
}
