import Foundation
import CoreGraphics
import CVirtualDisplay

/// CGVirtualDisplay köprüsünün Swift tarafı.
///
/// Ekran, nesne yaşadığı sürece sistemde kalır. Uygulama kapandığında
/// macOS ekranı otomatik kaldırır.
final class VirtualDisplay {
    private var handle: OpaquePointer?
    let displayID: CGDirectDisplayID
    let preset: ResolutionPreset
    let name: String

    init?(preset: ResolutionPreset, name: String = "Kodmoz Screen") {
        var displayID: UInt32 = 0
        guard let handle = KodmozVirtualDisplayCreate(
            name,
            UInt32(preset.width),
            UInt32(preset.height),
            60,
            preset.hiDPI ? 1 : 0,
            &displayID
        ), displayID != 0 else {
            return nil
        }
        self.handle = handle
        self.displayID = displayID
        self.preset = preset
        self.name = name
    }

    deinit {
        if let handle {
            KodmozVirtualDisplayDestroy(handle)
        }
    }

    var isOnline: Bool {
        CGDisplayIsOnline(displayID) != 0
    }

    /// Sistemin ekranı gerçekten çevrimiçi sayması için kısa süre bekler.
    @discardableResult
    func waitUntilOnline(timeout: TimeInterval = 3.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isOnline && CGDisplayPixelsWide(displayID) > 0 {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return isOnline
    }

    /// Gerçek framebuffer boyutu (piksel). CGDisplayPixelsWide Retina
    /// ekranlarda nokta boyutunu döndürebildiği için moddan okuyoruz.
    var pixelSize: CGSize {
        if let mode = CGDisplayCopyDisplayMode(displayID) {
            return CGSize(width: mode.pixelWidth, height: mode.pixelHeight)
        }
        return CGSize(
            width: CGDisplayPixelsWide(displayID),
            height: CGDisplayPixelsHigh(displayID)
        )
    }

    /// Ekranın nokta cinsinden boyutu ve masaüstündeki konumu.
    var bounds: CGRect {
        CGDisplayBounds(displayID)
    }

    var pointSize: CGSize {
        bounds.size
    }

    var scaleFactor: CGFloat {
        let pixels = pixelSize
        let points = pointSize
        guard points.width > 0 else { return 1 }
        return max(1, pixels.width / points.width)
    }

    var summary: String {
        "\(Int(pixelSize.width))×\(Int(pixelSize.height)) px · \(Int(pointSize.width))×\(Int(pointSize.height)) pt · @\(Int(scaleFactor))×"
    }

    /// Sistemin ürettiği mod listesinden istenen çözünürlüğü seçer.
    /// macOS 26 `hiDPI` bayrağını yok saydığı için gerçek mod seçimi burada.
    ///
    /// HiDPI modu ayrı gizli bir moddur: 1280×800 nokta / 2560×1600 piksel.
    /// `kCGDisplayShowDuplicateLowResolutionModes` olmadan listelenmez.
    @discardableResult
    func selectMode(pixelWidth: Int, pixelHeight: Int, hiDPI: Bool) -> Bool {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode]) ?? []
        guard !modes.isEmpty else { return false }

        let selected: CGDisplayMode?
        if hiDPI {
            selected = modes.first {
                $0.pixelWidth == pixelWidth
                    && $0.pixelHeight == pixelHeight
                    && $0.width == pixelWidth / 2
                    && $0.height == pixelHeight / 2
            } ?? modes.first {
                $0.pixelWidth == pixelWidth && $0.pixelHeight == pixelHeight
            }
        } else {
            selected = modes.first {
                $0.width == pixelWidth
                    && $0.height == pixelHeight
                    && $0.pixelWidth == pixelWidth
                    && $0.pixelHeight == pixelHeight
            } ?? modes.first {
                $0.width == pixelWidth && $0.height == pixelHeight
            }
        }
        guard let mode = selected else { return false }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil)
        let result = CGCompleteDisplayConfiguration(config, .permanently)
        return result == .success
    }
}
