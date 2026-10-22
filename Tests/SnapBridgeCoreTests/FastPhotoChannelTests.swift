import XCTest
import Network
@testable import SnapBridgeCore

final class FastPhotoChannelTests: XCTestCase {
    func testBackgroundPauseRetainsAuthenticatedConnection() {
        let server = FastPhotoChannel(), client = FastPhotoChannel()
        defer { client.stop(); server.stop() }
        let mac = UUID(), phone = UUID()
        let token = Data(repeating: 17, count: 32).base64EncodedString()
        let record = PairingRecord(receiverID: mac, receiverName: "Mac", token: token)
        let delivered = expectation(description: "Existing connection delivers after resume")
        var connections = 0
        server.onPacket = { packet, reply in
            XCTAssertEqual(packet.header.kind, .photo)
            reply(WirePacket(header: WireHeader(kind: .received, id: packet.header.id)))
        }
        client.onReady = { _ in
            connections += 1
            XCTAssertEqual(connections, 1, "Returning to the app must reuse the live socket")
            client.pause()
            // Longer than the ordinary heartbeat deadline: suspension must not close it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.3) {
                client.resume()
                client.send(WirePacket(header: WireHeader(kind: .photo),
                                       payload: Data([0xFF, 0xD8, 0xFF, 0xE0]))) { result in
                    if case .failure(let error) = result { XCTFail(error.localizedDescription) }
                }
            }
        }
        client.onPacket = { packet, _ in
            XCTAssertEqual(packet.header.kind, .received)
            delivered.fulfill()
        }
        server.onListening = { port in
            client.connect(to: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!),
                           pairing: record, deviceID: phone, name: "iPhone")
        }
        server.startReceiver(id: mac, tokens: [phone.uuidString: token], name: "Mac")
        wait(for: [delivered], timeout: 8)
        XCTAssertEqual(connections, 1)
    }

    func testEncryptedTransferAndImmediatePhotoAfterReopening() throws {
        let server = FastPhotoChannel(), client = FastPhotoChannel()
        defer { client.stop(); server.stop() }
        let mac = UUID(), phone = UUID()
        let token = Data(repeating: 31, count: 32).base64EncodedString()
        let record = PairingRecord(receiverID: mac, receiverName: "Mac", token: token)
        var photo = Data([0xFF, 0xD8, 0xFF, 0xE0])
        photo.append(Data(repeating: 0x5A, count: 1024 * 1024))
        let delivered = expectation(description: "Both transfers acknowledged")
        delivered.expectedFulfillmentCount = 2
        var phase = 0
        var progressCount = 0
        client.onTransferProgress = { progressCount += 1 }
        server.onPacket = { packet, reply in
            XCTAssertEqual(packet.payload, photo)
            reply(WirePacket(header: WireHeader(kind: .received, id: packet.header.id)))
        }
        client.onReady = { _ in
            client.send(WirePacket(header: WireHeader(kind: .photo), payload: photo)) {
                if case .failure(let error) = $0 { XCTFail(error.localizedDescription) }
            }
        }
        client.onPacket = { packet, _ in
            XCTAssertEqual(packet.header.kind, .received)
            delivered.fulfill()
            if phase == 0 {
                phase = 1
                client.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // Same saved token, no pairing code, Bonjour endpoint rediscovered.
                    client.startSender(pairing: record, deviceID: phone, name: "iPhone")
                }
            }
        }
        server.onListening = { port in
            client.connect(to: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!),
                           pairing: record, deviceID: phone, name: "iPhone")
        }
        server.startReceiver(id: mac, tokens: [phone.uuidString: token], name: "Mac")
        wait(for: [delivered], timeout: 10)
        XCTAssertGreaterThan(progressCount, 0, "Real receive progress must keep slow, healthy transfers alive")
    }

    func testIncorrectPairingTokenCannotAuthenticate() {
        let server = FastPhotoChannel(), client = FastPhotoChannel()
        defer { client.stop(); server.stop() }
        let mac = UUID(), phone = UUID()
        let correct = Data(repeating: 1, count: 32).base64EncodedString()
        let wrong = PairingRecord(receiverID: mac, receiverName: "Mac", token: Data(repeating: 2, count: 32).base64EncodedString())
        let authenticated = expectation(description: "Wrong key never connects")
        authenticated.isInverted = true
        client.onReady = { _ in authenticated.fulfill() }
        server.onListening = { port in
            client.connect(to: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!),
                           pairing: wrong, deviceID: phone, name: "Unknown")
        }
        server.startReceiver(id: mac, tokens: [phone.uuidString: correct], name: "Mac")
        wait(for: [authenticated], timeout: 3)
    }

    func testAutomaticRecoveryWhenReceiverRestarts() {
        let server = FastPhotoChannel(), client = FastPhotoChannel()
        defer { client.stop(); server.stop() }
        let mac = UUID(), phone = UUID()
        let token = Data(repeating: 3, count: 32).base64EncodedString()
        let record = PairingRecord(receiverID: mac, receiverName: "Mac", token: token)
        let recovered = expectation(description: "Reconnects after server disappears")
        var connectedBefore = false
        client.onReady = { _ in
            if connectedBefore { recovered.fulfill() }
            else {
                connectedBefore = true
                server.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    server.startReceiver(id: mac, tokens: [phone.uuidString: token], name: "Mac")
                }
            }
        }
        server.onListening = { _ in
            if !connectedBefore { client.startSender(pairing: record, deviceID: phone, name: "iPhone") }
        }
        server.startReceiver(id: mac, tokens: [phone.uuidString: token], name: "Mac")
        wait(for: [recovered], timeout: 10)
    }
}
