import Foundation
import CoreVideo
import CoreMedia
import CoreText
import AppKit

/// Ekran kaydı izni olmadan uçtan uca hattı test etmek için hareketli
/// bir desen üretir. `--test-pattern` ile kullanılır.
final class TestPatternSource {
    var onFrame: ((_ pixelBuffer: CVPixelBuffer, _ presentationTime: CMTime) -> Void)?

    private let queue = DispatchQueue(label: "com.kodmoz.screen.testpattern", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var pool: CVPixelBufferPool?
    private var width = 1280
    private var height = 800
    private var fps = 60
    private var frameIndex = 0
    private var running = false

    func start(width: Int, height: Int, fps: Int) {
        stop()
        self.width = width
        self.height = height
        self.fps = max(1, fps)
        frameIndex = 0
        running = true
        createPoolIfNeeded()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        let interval = DispatchTimeInterval.nanoseconds(Int(1_000_000_000 / Double(self.fps)))
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            self?.emitFrame()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        running = false
        timer?.cancel()
        timer = nil
        pool = nil
    }

    private func createPoolIfNeeded() {
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferPoolMinimumBufferCountKey: 4,
        ]
        var newPool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            nil,
            attributes as CFDictionary,
            &newPool
        )
        if status == kCVReturnSuccess {
            pool = newPool
        }
    }

    private func emitFrame() {
        guard running, let pool else { return }
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        draw(into: pixelBuffer)
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        frameIndex += 1
        onFrame?(pixelBuffer, CMClockGetTime(CMClockGetHostTimeClock()))
    }

    private func draw(into pixelBuffer: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return }

        let w = CGFloat(width)
        let h = CGFloat(height)
        let t = Double(frameIndex) / Double(max(1, fps))

        // Arka plan: koyu lacivert → mor degrade.
        let colors = [
            NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.16, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.13, green: 0.07, blue: 0.24, alpha: 1).cgColor,
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: h),
                end: CGPoint(x: w, y: 0),
                options: []
            )
        }

        // Hareketli dikey çubuk.
        let barX = CGFloat((t.truncatingRemainder(dividingBy: 4)) / 4) * w
        context.setFillColor(NSColor(calibratedRed: 0.32, green: 0.62, blue: 1, alpha: 0.35).cgColor)
        context.fill(CGRect(x: barX - 3, y: 0, width: 6, height: h))

        // Renk çubukları (alt şerit).
        let bars: [NSColor] = [.white, .yellow, .cyan, .green, .magenta, .red, .blue]
        let barWidth = w / CGFloat(bars.count)
        for (index, color) in bars.enumerated() {
            context.setFillColor(color.withAlphaComponent(0.9).cgColor)
            context.fill(CGRect(
                x: CGFloat(index) * barWidth,
                y: 0,
                width: barWidth - 6,
                height: h * 0.07
            ))
        }

        // Köşe işaretleri.
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(6)
        let inset: CGFloat = 36
        let arm: CGFloat = 60
        for corner in 0..<4 {
            let x = (corner % 2 == 0) ? inset : w - inset
            let y = (corner < 2) ? h - inset : inset
            let dx: CGFloat = (corner % 2 == 0) ? arm : -arm
            let dy: CGFloat = (corner < 2) ? -arm : arm
            context.move(to: CGPoint(x: x, y: y))
            context.addLine(to: CGPoint(x: x + dx, y: y))
            context.move(to: CGPoint(x: x, y: y))
            context.addLine(to: CGPoint(x: x, y: y + dy))
        }
        context.strokePath()

        // Metin katmanı.
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let titleFont = NSFont.monospacedSystemFont(ofSize: max(28, w / 38), weight: .bold)
        let infoFont = NSFont.monospacedSystemFont(ofSize: max(16, w / 80), weight: .regular)

        drawText(
            "KODMOZ SCREEN",
            at: CGPoint(x: w / 2, y: h * 0.60),
            font: titleFont,
            color: .white,
            alignment: .center,
            in: context
        )
        drawText(
            "\(width) × \(height) · \(fps) fps · kare \(frameIndex)",
            at: CGPoint(x: w / 2, y: h * 0.52),
            font: infoFont,
            color: NSColor.white.withAlphaComponent(0.75),
            alignment: .center,
            in: context
        )

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        drawText(
            formatter.string(from: Date()),
            at: CGPoint(x: w / 2, y: h * 0.45),
            font: infoFont,
            color: NSColor(calibratedRed: 0.5, green: 0.85, blue: 1, alpha: 0.9),
            alignment: .center,
            in: context
        )

        drawText(
            "Test deseni · Mac ekranı değil",
            at: CGPoint(x: w / 2, y: h * 0.16),
            font: infoFont,
            color: NSColor.white.withAlphaComponent(0.5),
            alignment: .center,
            in: context
        )
    }

    private func drawText(
        _ text: String,
        at point: CGPoint,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment,
        in context: CGContext
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        context.textPosition = CGPoint(x: point.x - bounds.width / 2, y: point.y)
        CTLineDraw(line, context)
    }
}
