import Foundation
import CoreGraphics
import CoreMedia
import CoreVideo
import IOSurface
import ScreenCaptureKit

/// Sanal ekranı yakalar. Önce ScreenCaptureKit dener; sanal ekranlarda
/// kare gelmezse (veya SCK hata verirse) CGDisplayStream'e düşer.
final class ScreenCaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    enum Backend: String {
        case screenCaptureKit = "ScreenCaptureKit"
        case displayStream = "CGDisplayStream"
        case testPattern = "Test deseni"
    }

    var onFrame: ((_ pixelBuffer: CVPixelBuffer, _ presentationTime: CMTime, _ keyframeHint: Bool) -> Void)?
    var onError: ((String) -> Void)?
    var onBackendChange: ((Backend) -> Void)?

    private(set) var backend: Backend = .screenCaptureKit
    private let queue = DispatchQueue(label: "com.kodmoz.screen.capture", qos: .userInteractive)
    private let callbackQueue = DispatchQueue(label: "com.kodmoz.screen.capture.callback", qos: .userInteractive)

    private var stream: SCStream?
    private var displayStream: CGDisplayStream?
    private var shareableDisplay: SCDisplay?
    private let stillLock = NSLock()
    private var stillPending = false
    private var lastStillAt = Date.distantPast
    private var fallbackWorkItem: DispatchWorkItem?
    private var framesDelivered = 0
    private var isRunning = false
    private var config = Configuration()
    private var stopping = false

    private struct Configuration {
        var displayID: CGDirectDisplayID = 0
        var width: Int = 0
        var height: Int = 0
        var fps: Int = 60
        var showCursor: Bool = true
    }

    func start(displayID: CGDirectDisplayID, width: Int, height: Int, fps: Int, showCursor: Bool) {
        stop()
        config = Configuration(displayID: displayID, width: width, height: height, fps: fps, showCursor: showCursor)
        isRunning = true
        stopping = false
        framesDelivered = 0
        startScreenCaptureKit()
    }

    /// Hareketsiz masaüstünde SCK yeni kare üretmez. İstemci bağlandığında
    /// tek karelik bir ekran görüntüsü alıp IDR olarak gönderiyoruz; böylece
    /// el sıkışma anahtar kare beklemeden tamamlanır.
    func requestStillFrame() {
        guard isRunning else { return }
        stillLock.lock()
        let now = Date()
        if stillPending || now.timeIntervalSince(lastStillAt) < 0.45 {
            stillLock.unlock()
            return
        }
        stillPending = true
        lastStillAt = now
        stillLock.unlock()

        if #available(macOS 14.0, *), let display = shareableDisplay {
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = config.width
            configuration.height = config.height
            configuration.showsCursor = config.showCursor
            Task { [weak self] in
                guard let self else { return }
                defer {
                    self.stillLock.lock()
                    self.stillPending = false
                    self.stillLock.unlock()
                }
                if let image = try? await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                ) {
                    self.emitStill(image)
                } else {
                    self.emitStillFromDisplay()
                }
            }
        } else {
            stillLock.lock()
            stillPending = false
            stillLock.unlock()
            emitStillFromDisplay()
        }
    }

    private func emitStillFromDisplay() {
        guard let image = CGDisplayCreateImage(config.displayID) else { return }
        emitStill(image)
    }

    private func emitStill(_ image: CGImage) {
        let width = config.width
        let height = config.height
        guard width > 0, height > 0 else { return }

        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else { return }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        deliver(pixelBuffer, time: CMClockGetTime(CMClockGetHostTimeClock()))
    }

    func stop() {
        isRunning = false
        stopping = true
        fallbackWorkItem?.cancel()
        fallbackWorkItem = nil

        if let stream {
            self.stream = nil
            Task { try? await stream.stopCapture() }
        }
        if let displayStream {
            displayStream.stop()
            self.displayStream = nil
        }
        backend = .screenCaptureKit
    }

    // MARK: - ScreenCaptureKit

    private func startScreenCaptureKit() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: false
                )
                guard let display = content.displays.first(where: { $0.displayID == self.config.displayID }) else {
                    throw CaptureError.displayNotFound
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.width = self.config.width
                configuration.height = self.config.height
                configuration.minimumFrameInterval = CMTime(
                    value: 1,
                    timescale: CMTimeScale(max(1, self.config.fps))
                )
                configuration.pixelFormat = kCVPixelFormatType_32BGRA
                configuration.queueDepth = 6
                configuration.showsCursor = self.config.showCursor
                configuration.capturesAudio = false
                if #available(macOS 14.0, *) {
                    configuration.scalesToFit = false
                }

                let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.queue)
                try await stream.startCapture()

                guard self.isRunning else {
                    try? await stream.stopCapture()
                    return
                }
                self.stream = stream
                self.shareableDisplay = display
                self.backend = .screenCaptureKit
                self.callbackQueue.async { self.onBackendChange?(.screenCaptureKit) }
                self.scheduleScreenCaptureKitFallback()
            } catch {
                NSLog("[KodmozScreen] ScreenCaptureKit hatası: %@", String(describing: error))
                self.callbackQueue.async {
                    self.onError?("ScreenCaptureKit başlatılamadı: \(error.localizedDescription)")
                }
                self.switchToDisplayStreamIfPossible()
            }
        }
    }

    private func scheduleScreenCaptureKitFallback() {
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning, self.framesDelivered == 0 else { return }
            NSLog("[KodmozScreen] SCK 3 saniyede kare vermedi; CGDisplayStream'e geçiliyor")
            self.switchToDisplayStreamIfPossible()
        }
        fallbackWorkItem = item
        queue.asyncAfter(deadline: .now() + 3, execute: item)
    }

    private func switchToDisplayStreamIfPossible() {
        guard isRunning else { return }
        if let stream {
            self.stream = nil
            Task { try? await stream.stopCapture() }
        }
        startDisplayStream()
    }

    // MARK: - CGDisplayStream

    private func startDisplayStream() {
        guard isRunning, displayStream == nil else { return }
        let properties = [CGDisplayStream.showCursor: config.showCursor] as CFDictionary
        let handler: CGDisplayStreamFrameAvailableHandler = { [weak self] status, _, surface, _ in
            guard let self else { return }
            switch status {
            case .frameComplete, .frameBlank:
                guard let surface else { return }
                self.handleIOSurface(surface)
            case .stopped:
                if self.isRunning && !self.stopping {
                    self.callbackQueue.async {
                        self.onError?("Ekran akışı durdu. Ekran kaydı iznini kontrol edin.")
                    }
                }
            default:
                break
            }
        }
        guard let stream = CGDisplayStream(
            dispatchQueueDisplay: config.displayID,
            outputWidth: config.width,
            outputHeight: config.height,
            pixelFormat: Int32(kCVPixelFormatType_32BGRA),
            properties: properties,
            queue: queue,
            handler: handler
        ) else {
            callbackQueue.async {
                self.onError?("CGDisplayStream oluşturulamadı. Ekran kaydı izni gerekli olabilir.")
            }
            return
        }

        self.displayStream = stream
        backend = .displayStream
        callbackQueue.async { self.onBackendChange?(.displayStream) }
        stream.start()
    }

    private func handleIOSurface(_ surface: IOSurface) {
        var unmanaged: Unmanaged<CVPixelBuffer>?
        let attributes = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA] as CFDictionary
        let status = CVPixelBufferCreateWithIOSurface(
            kCFAllocatorDefault,
            surface,
            attributes,
            &unmanaged
        )
        guard status == kCVReturnSuccess, let pixelBuffer = unmanaged?.takeRetainedValue() else { return }
        deliver(pixelBuffer, time: CMClockGetTime(CMClockGetHostTimeClock()))
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        deliver(pixelBuffer, time: time)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard isRunning, !stopping else { return }
        callbackQueue.async {
            self.onError?("Ekran akışı durdu: \(error.localizedDescription)")
        }
    }

    private func deliver(_ pixelBuffer: CVPixelBuffer, time: CMTime) {
        framesDelivered += 1
        guard isRunning else { return }
        callbackQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.onFrame?(pixelBuffer, time, true)
        }
    }
}

enum CaptureError: LocalizedError {
    case displayNotFound

    var errorDescription: String? {
        switch self {
        case .displayNotFound:
            return "Sanal ekran yakalama listesinde bulunamadı."
        }
    }
}
