import Foundation
import AppKit

/// Uygulama ikonunu kodla üretir. `--make-icon <dizin>` ile çağrılır;
/// build.sh iconset'i iconutil ile .icns'e çevirir.
enum IconRenderer {
    @discardableResult
    static func renderIconSet(to directory: URL) -> Bool {
        let iconset = directory.appendingPathComponent("AppIcon.iconset")
        do {
            try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        } catch {
            print("Ikon dizini oluşturulamadı: \(error)")
            return false
        }

        let entries: [(String, Int)] = [
            ("icon_16x16", 16),
            ("icon_16x16@2x", 32),
            ("icon_32x32", 32),
            ("icon_32x32@2x", 64),
            ("icon_128x128", 128),
            ("icon_128x128@2x", 256),
            ("icon_256x256", 256),
            ("icon_256x256@2x", 512),
            ("icon_512x512", 512),
            ("icon_512x512@2x", 1024),
        ]

        for (name, size) in entries {
            guard let data = pngData(size: size) else {
                print("Ikon üretilemedi: \(name)")
                return false
            }
            do {
                try data.write(to: iconset.appendingPathComponent("\(name).png"))
            } catch {
                print("Ikon yazılamadı: \(error)")
                return false
            }
        }
        print("Ikon seti: \(iconset.path)")
        return true
    }

    static func pngData(size: Int) -> Data? {
        guard size > 0 else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let s = CGFloat(size)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high

        // Yuvarlatılmış kare arka plan.
        let inset = s * 0.055
        let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        let radius = rect.width * 0.225
        let backgroundPath = CGPath(
            roundedRect: rect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )

        context.saveGState()
        context.addPath(backgroundPath)
        context.clip()

        let colors = [
            CGColor(red: 0.18, green: 0.15, blue: 0.52, alpha: 1),
            CGColor(red: 0.48, green: 0.26, blue: 0.84, alpha: 1),
            CGColor(red: 0.12, green: 0.10, blue: 0.28, alpha: 1),
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 0.55, 1]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: s * 0.12, y: s * 0.96),
                end: CGPoint(x: s * 0.88, y: s * 0.04),
                options: []
            )
        }

        context.setFillColor(CGColor(red: 0.40, green: 0.55, blue: 1, alpha: 0.28))
        context.fillEllipse(in: CGRect(x: s * 0.40, y: s * 0.38, width: s * 0.78, height: s * 0.78))
        context.restoreGState()

        let stroke = max(1, s * 0.02)
        context.setLineWidth(stroke)
        context.setLineJoin(.round)

        // Arka ekran.
        let back = CGRect(x: s * 0.20, y: s * 0.42, width: s * 0.48, height: s * 0.32)
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.42))
        context.addPath(CGPath(
            roundedRect: back,
            cornerWidth: s * 0.035,
            cornerHeight: s * 0.035,
            transform: nil
        ))
        context.strokePath()

        // Ön ekran.
        let front = CGRect(x: s * 0.32, y: s * 0.25, width: s * 0.50, height: s * 0.37)
        let frontPath = CGPath(
            roundedRect: front,
            cornerWidth: s * 0.045,
            cornerHeight: s * 0.045,
            transform: nil
        )
        context.setFillColor(CGColor(red: 0.06, green: 0.08, blue: 0.19, alpha: 1))
        context.addPath(frontPath)
        context.fillPath()
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
        context.addPath(frontPath)
        context.strokePath()

        // Ayak.
        context.setLineWidth(stroke * 1.25)
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.8))
        context.move(to: CGPoint(x: s * 0.57, y: s * 0.25))
        context.addLine(to: CGPoint(x: s * 0.52, y: s * 0.18))
        context.move(to: CGPoint(x: s * 0.57, y: s * 0.25))
        context.addLine(to: CGPoint(x: s * 0.62, y: s * 0.18))
        context.strokePath()

        // Ekranda nabız gibi duran nokta.
        context.setFillColor(CGColor(red: 0.33, green: 0.86, blue: 0.95, alpha: 1))
        context.fillEllipse(in: CGRect(
            x: s * 0.535,
            y: s * 0.39,
            width: s * 0.075,
            height: s * 0.075
        ))

        // Küçük sinyal yayları.
        if size >= 64 {
            context.setStrokeColor(CGColor(red: 0.55, green: 0.9, blue: 1, alpha: 0.75))
            context.setLineWidth(stroke * 0.9)
            for index in 0..<2 {
                let offset = CGFloat(index) * s * 0.045
                context.addArc(
                    center: CGPoint(x: s * 0.57, y: s * 0.43),
                    radius: s * 0.12 + offset,
                    startAngle: -.pi * 0.15,
                    endAngle: .pi * 0.35,
                    clockwise: false
                )
                context.strokePath()
            }
        }

        guard let image = context.makeImage() else { return nil }
        let representation = NSBitmapImageRep(cgImage: image)
        representation.size = NSSize(width: size, height: size)
        return representation.representation(using: .png, properties: [:])
    }
}
