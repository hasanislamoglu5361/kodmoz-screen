import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

/// VideoToolbox ile donanım hızlandırmalı H.264 kodlayıcı.
///
/// Çıktı Annex-B biçimindedir (4 baytlık başlangıç kodları). Anahtar
/// karelerin başında SPS/PPS NAL'ları eklenir; Android'in MediaCodec
/// çözücüsü hem csd-0/csd-1 hem de bant içi parametreleri bu biçimde alır.
final class H264Encoder {
    struct Configuration {
        var width: Int
        var height: Int
        var fps: Int
        var bitrate: Int
    }

    var onFrame: ((_ payload: Data, _ keyframe: Bool, _ sps: Data?, _ pps: Data?) -> Void)?
    var onError: ((String) -> Void)?

    private var session: VTCompressionSession?
    private let configuration: Configuration
    private let callbackQueue = DispatchQueue(label: "com.kodmoz.screen.encoder.callback")
    private let lock = NSLock()
    private var framesInFlight = 0
    private var needsKeyframe = true
    private var lastFormat: CMFormatDescription?
    private var lastSPS: Data?
    private var lastPPS: Data?
    private var isInvalid = false
    private(set) var encodedFrames = 0

    init(configuration: Configuration) {
        self.configuration = configuration
        createSession()
    }

    deinit {
        invalidate()
    }

    var size: CGSize {
        CGSize(width: configuration.width, height: configuration.height)
    }

    var parameterSets: (sps: Data, pps: Data)? {
        guard let lastSPS, let lastPPS else { return nil }
        return (lastSPS, lastPPS)
    }

    func forceKeyframe() {
        lock.lock()
        needsKeyframe = true
        lock.unlock()
    }

    func updateBitrate(_ bitrate: Int) {
        guard let session else { return }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: NSNumber(value: bitrate))
        let bytesPerSecond = max(1, bitrate / 8)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits,
                             value: [NSNumber(value: bytesPerSecond), NSNumber(value: 1)] as CFArray)
    }

    /// Kareyi kodlar. Kodlayıcı meşgulse (3'ten fazla kare kuyrukta) `false`.
    @discardableResult
    func encode(pixelBuffer: CVPixelBuffer, presentationTime: CMTime, forceKeyframe: Bool = false) -> Bool {
        guard let session, !isInvalid else { return false }

        lock.lock()
        if !forceKeyframe && framesInFlight >= 3 {
            lock.unlock()
            return false
        }
        let shouldForce = forceKeyframe || needsKeyframe
        if shouldForce { needsKeyframe = false }
        framesInFlight += 1
        lock.unlock()

        var properties: CFDictionary?
        if shouldForce {
            properties = [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
        }

        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: .invalid,
            frameProperties: properties,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )

        if status != noErr {
            lock.lock()
            framesInFlight = max(0, framesInFlight - 1)
            lock.unlock()
            if status == kVTVideoEncoderMalfunctionErr {
                onError?("Video kodlayıcı arızalandı. Akış yeniden başlatılmalı.")
            }
            return false
        }
        return true
    }

    func invalidate() {
        guard !isInvalid else { return }
        isInvalid = true
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
        session = nil
    }

    // MARK: - Oturum

    private func createSession() {
        let width = Int32(configuration.width)
        let height = Int32(configuration.height)

        var session: VTCompressionSession?
        var status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true,
                kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: false,
            ] as CFDictionary,
            imageBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: configuration.width,
                kCVPixelBufferHeightKey: configuration.height,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
                kCVPixelBufferMetalCompatibilityKey: true,
            ] as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: Self.outputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )

        if status != noErr || session == nil {
            // Donanım yolu yoksa yazılım kodlayıcıya düş.
            status = VTCompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                width: width,
                height: height,
                codecType: kCMVideoCodecType_H264,
                encoderSpecification: nil,
                imageBufferAttributes: nil,
                compressedDataAllocator: nil,
                outputCallback: Self.outputCallback,
                refcon: Unmanaged.passUnretained(self).toOpaque(),
                compressionSessionOut: &session
            )
        }

        guard status == noErr, let session else {
            onError?("H.264 kodlayıcı oluşturulamadı (hata \(status)).")
            return
        }
        self.session = session

        setProperty(kVTCompressionPropertyKey_RealTime, true)
        setProperty(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Main_AutoLevel)
        setProperty(kVTCompressionPropertyKey_AllowFrameReordering, false)
        setProperty(kVTCompressionPropertyKey_H264EntropyMode, kVTH264EntropyMode_CAVLC)
        setProperty(kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, true)
        setProperty(kVTCompressionPropertyKey_ExpectedFrameRate, configuration.fps)
        setProperty(kVTCompressionPropertyKey_MaxKeyFrameInterval, configuration.fps * 2)
        setProperty(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, 2.0)
        setProperty(kVTCompressionPropertyKey_AverageBitRate, configuration.bitrate)
        setProperty(kVTCompressionPropertyKey_DataRateLimits,
                    [NSNumber(value: max(1, configuration.bitrate / 8)), NSNumber(value: 1)] as CFArray)
        setProperty(kVTCompressionPropertyKey_ColorPrimaries, kCVImageBufferColorPrimaries_ITU_R_709_2)
        setProperty(kVTCompressionPropertyKey_TransferFunction, kCVImageBufferTransferFunction_ITU_R_709_2)
        setProperty(kVTCompressionPropertyKey_YCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2)
        setProperty(kVTCompressionPropertyKey_Quality, 0.65)

        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    private func setProperty(_ key: CFString, _ value: Any) {
        guard let session else { return }
        let status = VTSessionSetProperty(session, key: key, value: value as CFTypeRef)
        if status != noErr {
            print("[KodmozScreen] VTSessionSetProperty \(key) başarısız: \(status)")
        }
    }

    // MARK: - Çıktı

    private static let outputCallback: VTCompressionOutputCallback = {
        refcon, _, status, _, sampleBuffer in
        guard let refcon, let sampleBuffer else { return }
        let encoder = Unmanaged<H264Encoder>.fromOpaque(refcon).takeUnretainedValue()
        encoder.handleEncodedFrame(sampleBuffer, status: status)
    }

    private func handleEncodedFrame(_ sampleBuffer: CMSampleBuffer, status: OSStatus) {
        lock.lock()
        framesInFlight = max(0, framesInFlight - 1)
        lock.unlock()

        guard status == noErr, !isInvalid, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        lastFormat = format

        let keyframe = sampleIsKeyframe(sampleBuffer)
        guard let payload = annexBPayload(from: sampleBuffer, format: format) else { return }

        var spsWithStartCode: Data?
        var ppsWithStartCode: Data?
        if let sets = parameterSets(from: format) {
            lastSPS = sets.sps
            lastPPS = sets.pps
            spsWithStartCode = sets.sps
            ppsWithStartCode = sets.pps
        }

        encodedFrames += 1
        callbackQueue.async { [weak self] in
            guard let self, !self.isInvalid else { return }
            self.onFrame?(payload, keyframe, spsWithStartCode, ppsWithStartCode)
        }
    }

    private func annexBPayload(from sampleBuffer: CMSampleBuffer, format: CMFormatDescription) -> Data? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        guard length > 0 else { return nil }

        var bytes = [UInt8](repeating: 0, count: length)
        let copyStatus = bytes.withUnsafeMutableBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: base)
        }
        guard copyStatus == noErr else { return nil }

        let startCode: [UInt8] = [0, 0, 0, 1]
        var output = Data(capacity: length + 64)

        let isKeyframe = sampleIsKeyframe(sampleBuffer)
        if isKeyframe, let sets = finalParameterSets(from: format) {
            output.append(contentsOf: startCode)
            output.append(contentsOf: sets.sps)
            output.append(contentsOf: startCode)
            output.append(contentsOf: sets.pps)
        }

        var offset = 0
        while offset + 4 <= length {
            let nalLength = Int(bytes[offset]) << 24
                | Int(bytes[offset + 1]) << 16
                | Int(bytes[offset + 2]) << 8
                | Int(bytes[offset + 3])
            offset += 4
            guard nalLength > 0, offset + nalLength <= length else { break }
            output.append(contentsOf: startCode)
            output.append(contentsOf: bytes[offset..<(offset + nalLength)])
            offset += nalLength
        }
        return output.isEmpty ? nil : output
    }

    private func sampleIsKeyframe(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false),
              CFArrayGetCount(attachments) > 0,
              let raw = CFArrayGetValueAtIndex(attachments, 0) else {
            return true
        }
        let dictionary = unsafeBitCast(raw, to: CFDictionary.self)
        // NotSync anahtarı "false" değeriyle de bulunabildiği için değeri okuyoruz.
        if let notSync = boolValue(in: dictionary, key: kCMSampleAttachmentKey_NotSync), notSync {
            return false
        }
        if let depends = boolValue(in: dictionary, key: kCMSampleAttachmentKey_DependsOnOthers), depends {
            return false
        }
        return true
    }

    private func boolValue(in dictionary: CFDictionary, key: CFString) -> Bool? {
        guard let raw = CFDictionaryGetValue(
            dictionary,
            Unmanaged.passUnretained(key).toOpaque()
        ) else { return nil }
        let value = unsafeBitCast(raw, to: CFBoolean.self)
        return CFBooleanGetValue(value)
    }

    /// SPS/PPS'i 4 baytlık Annex-B başlangıç koduyla döndürür.
    private func parameterSets(from format: CMFormatDescription) -> (sps: Data, pps: Data)? {
        guard let raw = finalParameterSets(from: format) else { return nil }
        let startCode: [UInt8] = [0, 0, 0, 1]
        var sps = Data(startCode)
        sps.append(contentsOf: raw.sps)
        var pps = Data(startCode)
        pps.append(contentsOf: raw.pps)
        return (sps, pps)
    }

    private func finalParameterSets(from format: CMFormatDescription) -> (sps: [UInt8], pps: [UInt8])? {
        var count: Int = 0
        var nalHeaderLength: Int32 = 0
        guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format,
            parameterSetIndex: 0,
            parameterSetPointerOut: nil,
            parameterSetSizeOut: nil,
            parameterSetCountOut: &count,
            nalUnitHeaderLengthOut: &nalHeaderLength
        ) == noErr, count >= 2 else {
            return nil
        }

        var spsPointer: UnsafePointer<UInt8>?
        var spsSize: Int = 0
        guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format,
            parameterSetIndex: 0,
            parameterSetPointerOut: &spsPointer,
            parameterSetSizeOut: &spsSize,
            parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: nil
        ) == noErr, let spsPointer, spsSize > 0 else {
            return nil
        }

        var ppsPointer: UnsafePointer<UInt8>?
        var ppsSize: Int = 0
        guard CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format,
            parameterSetIndex: 1,
            parameterSetPointerOut: &ppsPointer,
            parameterSetSizeOut: &ppsSize,
            parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: nil
        ) == noErr, let ppsPointer, ppsSize > 0 else {
            return nil
        }

        let sps = Array(UnsafeBufferPointer(start: spsPointer, count: spsSize))
        let pps = Array(UnsafeBufferPointer(start: ppsPointer, count: ppsSize))
        return (sps, pps)
    }
}
