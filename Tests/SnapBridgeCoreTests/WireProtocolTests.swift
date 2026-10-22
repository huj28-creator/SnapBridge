import XCTest
@testable import SnapBridgeCore

final class WireProtocolTests: XCTestCase {
    func testRequestingSetupDoesNotAuthorizeAConnection() throws {
        let request = PairingRequest(deviceID: UUID(), code: nil, token: nil, requestsCode: true)
        XCTAssertFalse(request.isAuthorized(pairingCode: "123456", savedToken: "saved-secret"))
        let packet = WirePacket(header: WireHeader(kind: .pairingRequested))
        let decoded = try WirePacket.decode(packet.encoded())
        XCTAssertEqual(decoded.header.kind, .pairingRequested)
        XCTAssertNil(decoded.header.pairing)
        XCTAssertTrue(decoded.payload.isEmpty)
    }

    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0xFF, 0xD9])

    func testPhotoRoundTripPreservesIdentityDateAndEveryByte() throws {
        let id = UUID(), date = Date(timeIntervalSince1970: 1_800_000_000)
        let packet = WirePacket(header: WireHeader(kind: .photo, id: id, createdAt: date), payload: jpeg)
        let decoded = try WirePacket.decode(packet.encoded())
        XCTAssertEqual(decoded.header.id, id)
        XCTAssertEqual(decoded.header.createdAt, date)
        XCTAssertEqual(decoded.payload, jpeg)
    }

    func testTruncatedAndOversizedHeadersAreRejected() {
        for data in [Data(), Data([0, 0, 0]), Data([0, 0, 0, 100]), Data([0xFF, 0xFF, 0xFF, 0xFF])] {
            XCTAssertThrowsError(try WirePacket.decode(data))
        }
    }

    func testNonJPEGPhotoAndUnexpectedControlPayloadAreRejected() throws {
        XCTAssertThrowsError(try WirePacket.decode(WirePacket(header: WireHeader(kind: .photo), payload: Data("hello".utf8)).encoded()))
        XCTAssertThrowsError(try WirePacket.decode(WirePacket(header: WireHeader(kind: .received), payload: jpeg).encoded()))
    }

    func testPhotoLimitAndFutureProtocolVersionAreRejected() throws {
        let tooLarge = Data(repeating: 0, count: BridgeLimits.maxPhotoBytes + 1)
        XCTAssertThrowsError(try WirePacket(header: WireHeader(kind: .photo), payload: tooLarge).encoded())
        var header = WireHeader(kind: .received)
        header.version = 2
        XCTAssertThrowsError(try WirePacket.decode(WirePacket(header: header).encoded()))
    }

    func testFirstPairingRequiresExactSixDigitCode() {
        let id = UUID()
        XCTAssertTrue(PairingRequest(deviceID: id, code: "004219", token: nil).isAuthorized(pairingCode: "004219", savedToken: nil))
        for code in ["004218", "4219", "", "abcdef"] {
            XCTAssertFalse(PairingRequest(deviceID: id, code: code, token: nil).isAuthorized(pairingCode: "004219", savedToken: nil))
        }
    }

    func testPermanentPairingSurvivesPairingCodeChanges() throws {
        let record = PairingRecord(receiverID: UUID(), receiverName: "My Mac", token: "saved-secret-token")
        let restored = try JSONDecoder().decode(PairingRecord.self, from: JSONEncoder().encode(record))
        let request = PairingRequest(deviceID: UUID(), code: nil, token: restored.token)
        for newCode in ["000000", "999999", "123456"] {
            XCTAssertTrue(request.isAuthorized(pairingCode: newCode, savedToken: record.token))
        }
        XCTAssertFalse(request.isAuthorized(pairingCode: "123456", savedToken: nil), "Forgetting the phone must revoke its token")
        XCTAssertFalse(request.isAuthorized(pairingCode: "123456", savedToken: "another-secret"))
    }

    func testAmbiguousAndEmptyCredentialsAreRejected() {
        let id = UUID()
        XCTAssertFalse(PairingRequest(deviceID: id, code: "123456", token: "secret").isAuthorized(pairingCode: "123456", savedToken: "secret"))
        XCTAssertFalse(PairingRequest(deviceID: id, code: nil, token: "").isAuthorized(pairingCode: "123456", savedToken: ""))
        XCTAssertFalse(PairingRequest(deviceID: id, code: nil, token: nil).isAuthorized(pairingCode: "123456", savedToken: nil))
    }

    func testWelcomeAndReceiptRoundTrip() throws {
        let record = PairingRecord(receiverID: UUID(), receiverName: "Mac", token: "secret")
        let welcome = try WirePacket.decode(WirePacket(header: WireHeader(kind: .paired, pairing: record)).encoded())
        XCTAssertEqual(welcome.header.pairing?.receiverID, record.receiverID)
        let id = UUID()
        let receipt = try WirePacket.decode(WirePacket(header: WireHeader(kind: .received, id: id)).encoded())
        XCTAssertEqual(receipt.header.id, id)
        XCTAssertTrue(receipt.payload.isEmpty)
    }
}
