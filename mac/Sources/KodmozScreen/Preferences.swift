import Foundation

/// Mac tarafında sunulan sanal ekran çözünürlükleri.
/// Değerler gerçek piksel boyutlarıdır; HiDPI seçeneklerinde arayüz
/// piksellerin yarısı kadar nokta kullanır (Retina görünümü).
enum ResolutionPreset: String, CaseIterable, Identifiable {
    case sharp2560
    case sharp1920
    case sharp2960
    case sharp1080
    case pixel2560
    case pixel1920
    case pixel1280

    var id: String { rawValue }

    var width: Int {
        switch self {
        case .sharp2560, .pixel2560: return 2560
        case .sharp1920, .pixel1920: return 1920
        case .sharp2960: return 2960
        case .sharp1080: return 1920
        case .pixel1280: return 1280
        }
    }

    var height: Int {
        switch self {
        case .sharp2560, .pixel2560: return 1600
        case .sharp1920, .pixel1920: return 1200
        case .sharp2960: return 1848
        case .sharp1080: return 1080
        case .pixel1280: return 800
        }
    }

    var hiDPI: Bool {
        switch self {
        case .sharp2560, .sharp1920, .sharp2960, .sharp1080: return true
        case .pixel2560, .pixel1920, .pixel1280: return false
        }
    }

    var title: String {
        "\(width) × \(height)"
    }

    var detail: String {
        if hiDPI {
            return "\(width / 2) × \(height / 2) nokta · Retina"
        }
        return "\(width) × \(height) nokta · 1×"
    }

    /// Önerilen varsayılan: çoğu Samsung tablet 16:10 ve 2560×1600.
    static let `default`: ResolutionPreset = .sharp2560
}

final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard
    private let codeKey = "pairingCode"

    init() {
        defaults.register(defaults: [
            "port": 9280,
            "resolution": ResolutionPreset.default.rawValue,
            "fps": 60,
            "bitrateMbps": 20,
            "showCursor": true,
            "inputEnabled": true,
            "naturalScroll": true,
            "requireCode": true,
            "serverEnabled": true,
            "mirrorMode": false,
            "didShowWelcome": false,
        ])
    }

    var port: Int {
        get {
            if let raw = ProcessInfo.processInfo.environment["KODMOZ_SCREEN_PORT"],
               let value = Int(raw), (1024...65535).contains(value) {
                return value
            }
            let value = defaults.integer(forKey: "port")
            return (1024...65535).contains(value) ? value : 9280
        }
        set { defaults.set(newValue, forKey: "port") }
    }

    var resolution: ResolutionPreset {
        get {
            if let raw = ProcessInfo.processInfo.environment["KODMOZ_SCREEN_PRESET"],
               let preset = ResolutionPreset(rawValue: raw) {
                return preset
            }
            return ResolutionPreset(rawValue: defaults.string(forKey: "resolution") ?? "") ?? .default
        }
        set { defaults.set(newValue.rawValue, forKey: "resolution") }
    }

    var fps: Int {
        get {
            let value = defaults.integer(forKey: "fps")
            return [30, 60].contains(value) ? value : 60
        }
        set { defaults.set(newValue, forKey: "fps") }
    }

    /// 0 = otomatik (çözünürlüğe göre 10–30 Mbps arası).
    var bitrateMbps: Int {
        get {
            let value = defaults.integer(forKey: "bitrateMbps")
            return [0, 8, 12, 20, 30, 40].contains(value) ? value : 20
        }
        set { defaults.set(newValue, forKey: "bitrateMbps") }
    }

    var showCursor: Bool {
        get { defaults.bool(forKey: "showCursor") }
        set { defaults.set(newValue, forKey: "showCursor") }
    }

    var inputEnabled: Bool {
        get { defaults.bool(forKey: "inputEnabled") }
        set { defaults.set(newValue, forKey: "inputEnabled") }
    }

    var naturalScroll: Bool {
        get { defaults.bool(forKey: "naturalScroll") }
        set { defaults.set(newValue, forKey: "naturalScroll") }
    }

    var requireCode: Bool {
        get { defaults.bool(forKey: "requireCode") }
        set { defaults.set(newValue, forKey: "requireCode") }
    }

    var serverEnabled: Bool {
        get { defaults.bool(forKey: "serverEnabled") }
        set { defaults.set(newValue, forKey: "serverEnabled") }
    }

    var mirrorMode: Bool {
        get { defaults.bool(forKey: "mirrorMode") }
        set { defaults.set(newValue, forKey: "mirrorMode") }
    }

    var didShowWelcome: Bool {
        get { defaults.bool(forKey: "didShowWelcome") }
        set { defaults.set(newValue, forKey: "didShowWelcome") }
    }

    /// Eşleşme kodu ilk çalıştırmada üretilir ve kullanıcı yenileyene kadar kalır.
    var pairingCode: String {
        if let override = ProcessInfo.processInfo.environment["KODMOZ_SCREEN_CODE"],
           override.count == 4 {
            return override
        }
        if let existing = defaults.string(forKey: codeKey), existing.count == 4 {
            return existing
        }
        let fresh = Self.randomCode()
        defaults.set(fresh, forKey: codeKey)
        return fresh
    }

    func regeneratePairingCode() -> String {
        let fresh = Self.randomCode()
        defaults.set(fresh, forKey: codeKey)
        return fresh
    }

    private static func randomCode() -> String {
        String(format: "%04d", Int.random(in: 0...9999))
    }

    var resolvedBitrate: Int {
        if bitrateMbps > 0 { return bitrateMbps * 1_000_000 }
        // Otomatik: piksel sayısına göre makul bir hedef.
        let pixels = resolution.width * resolution.height
        if pixels >= 4_000_000 { return 24_000_000 }
        if pixels >= 2_000_000 { return 16_000_000 }
        return 10_000_000
    }
}
