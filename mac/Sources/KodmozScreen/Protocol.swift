import Foundation

/// Tel üzerindeki ikili protokol. Android tarafındaki `Protocol.kt` ile
/// birebir aynı olmak zorunda; ayrıntılar docs/PROTOCOL.md'de.
enum WireProtocol {
    /// 8 bayt sihirli sayı.
    static let magic: [UInt8] = Array("KODMOZSC".utf8)
    static let version: UInt8 = 1
    static let handshakeHeaderSize = 16
    static let maxHandshakeJSON = 64 * 1024
    static let maxPayload = 8 * 1024 * 1024

    enum MessageType: UInt8 {
        case video = 1
        case input = 2
        case ping = 3
        case pong = 4
        case stats = 5
        case errorMessage = 6
        case bye = 7
    }

    enum Flags {
        static let keyframe: UInt8 = 1
        /// Video yükünün başında SPS/PPS NAL'ları var.
        static let config: UInt8 = 2
    }

    enum InputKind: UInt8 {
        case move = 0
        case button = 1
        case scroll = 2
        case key = 3
        case text = 4
    }

    struct Hello: Codable {
        var `protocol`: Int
        var device: String
        var code: String?
        var width: Int?
        var height: Int?
        var fps: Int?
    }

    struct ServerHello: Codable {
        var `protocol`: Int
        var ok: Bool
        var width: Int
        var height: Int
        var fps: Int
        var bitrate: Int
        var codec: String
        /// Annex-B başlangıç koduyla birlikte, base64.
        var sps: String
        var pps: String
        var display: String
        var scale: Int
        var server: String
    }

    struct Stats: Codable {
        var fps: Double
        var mbps: Double
        var width: Int
        var height: Int
    }

    struct ServerError: Codable {
        var message: String
        var code: String
    }
}

enum InputEvent {
    /// x/y 0…1 aralığında normalize edilmiş ekran koordinatları.
    case move(x: Double, y: Double)
    case button(x: Double, y: Double, button: Int, down: Bool, clickCount: Int)
    case scroll(dx: Int, dy: Int)
    /// Android KeyEvent anahtar kodu.
    case key(code: Int, down: Bool, meta: Int)
    case text(String)
}

extension Data {
    mutating func appendBE(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    mutating func appendBE(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    func beUInt16(at index: Int) -> UInt16 {
        UInt16(self[index]) << 8 | UInt16(self[index + 1])
    }

    func beUInt32(at index: Int) -> UInt32 {
        UInt32(self[index]) << 24
            | UInt32(self[index + 1]) << 16
            | UInt32(self[index + 2]) << 8
            | UInt32(self[index + 3])
    }
}

func makeHandshakeFrame(json: Data) -> Data {
    var data = Data(capacity: WireProtocol.handshakeHeaderSize + json.count)
    data.append(contentsOf: WireProtocol.magic)
    data.append(WireProtocol.version)
    data.append(0)
    data.append(0)
    data.append(0)
    data.appendBE(UInt32(json.count))
    data.append(json)
    return data
}

func makeMessage(type: WireProtocol.MessageType, flags: UInt8 = 0, payload: Data = Data()) -> Data {
    var data = Data(capacity: 8 + payload.count)
    data.append(type.rawValue)
    data.append(flags)
    data.append(0)
    data.append(0)
    data.appendBE(UInt32(payload.count))
    data.append(payload)
    return data
}

func makeServerError(message: String, code: String) -> Data {
    let payload = (try? JSONEncoder().encode(WireProtocol.ServerError(message: message, code: code)))
        ?? Data("{\"message\":\"Hata\",\"code\":\"error\"}".utf8)
    return makeMessage(type: .errorMessage, payload: payload)
}
