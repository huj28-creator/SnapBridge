import Foundation
import Network
import Security

/// Direct LAN TLS/TCP, authenticated with the existing random pairing token.
/// Discovery stops before connecting; no repeated pairing or image transcoding.
final class FastPhotoChannel {
    static let serviceType = "_snapbridge-v1._tcp"
    var onReady: ((String) -> Void)?
    var onDisconnected: (() -> Void)?
    var onTransferProgress: (() -> Void)?
    var onPacket: ((WirePacket, @escaping (WirePacket) -> Void) -> Void)?
    var onListening: ((UInt16) -> Void)?
    private let queue = DispatchQueue(label: "local.snapbridge.fast-network", qos: .userInitiated)
    private var listener: NWListener?
    private var active: FastSocket?
    private var candidates: [UUID: FastSocket] = [:]
    private var sender: (PairingRecord, UUID, String)?
    private var receiver: (UUID, [String: String], String)?
    private var running = false
    private var suspended = false
    private var retry: DispatchWorkItem?
    private var retryAttempt = 0
    private var heartbeat: DispatchSourceTimer?
    private var lastResponse = PerformanceTrace.now()

    static func parameters(keys: [String: String]) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        for (identity, token) in keys {
            guard let key = Data(base64Encoded: token), key.count == 32 else { continue }
            let keyBytes = key.withUnsafeBytes { DispatchData(bytes: $0) }
            let name = Data(identity.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
            sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions,
                                                   keyBytes as __DispatchData, name as __DispatchData)
        }
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions,
            tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 2
        tcp.keepaliveInterval = 1
        tcp.keepaliveCount = 2
        tcp.connectionTimeout = 2
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = true
        parameters.prohibitedInterfaceTypes = [.cellular]
        return parameters
    }

    func startReceiver(id: UUID, tokens: [String: String], name: String) {
        queue.async { [self] in
            self.stopLocked()
            self.running = true
            self.receiver = (id, tokens, name)
            self.listenLocked()
        }
    }

    private func listenLocked() {
        guard running, listener == nil, let receiver, !receiver.1.isEmpty else { return }
        do {
            let listener = try NWListener(using: Self.parameters(keys: receiver.1))
            listener.service = NWListener.Service(name: receiver.0.uuidString, type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] connection in
                guard let self, self.running, self.candidates.count < 4 else { connection.cancel(); return }
                self.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener, self.listener === listener else { return }
                if case .ready = state, let port = listener.port?.rawValue {
                    PerformanceTrace.connection("listener_ready port=\(port)")
                    DispatchQueue.main.async { self.onListening?(port) }
                } else if case .failed(let error) = state {
                    PerformanceTrace.connection("listener_failed \(error)")
                    listener.cancel()
                    self.listener = nil
                    self.retryListener()
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch { retryListener() }
    }

    private func retryListener() {
        guard running, receiver != nil else { return }
        retry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.listenLocked() }
        retry = work
        let delay = min(4, 0.5 * pow(2, Double(min(retryAttempt, 3))))
        retryAttempt += 1
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func startSender(pairing: PairingRecord, deviceID: UUID, name: String) {
        queue.async {
            self.stopLocked()
            self.running = true
            self.sender = (pairing, deviceID, name)
            self.connectSavedReceiverLocked()
        }
    }

    /// Also used by the localhost integration tests to bypass Bonjour discovery.
    func connect(to endpoint: NWEndpoint, pairing: PairingRecord, deviceID: UUID, name: String) {
        queue.async {
            self.stopLocked()
            self.running = true
            self.sender = (pairing, deviceID, name)
            self.connectLocked(endpoint)
        }
    }

    func stop() { queue.async { self.stopLocked() } }

    func pause() {
        queue.async {
            self.suspended = true
            self.retry?.cancel()
            self.heartbeat?.cancel()
            self.heartbeat = nil
            // Keep the authenticated socket. iOS may retain it while the app is suspended.
        }
    }

    func resume() {
        queue.async {
            self.suspended = false
            self.retryAttempt = 0
            self.lastResponse = PerformanceTrace.now()
            if let active = self.active {
                self.startHeartbeat()
                active.send(WirePacket(header: WireHeader(kind: .ping))) { _ in }
            } else { self.connectSavedReceiverLocked() }
        }
    }

    func recover() {
        queue.async {
            guard self.sender != nil else { return }
            self.retryAttempt = 0
            self.active?.close()
            self.active = nil
            self.candidates.values.forEach { $0.close() }
            self.candidates = [:]
            self.connectSavedReceiverLocked()
        }
    }

    func send(_ packet: WirePacket, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            guard let active = self.active else {
                DispatchQueue.main.async { completion(.failure(FastChannelError.disconnected)) }
                return
            }
            active.send(packet) { result in DispatchQueue.main.async { completion(result) } }
        }
    }

    private func connectSavedReceiverLocked() {
        guard running, !suspended, let sender, active == nil, candidates.isEmpty else { return }
        retry?.cancel()
        // The saved receiver ID is already its Bonjour service name. Resolve and
        // connect directly, without browsing or waiting for a discovered-device list.
        let endpoint = NWEndpoint.service(name: sender.0.receiverID.uuidString,
                                          type: Self.serviceType, domain: "local.", interface: nil)
        connectLocked(endpoint)
    }

    private func connectLocked(_ endpoint: NWEndpoint) {
        guard let sender, running, !suspended else { return }
        let parameters = Self.parameters(keys: [sender.1.uuidString: sender.0.token])
        PerformanceTrace.connection("direct_connect \(endpoint)")
        accept(NWConnection(to: endpoint, using: parameters))
    }

    private func accept(_ connection: NWConnection) {
        let socket = FastSocket(connection: connection, queue: queue)
        candidates[socket.id] = socket
        socket.onReady = { [weak self, weak socket] in
            guard let self, let socket else { return }
            if let sender = self.sender {
                socket.send(WirePacket(header: WireHeader(kind: .hello, id: sender.1, message: sender.2))) { _ in }
            } else if let receiver = self.receiver {
                socket.send(WirePacket(header: WireHeader(kind: .hello, id: receiver.0, message: receiver.2))) { _ in }
            }
        }
        socket.onPacket = { [weak self, weak socket] packet in
            guard let self, let socket else { return }
            if self.active !== socket {
                guard packet.header.kind == .hello else { socket.close(); return }
                if let sender = self.sender {
                    guard packet.header.id == sender.0.receiverID else { socket.close(); return }
                } else if let receiver = self.receiver {
                    guard receiver.1[packet.header.id.uuidString] != nil else { socket.close(); return }
                }
                self.active?.close()
                self.active = socket
                self.retryAttempt = 0
                self.lastResponse = PerformanceTrace.now()
                self.startHeartbeat()
                PerformanceTrace.connection("direct_authenticated")
                let name = String((packet.header.message ?? "Paired device").prefix(64))
                DispatchQueue.main.async { self.onReady?(name) }
                return
            }
            self.lastResponse = PerformanceTrace.now()
            if packet.header.kind == .ping {
                socket.send(WirePacket(header: WireHeader(kind: .pong, id: packet.header.id))) { _ in }
            } else if packet.header.kind == .pong, packet.header.message == "receiving-photo" {
                DispatchQueue.main.async { self.onTransferProgress?() }
            } else if packet.header.kind != .pong {
                DispatchQueue.main.async { [self, socket] in
                    self.onPacket?(packet) { [weak self, weak socket] reply in
                        guard let self, let socket else { return }
                        self.queue.async { if self.active === socket { socket.send(reply) { _ in } } }
                    }
                }
            }
        }
        socket.onReceiveProgress = { [weak self, weak socket] in
            guard let self, let socket, self.receiver != nil, self.active === socket else { return }
            // Acknowledge real receive progress, independently of TCP's local send buffer.
            socket.send(WirePacket(header: WireHeader(kind: .pong, message: "receiving-photo"))) { _ in }
        }
        socket.onClosed = { [weak self, weak socket] in
            guard let self, let socket else { return }
            self.candidates.removeValue(forKey: socket.id)
            if self.active === socket {
                self.active = nil
                self.heartbeat?.cancel()
                self.heartbeat = nil
                DispatchQueue.main.async { self.onDisconnected?() }
            }
            self.scheduleRetry()
        }
        socket.start()
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        guard sender != nil, !suspended else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, let active = self.active else { return }
            if PerformanceTrace.now() - self.lastResponse > 3 {
                active.close()
            } else {
                active.send(WirePacket(header: WireHeader(kind: .ping))) { _ in }
            }
        }
        heartbeat = timer
        timer.resume()
    }

    private func scheduleRetry() {
        guard running, !suspended, sender != nil else { return }
        retry?.cancel()
        let retry = DispatchWorkItem { [weak self] in self?.connectSavedReceiverLocked() }
        self.retry = retry
        // Retry quickly after a transient drop, then reduce radio activity during an outage.
        let delay = min(4, 0.25 * pow(2, Double(min(retryAttempt, 4))))
        retryAttempt += 1
        queue.asyncAfter(deadline: .now() + delay, execute: retry)
    }

    private func stopLocked() {
        running = false
        suspended = false
        retryAttempt = 0
        sender = nil
        receiver = nil
        retry?.cancel()
        heartbeat?.cancel()
        heartbeat = nil
        listener?.cancel()
        listener = nil
        let sockets = Array(candidates.values)
        candidates = [:]
        active = nil
        sockets.forEach { $0.close() }
    }
}

private final class FastSocket {
    let id = UUID()
    var onReady: (() -> Void)?
    var onClosed: (() -> Void)?
    var onPacket: ((WirePacket) -> Void)?
    var onReceiveProgress: (() -> Void)?
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var closed = false
    private var greeted = false
    private var lastProgress: TimeInterval = 0
    private var incomingBody = Data()
    private var incomingCount = 0

    init(connection: NWConnection, queue: DispatchQueue) { self.connection = connection; self.queue = queue }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, !self.closed else { return }
            switch state {
            case .ready: self.onReady?(); self.readHeader()
            case .failed(let error), .waiting(let error):
                PerformanceTrace.connection("socket_failed \(error)")
                self.close()
            case .cancelled: self.close()
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if let self, !self.greeted {
                PerformanceTrace.connection("handshake_deadline")
                self.close()
            }
        }
    }

    func send(_ packet: WirePacket, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !closed else { completion(.failure(FastChannelError.disconnected)); return }
        do {
            let payload = try packet.encoded()
            let count = UInt32(payload.count)
            var frame = Data()
            frame.reserveCapacity(payload.count + 4)
            frame.append(contentsOf: [UInt8((count >> 24) & 255), UInt8((count >> 16) & 255),
                                      UInt8((count >> 8) & 255), UInt8(count & 255)])
            frame.append(payload)
            connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                if let error { completion(.failure(error)); self?.close() }
                else { completion(.success(())) }
            })
        } catch { completion(.failure(error)) }
    }

    func close() {
        guard !closed else { return }
        closed = true
        connection.cancel()
        onClosed?()
    }

    private func readHeader() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, ended, error in
            guard let self, !self.closed else { return }
            guard error == nil, !ended, let data, data.count == 4 else { self.close(); return }
            let count = data.reduce(0) { ($0 << 8) | Int($1) }
            guard count > 0, count <= BridgeLimits.maxPhotoBytes + BridgeLimits.maxHeaderBytes + 4 else { self.close(); return }
            self.incomingBody = Data()
            self.incomingBody.reserveCapacity(count)
            self.incomingCount = count
            self.readBody()
        }
    }

    private func readBody() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: min(64 * 1024, incomingCount - incomingBody.count)) { [weak self] chunk, _, ended, error in
            guard let self, !self.closed else { return }
            guard error == nil, let chunk, !chunk.isEmpty else { self.close(); return }
            self.incomingBody.append(chunk)
            if self.incomingCount > 64 * 1024, PerformanceTrace.now() - self.lastProgress > 0.15 {
                self.lastProgress = PerformanceTrace.now()
                self.onReceiveProgress?()
            }
            if self.incomingBody.count == self.incomingCount {
                guard let packet = try? WirePacket.decode(self.incomingBody) else { self.close(); return }
                if packet.header.kind == .hello { self.greeted = true }
                self.onPacket?(packet)
                if ended { self.close() } else { self.readHeader() }
            } else if ended { self.close() }
            else { self.readBody() }
        }
    }
}

enum FastChannelError: LocalizedError {
    case disconnected
    var errorDescription: String? { "The direct connection is reconnecting. Your photo remains queued." }
}
