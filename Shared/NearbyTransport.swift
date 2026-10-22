import Foundation
import Combine
import MultipeerConnectivity

struct NearbyMac: Identifiable {
    let id: UUID
    let name: String
    let peer: MCPeerID
}

final class NearbyTransport: NSObject, ObservableObject {
    enum Role { case receiver, camera }
    @Published private(set) var connected = false
    @Published private(set) var status = "Starting…"
    @Published private(set) var connectedName = ""
    @Published private(set) var nearbyMacs: [NearbyMac] = []
    @Published private(set) var pairingCode = String(format: "%06d", Int.random(in: 0...999999))
    @Published private(set) var pairing: PairingRecord?
    @Published private(set) var hasPairedPhone = false
    @Published private(set) var pairedPhoneName = "Your iPhone"
    @Published private(set) var error: String?
    @Published private(set) var showingPairingCode = false

    var onPhoto: ((UUID, Data, Date, @escaping (Result<Void, Error>) -> Void) -> Void)?
    var onReceipt: ((UUID) -> Void)?
    var onRejected: ((UUID, String) -> Void)?
    var onConnected: (() -> Void)?
    var onTransferProgress: (() -> Void)?
    var onPairingRequested: (() -> Void)?
    let role: Role
    let deviceID: UUID
    private let peerID: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var trustedTokens: [String: String]
    private var authorized: [MCPeerID: PairingRequest] = [:]
    private var invitedPeer: MCPeerID?
    private var inviteDeadline: DispatchWorkItem?
    private var retryWork: DispatchWorkItem?
    private var isRunning = false
    private var failedInvitations = 0
    private var blockedUntil = Date.distantPast
    private let sendQueue = DispatchQueue(label: "local.snapbridge.send", qos: .userInitiated)
    private let fast = FastPhotoChannel()
    private var fastConnected = false
    private var legacyReady = false
    private var legacyFallback: DispatchWorkItem?
    private var discoverySuspended = false
    private var lastPairingPrompt = Date.distantPast

    init(role: Role, displayName: String) {
        self.role = role
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: "deviceID"), let id = UUID(uuidString: value) {
            deviceID = id
        } else {
            deviceID = UUID()
            defaults.set(deviceID.uuidString, forKey: "deviceID")
        }
        if let data = defaults.data(forKey: "peerIdentity"),
           let saved = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data) {
            peerID = saved
        } else {
            peerID = MCPeerID(displayName: String(displayName.prefix(50)))
            defaults.set(try? NSKeyedArchiver.archivedData(withRootObject: peerID,
                                                         requiringSecureCoding: true), forKey: "peerIdentity")
        }
        trustedTokens = KeychainStore.load([String: String].self, key: "trusted-phones") ?? [:]
        pairing = KeychainStore.load(PairingRecord.self, key: "paired-mac")
        hasPairedPhone = !trustedTokens.isEmpty
        pairedPhoneName = defaults.string(forKey: "pairedPhoneName") ?? "Your iPhone"
        super.init()
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        fast.onReady = { [weak self] name in
            guard let self, self.isRunning, self.role == .receiver || self.pairing != nil else { return }
            self.fastConnected = true
            self.connectedName = name
            self.connected = true
            self.error = nil
            self.status = "Connected to \(name)"
            self.legacyFallback?.cancel()
            self.inviteDeadline?.cancel()
            self.browser?.stopBrowsingForPeers()
            self.advertiser?.stopAdvertisingPeer()
            self.onConnected?()
        }
        fast.onDisconnected = { [weak self] in
            guard let self, self.isRunning else { return }
            self.fastConnected = false
            if !self.legacyReady {
                self.connected = false
                self.status = self.role == .camera ? "Reconnecting to your Mac…" : "Ready for your iPhone"
            }
            self.scheduleLegacyFallback()
        }
        fast.onTransferProgress = { [weak self] in self?.onTransferProgress?() }
        fast.onPacket = { [weak self] packet, reply in
            guard let self, self.isRunning else { return }
            switch packet.header.kind {
            case .pairingRequested:
                if self.role == .receiver { self.showPairingCode(); self.onPairingRequested?() }
            case .photo:
                guard self.role == .receiver, let onPhoto = self.onPhoto else { return }
                onPhoto(packet.header.id, packet.payload, packet.header.createdAt ?? Date()) { result in
                    switch result {
                    case .success: reply(WirePacket(header: WireHeader(kind: .received, id: packet.header.id)))
                    case .failure(let error):
                        self.error = error.localizedDescription
                        reply(WirePacket(header: WireHeader(kind: .rejected, id: packet.header.id, message: error.localizedDescription)))
                    }
                }
            case .received: if self.role == .camera { self.onReceipt?(packet.header.id) }
            case .rejected: if self.role == .camera { self.onRejected?(packet.header.id, packet.header.message ?? "Photo could not be saved.") }
            default: break
            }
        }
    }

    func start() {
        discoverySuspended = false
        if isRunning {
            fast.resume()
            if !fastConnected { scheduleLegacyFallback() }
            return
        }
        isRunning = true
        error = nil
        if role == .receiver {
            let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: [
                "id": deviceID.uuidString, "v": "1", "name": peerID.displayName
            ], serviceType: BridgeLimits.serviceType)
            advertiser.delegate = self
            self.advertiser = advertiser
            if trustedTokens.isEmpty { advertiser.startAdvertisingPeer() }
            else {
                fast.startReceiver(id: deviceID, tokens: trustedTokens, name: peerID.displayName)
                scheduleLegacyFallback()
            }
            status = "Ready for your iPhone"
        } else {
            let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: BridgeLimits.serviceType)
            browser.delegate = self
            self.browser = browser
            if let pairing {
                fast.startSender(pairing: pairing, deviceID: deviceID, name: peerID.displayName)
                scheduleLegacyFallback()
            } else { browser.startBrowsingForPeers() }
            status = pairing == nil ? "Pair your Mac to start" : "Looking for \(pairing!.receiverName)…"
        }
    }

    func stop() {
        isRunning = false
        legacyFallback?.cancel()
        fast.stop()
        fastConnected = false
        legacyReady = false
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        browser = nil
        advertiser = nil
        inviteDeadline?.cancel()
        retryWork?.cancel()
        invitedPeer = nil
        connected = false
        nearbyMacs = []
        authorized = [:]
        session.disconnect()
        status = "Paused"
    }

    func pauseForBackground() {
        discoverySuspended = true
        legacyFallback?.cancel()
        retryWork?.cancel()
        browser?.stopBrowsingForPeers()
        fast.pause()
    }

    func pair(with mac: NearbyMac, code: String) {
        guard !connected, invitedPeer == nil else { return }
        error = nil
        invite(mac.peer, request: PairingRequest(deviceID: deviceID, code: code, token: nil))
    }

    func requestPairingCode(for mac: NearbyMac) {
        guard role == .camera, pairing == nil,
              let context = try? JSONEncoder().encode(PairingRequest(deviceID: deviceID, code: nil,
                                                                     token: nil, requestsCode: true)) else { return }
        browser?.invitePeer(mac.peer, to: session, withContext: context, timeout: 2)
    }

    func showPairingCode() {
        guard role == .receiver else { return }
        if !showingPairingCode { pairingCode = String(format: "%06d", Int.random(in: 0...999999)) }
        showingPairingCode = true
        advertiser?.startAdvertisingPeer()
    }

    func reconnect() {
        error = nil
        guard isRunning, !connected, invitedPeer == nil, let pairing,
              let mac = nearbyMacs.first(where: { $0.id == pairing.receiverID }) else { return }
        invite(mac.peer, request: PairingRequest(deviceID: deviceID, code: nil, token: pairing.token))
    }

    func forgetMac() {
        // An intentional change requests setup on the Mac; a radio drop never does.
        let request = WirePacket(header: WireHeader(kind: .pairingRequested))
        if fastConnected { fast.send(request) { _ in } }
        else if let peer = session.connectedPeers.first { try? send(request, to: peer) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.fast.stop() }
        fastConnected = false
        legacyReady = false
        pairing = nil
        KeychainStore.delete("paired-mac")
        invitedPeer = nil
        inviteDeadline?.cancel()
        retryWork?.cancel()
        connected = false
        session.disconnect()
        status = "Pair your Mac to start"
        browser?.startBrowsingForPeers()
    }

    func resetPairing() {
        fast.stop()
        fastConnected = false
        legacyReady = false
        trustedTokens = [:]
        hasPairedPhone = false
        pairedPhoneName = "Your iPhone"
        KeychainStore.delete("trusted-phones")
        authorized = [:]
        connected = false
        session.disconnect()
        pairingCode = String(format: "%06d", Int.random(in: 0...999999))
        showingPairingCode = true
        status = "Pairing reset. Enter the new code on your iPhone."
        advertiser?.startAdvertisingPeer()
    }

    func clearError() { error = nil }

    func recoverStalledTransfer() {
        fastConnected = false
        legacyReady = false
        connected = false
        invitedPeer = nil
        session.disconnect()
        fast.recover()
        status = "Reconnecting — your photo is kept safely"
        scheduleLegacyFallback()
    }

    func sendPhoto(id: UUID, data: Data, date: Date, completion: @escaping (Result<Void, Error>) -> Void) {
        if fastConnected {
            let start = PerformanceTrace.now()
            fast.send(WirePacket(header: WireHeader(kind: .photo, id: id, createdAt: date), payload: data)) { result in
                PerformanceTrace.record("enqueue_direct_tls", id: id, since: start, bytes: data.count)
                completion(result)
            }
            return
        }
        guard connected, let peer = session.connectedPeers.first else {
            completion(.failure(NSError(domain: "SnapBridge", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Your Mac is disconnected. The photo is queued."])))
            return
        }
        sendQueue.async {
            let start = PerformanceTrace.now()
            do {
                try self.send(WirePacket(header: WireHeader(kind: .photo, id: id, createdAt: date), payload: data), to: peer)
                PerformanceTrace.record("enqueue_transport", id: id, since: start, bytes: data.count)
                DispatchQueue.main.async { completion(.success(())) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }

    private func invite(_ peer: MCPeerID, request: PairingRequest) {
        guard let context = try? JSONEncoder().encode(request) else { return }
        invitedPeer = peer
        status = "Connecting to \(peer.displayName)…"
        browser?.invitePeer(peer, to: session, withContext: context, timeout: 3)
        inviteDeadline?.cancel()
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, !self.connected, self.invitedPeer == peer else { return }
            self.invitedPeer = nil
            self.error = "Could not connect. Check the pairing code, open SnapBridge on the Mac, and allow Local Network access."
            self.status = "Connection needs attention"
            self.scheduleReconnect()
        }
        inviteDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: deadline)
    }

    private func send(_ packet: WirePacket, to peer: MCPeerID) throws {
        try session.send(packet.encoded(), toPeers: [peer], with: .reliable)
    }

    private func scheduleReconnect() {
        guard role == .camera, isRunning, !discoverySuspended, pairing != nil else { return }
        retryWork?.cancel()
        let retry = DispatchWorkItem { [weak self] in self?.reconnect() }
        retryWork = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: retry)
    }

    private func scheduleLegacyFallback() {
        legacyFallback?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning, !self.discoverySuspended, !self.fastConnected else { return }
            if self.role == .camera { self.browser?.startBrowsingForPeers(); self.reconnect() }
            else { self.advertiser?.startAdvertisingPeer() }
        }
        legacyFallback = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func handle(_ data: Data, from peer: MCPeerID) {
        do {
            let packet = try WirePacket.decode(data)
            #if DEBUG
            print("[SnapBridge] Received \(packet.header.kind.rawValue) from expected peer: \(peer == invitedPeer)")
            #endif
            switch packet.header.kind {
            case .pairingRequested:
                guard role == .receiver, authorized[peer] != nil else { return }
                showPairingCode()
                onPairingRequested?()
            case .paired:
                guard role == .camera, peer == invitedPeer, let record = packet.header.pairing,
                      record.token.count >= 32 else { return }
                do { try KeychainStore.save(record, key: "paired-mac") }
                catch {
                    inviteDeadline?.cancel()
                    session.disconnect()
                    throw error
                }
                pairing = record
                connectedName = record.receiverName
                connected = true
                legacyReady = true
                status = "Connected to \(record.receiverName)"
                error = nil
                inviteDeadline?.cancel()
                browser?.stopBrowsingForPeers()
                if !fastConnected { fast.startSender(pairing: record, deviceID: deviceID, name: peerID.displayName) }
                onConnected?()
            case .photo:
                guard role == .receiver, authorized[peer] != nil else { return }
                guard let onPhoto else { throw WireError.invalidPhoto }
                onPhoto(packet.header.id, packet.payload, packet.header.createdAt ?? Date()) { [weak self] result in
                    guard let self, self.authorized[peer] != nil else { return }
                    switch result {
                    case .success:
                        try? self.send(WirePacket(header: WireHeader(kind: .received, id: packet.header.id)), to: peer)
                    case .failure(let error):
                        try? self.send(WirePacket(header: WireHeader(kind: .rejected, id: packet.header.id,
                                                                   message: error.localizedDescription)), to: peer)
                        self.error = error.localizedDescription
                    }
                }
            case .received:
                guard role == .camera, connected, peer == invitedPeer else { return }
                onReceipt?(packet.header.id)
            case .rejected:
                guard role == .camera, connected, peer == invitedPeer else { return }
                onRejected?(packet.header.id, packet.header.message ?? "The Mac could not save this photo.")
            case .hello, .ping, .pong: break
            }
        } catch {
            self.error = error.localizedDescription
            #if DEBUG
            print("[SnapBridge] Receive failed: \(error.localizedDescription)")
            #endif
        }
    }
}

extension NearbyTransport: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            switch state {
            case .connected:
                if self.role == .receiver, let request = self.authorized[peerID] {
                    do {
                        let token: String
                        if let saved = self.trustedTokens[request.deviceID.uuidString] { token = saved }
                        else { token = try KeychainStore.randomToken() }
                        var tokens = self.trustedTokens
                        tokens[request.deviceID.uuidString] = token
                        try KeychainStore.save(tokens, key: "trusted-phones")
                        self.trustedTokens = tokens
                        self.hasPairedPhone = true
                        self.showingPairingCode = false
                        self.pairedPhoneName = peerID.displayName
                        UserDefaults.standard.set(peerID.displayName, forKey: "pairedPhoneName")
                        let record = PairingRecord(receiverID: self.deviceID,
                                                   receiverName: self.peerID.displayName, token: token)
                        try self.send(WirePacket(header: WireHeader(kind: .paired, pairing: record)), to: peerID)
                        self.connected = true
                        self.legacyReady = true
                        self.connectedName = peerID.displayName
                        self.status = "Connected to \(peerID.displayName)"
                        self.error = nil
                        self.advertiser?.stopAdvertisingPeer()
                        if !self.fastConnected {
                            self.fast.startReceiver(id: self.deviceID, tokens: self.trustedTokens, name: self.peerID.displayName)
                        }
                    } catch {
                        self.error = error.localizedDescription
                        self.session.disconnect()
                    }
                } else if self.role == .camera {
                    self.status = "Finishing secure pairing…"
                }
            case .connecting: break
            case .notConnected:
                self.authorized.removeValue(forKey: peerID)
                guard self.role == .receiver || self.invitedPeer == peerID else { return }
                self.legacyReady = false
                self.invitedPeer = nil
                self.inviteDeadline?.cancel()
                if self.fastConnected { return }
                self.connected = false
                self.connectedName = ""
                self.invitedPeer = nil
                self.inviteDeadline?.cancel()
                self.status = self.role == .receiver ? "Ready for your iPhone" : "Reconnecting to your saved Mac…"
                self.scheduleReconnect()
                if self.role == .receiver { self.advertiser?.startAdvertisingPeer() }
                else if !self.discoverySuspended { self.browser?.startBrowsingForPeers() }
            @unknown default: break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in self?.handle(data, from: peerID) }
    }
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String,
                 fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension NearbyTransport: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning,
                  let context, context.count < 2048,
                  let request = try? JSONDecoder().decode(PairingRequest.self, from: context) else {
                invitationHandler(false, nil); return
            }
            if request.requestsCode == true, request.code == nil, request.token == nil {
                // This only reveals setup locally; no code/token is sent to the requester.
                if Date().timeIntervalSince(self.lastPairingPrompt) >= 5 {
                    self.lastPairingPrompt = Date()
                    self.showPairingCode()
                    self.onPairingRequested?()
                }
                invitationHandler(false, nil)
                return
            }
            guard Date() >= self.blockedUntil, self.authorized.isEmpty,
                  self.session.connectedPeers.isEmpty else { invitationHandler(false, nil); return }
            guard request.isAuthorized(pairingCode: self.pairingCode,
                                       savedToken: self.trustedTokens[request.deviceID.uuidString]) else {
                self.failedInvitations += 1
                if self.failedInvitations >= 5 {
                    self.blockedUntil = Date().addingTimeInterval(30)
                    self.failedInvitations = 0
                }
                invitationHandler(false, nil); return
            }
            self.failedInvitations = 0
            self.authorized[peerID] = request
            invitationHandler(true, self.session)
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.error = "Discovery could not start: \(error.localizedDescription). Check Local Network permission in System Settings."
            self?.status = "Local Network access needed"
        }
    }
}

extension NearbyTransport: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let value = info?["id"], let id = UUID(uuidString: value),
                  info?["v"] == "1" else { return }
            self.nearbyMacs.removeAll { $0.id == id }
            self.nearbyMacs.append(NearbyMac(id: id, name: info?["name"] ?? peerID.displayName, peer: peerID))
            self.reconnect()
        }
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in self?.nearbyMacs.removeAll { $0.peer == peerID } }
    }
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.error = "Could not find nearby Macs: \(error.localizedDescription). Allow Local Network access in Settings."
            self?.status = "Local Network access needed"
        }
    }
}
