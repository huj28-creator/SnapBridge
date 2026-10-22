import Foundation

enum BridgeLimits {
    static let serviceType = "snapbridge-v1"
    static let maxPhotoBytes = 16 * 1024 * 1024
    static let maxHeaderBytes = 8 * 1024
    static let maxPendingPhotos = 10
}

struct PairingRequest: Codable {
    let deviceID: UUID
    let code: String?
    let token: String?
    var requestsCode: Bool? = nil

    func isAuthorized(pairingCode: String, savedToken: String?) -> Bool {
        if let token, code == nil, let savedToken {
            return !token.isEmpty && Self.constantTimeEqual(token, savedToken)
        }
        if let code, token == nil {
            return code.count == 6 && code.allSatisfy(\.isNumber)
                && Self.constantTimeEqual(code, pairingCode)
        }
        return false
    }

    static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

struct PairingRecord: Codable {
    let receiverID: UUID
    let receiverName: String
    let token: String
}

enum WireKind: String, Codable {
    case photo, paired, received, rejected, hello, ping, pong, pairingRequested
}

struct WireHeader: Codable {
    var version = 1
    let kind: WireKind
    var id = UUID()
    var createdAt: Date?
    var pairing: PairingRecord?
    var message: String?
}

struct WirePacket {
    let header: WireHeader
    var payload = Data()

    func encoded() throws -> Data {
        guard payload.count <= BridgeLimits.maxPhotoBytes else { throw WireError.tooLarge }
        let json = try JSONEncoder().encode(header)
        guard json.count <= BridgeLimits.maxHeaderBytes else { throw WireError.invalidHeader }
        let length = UInt32(json.count)
        var result = Data()
        result.reserveCapacity(4 + json.count + payload.count)
        result.append(contentsOf: [
            UInt8((length >> 24) & 255), UInt8((length >> 16) & 255),
            UInt8((length >> 8) & 255), UInt8(length & 255)
        ])
        result.append(json)
        result.append(payload)
        return result
    }

    static func decode(_ data: Data) throws -> WirePacket {
        guard data.count >= 4 else { throw WireError.truncated }
        guard data.count <= BridgeLimits.maxPhotoBytes + BridgeLimits.maxHeaderBytes + 4
        else { throw WireError.tooLarge }
        let bytes = Array(data.prefix(4))
        let length = bytes.reduce(0) { ($0 << 8) | Int($1) }
        guard length > 0, length <= BridgeLimits.maxHeaderBytes else { throw WireError.invalidHeader }
        guard data.count >= 4 + length else { throw WireError.truncated }
        let header = try JSONDecoder().decode(WireHeader.self, from: data.subdata(in: 4..<(4 + length)))
        guard header.version == 1 else { throw WireError.unsupportedVersion }
        let payload = data.suffix(from: 4 + length)
        guard payload.count <= BridgeLimits.maxPhotoBytes else { throw WireError.tooLarge }
        if header.kind == .photo {
            guard payload.count >= 4, payload.starts(with: [0xFF, 0xD8, 0xFF])
            else { throw WireError.invalidPhoto }
        } else if !payload.isEmpty {
            throw WireError.invalidHeader
        }
        return WirePacket(header: header, payload: payload)
    }
}

enum WireError: LocalizedError {
    case truncated, tooLarge, invalidHeader, invalidPhoto, unsupportedVersion
    var errorDescription: String? {
        switch self {
        case .truncated: return "The transfer was incomplete. Please try again."
        case .tooLarge: return "The photo exceeds the 16 MB transfer limit."
        case .invalidHeader: return "The transfer could not be understood."
        case .invalidPhoto: return "The transfer did not contain a JPEG photo."
        case .unsupportedVersion: return "Update SnapBridge on both devices."
        }
    }
}
