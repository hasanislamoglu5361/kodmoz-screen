import Foundation
import Network

/// Tabletin bağlandığı TCP sunucusu. Aynı anda tek istemci kabul eder.
/// Bonjour ile `_kodmoz-screen._tcp` servisi olarak duyurulur.
final class StreamServer {
    struct DisplayInfo {
        var width: Int
        var height: Int
        var fps: Int
        var bitrate: Int
        var scale: Int
        var name: String
    }

    enum Status: Equatable {
        case stopped
        case listening
        case clientConnecting(String?)
        case streaming(String)
        case failed(String)

        var text: String {
            switch self {
            case .stopped: return "Sunucu kapalı"
            case .listening: return "Bağlantı bekleniyor"
            case .clientConnecting(let name): return name.map { "\($0) bağlanıyor…" } ?? "İstemci bağlanıyor…"
            case .streaming(let name): return "Bağlı: \(name)"
            case .failed(let message): return message
            }
        }
    }

    var displayInfoProvider: (() -> DisplayInfo)?
    var onInput: ((InputEvent) -> Void)?
    var onStatusChange: ((Status) -> Void)?
    var onStats: ((_ fps: Double, _ mbps: Double) -> Void)?
    var onKeyframeNeeded: (() -> Void)?

    private(set) var status: Status = .stopped
    private(set) var isStreaming = false
    private(set) var connectedDevice: String?

    private let queue = DispatchQueue(label: "com.kodmoz.screen.server")
    private var listener: NWListener?
    private var statsTimer: DispatchSourceTimer?
    private var session: ClientSession?
    private var framesThisSecond = 0
    private var bytesThisSecond = 0
    private var requiredCode: String?

    private final class ClientSession {
        enum State {
            case handshake
            case awaitingKeyframe
            case streaming
            case closed
        }

        let connection: NWConnection
        var deviceName = ""
        var state: State = .handshake
        var pendingBytes = 0
        var sps: Data?
        var pps: Data?

        init(connection: NWConnection) {
            self.connection = connection
        }
    }

    deinit {
        statsTimer?.cancel()
        session?.connection.cancel()
        listener?.cancel()
    }

    // MARK: - Yaşam döngüsü

    func start(port: Int, serviceName: String, requiredCode: String?) {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopLocked()
            self.requiredCode = requiredCode.flatMap { $0.isEmpty ? nil : $0 }

            do {
                let tcp = NWProtocolTCP.Options()
                tcp.noDelay = true
                tcp.enableKeepalive = true
                tcp.keepaliveIdle = 5
                tcp.keepaliveCount = 3
                tcp.keepaliveInterval = 2
                tcp.connectionTimeout = 6

                let parameters = NWParameters(tls: nil, tcp: tcp)
                parameters.allowLocalEndpointReuse = true

                guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
                    self.setStatus(.failed("Geçersiz port: \(port)"))
                    return
                }

                let listener = try NWListener(using: parameters, on: nwPort)
                listener.service = NWListener.Service(
                    name: serviceName,
                    type: "_kodmoz-screen._tcp"
                )
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    self.queue.async {
                        switch state {
                        case .ready:
                            self.setStatus(.listening)
                        case .failed(let error):
                            let detail = error.localizedDescription
                            if detail.lowercased().contains("address already in use") {
                                self.setStatus(.failed("Port kullanımda. Başka bir Kodmoz Screen kopyası çalışıyor olabilir."))
                            } else {
                                self.setStatus(.failed("Sunucu hatası: \(detail)"))
                            }
                        default:
                            break
                        }
                    }
                }
                self.listener = listener
                listener.start(queue: self.queue)
                self.startStatsTimer()
                NSLog("[KodmozScreen] sunucu dinliyor: port \(port)")
            } catch {
                self.setStatus(.failed("Sunucu başlatılamadı: \(error.localizedDescription)"))
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopLocked()
        }
    }

    /// Eşleşme kodunu bağlantıyı kesmeden günceller; bir sonraki
    /// el sıkışmada geçerli olur.
    func setRequiredCode(_ code: String?) {
        queue.async { [weak self] in
            self?.requiredCode = code.flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    private func stopLocked() {
        statsTimer?.cancel()
        statsTimer = nil
        if let session {
            session.state = .closed
            session.connection.cancel()
        }
        session = nil
        listener?.cancel()
        listener = nil
        isStreaming = false
        connectedDevice = nil
        framesThisSecond = 0
        bytesThisSecond = 0
        setStatus(.stopped)
    }

    // MARK: - Bağlantı

    private func accept(_ connection: NWConnection) {
        queue.async { [weak self] in
            guard let self else {
                connection.cancel()
                return
            }
            if let old = self.session {
                old.state = .closed
                old.connection.cancel()
            }
            let session = ClientSession(connection: connection)
            self.session = session
            self.isStreaming = false
            self.connectedDevice = nil
            self.framesThisSecond = 0
            self.bytesThisSecond = 0
            self.setStatus(.clientConnecting(nil))

            connection.stateUpdateHandler = { [weak self, weak session] state in
                guard let self, let session else { return }
                self.queue.async {
                    guard self.session === session else { return }
                    switch state {
                    case .ready:
                        self.readHello(session)
                    case .failed, .cancelled:
                        self.close(session, reason: "connection")
                    default:
                        break
                    }
                }
            }
            connection.start(queue: self.queue)

            self.queue.asyncAfter(deadline: .now() + 12) { [weak self, weak session] in
                guard let self, let session,
                      self.session === session,
                      session.state == .handshake else { return }
                self.sendError(
                    "Video akışı başlamadı. Mac'te Ekran Kaydı iznini kontrol edin.",
                    code: "timeout",
                    to: session,
                    closeAfter: true
                )
            }
        }
    }

    private func readHello(_ session: ClientSession) {
        readExactly(session.connection, count: WireProtocol.handshakeHeaderSize) { [weak self, weak session] header in
            guard let self, let session else { return }
            self.queue.async {
                guard self.session === session else { return }
                guard let header,
                      header.count == WireProtocol.handshakeHeaderSize,
                      Array(header.prefix(8)) == WireProtocol.magic else {
                    self.sendError("Geçersiz istemci.", code: "badMagic", to: session, closeAfter: true)
                    return
                }
                guard header[8] == WireProtocol.version else {
                    self.sendError(
                        "Protokol sürümü uyumsuz (istemci \(header[8]), sunucu \(WireProtocol.version)).",
                        code: "badVersion",
                        to: session,
                        closeAfter: true
                    )
                    return
                }

                let jsonLength = Int(header.beUInt32(at: 12))
                guard jsonLength > 0, jsonLength <= WireProtocol.maxHandshakeJSON else {
                    self.sendError("Geçersiz el sıkışma.", code: "badHello", to: session, closeAfter: true)
                    return
                }

                self.readExactly(session.connection, count: jsonLength) { [weak self, weak session] jsonData in
                    guard let self, let session else { return }
                    self.queue.async {
                        guard self.session === session, let jsonData else {
                            self.close(session, reason: "helloRead")
                            return
                        }
                        self.handleHello(session, jsonData: jsonData)
                    }
                }
            }
        }
    }

    private func handleHello(_ session: ClientSession, jsonData: Data) {
        let hello: WireProtocol.Hello
        do {
            hello = try JSONDecoder().decode(WireProtocol.Hello.self, from: jsonData)
        } catch {
            sendError("El sıkışma JSON'u okunamadı.", code: "badJSON", to: session, closeAfter: true)
            return
        }

        guard hello.protocol == Int(WireProtocol.version) else {
            sendError(
                "Protokol sürümü uyumsuz (istemci \(hello.protocol), sunucu \(WireProtocol.version)).",
                code: "badVersion",
                to: session,
                closeAfter: true
            )
            return
        }

        if let requiredCode {
            let provided = (hello.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard provided == requiredCode else {
                sendError("Eşleşme kodu hatalı. Mac ekranındaki 4 haneli kodu girin.", code: "badCode", to: session, closeAfter: true)
                return
            }
        }

        session.deviceName = String(hello.device.prefix(64)).replacingOccurrences(of: "\n", with: " ")
        if session.deviceName.isEmpty { session.deviceName = "Android tablet" }
        session.state = .awaitingKeyframe
        connectedDevice = session.deviceName
        setStatus(.clientConnecting(session.deviceName))
        NSLog("[KodmozScreen] istemci bağlandı: %@", session.deviceName)

        DispatchQueue.main.async { [weak self] in
            self?.onKeyframeNeeded?()
        }
        readMessages(session)
    }

    private func readMessages(_ session: ClientSession) {
        readExactly(session.connection, count: 8) { [weak self, weak session] header in
            guard let self, let session, let header else { return }
            self.queue.async {
                guard self.session === session, session.state != .closed else { return }
                let type = header[0]
                let length = Int(header.beUInt32(at: 4))
                guard length <= WireProtocol.maxPayload else {
                    self.close(session, reason: "oversize")
                    return
                }

                if length == 0 {
                    self.handleMessage(session, type: type, payload: Data())
                    if session.state != .closed { self.readMessages(session) }
                    return
                }

                self.readExactly(session.connection, count: length) { [weak self, weak session] payload in
                    guard let self, let session, let payload else { return }
                    self.queue.async {
                        guard self.session === session, session.state != .closed else { return }
                        self.handleMessage(session, type: type, payload: payload)
                        if session.state != .closed { self.readMessages(session) }
                    }
                }
            }
        }
    }

    private func handleMessage(_ session: ClientSession, type: UInt8, payload: Data) {
        switch type {
        case WireProtocol.MessageType.input.rawValue:
            if let event = Self.parseInput(payload) {
                onInput?(event)
            }
        case WireProtocol.MessageType.ping.rawValue:
            sendRaw(makeMessage(type: .pong, payload: payload), to: session)
        case WireProtocol.MessageType.bye.rawValue:
            close(session, reason: "bye")
        default:
            break
        }
    }

    private func close(_ session: ClientSession, reason: String) {
        guard self.session === session else { return }
        session.state = .closed
        session.connection.cancel()
        self.session = nil
        isStreaming = false
        connectedDevice = nil
        setStatus(listener == nil ? .stopped : .listening)
        NSLog("[KodmozScreen] bağlantı kapandı: %@", reason)
    }

    // MARK: - Video

    func sendVideo(_ payload: Data, keyframe: Bool, sps: Data?, pps: Data?) {
        queue.async { [weak self] in
            guard let self, let session = self.session else { return }
            guard session.state == .awaitingKeyframe || session.state == .streaming else { return }

            if session.state == .awaitingKeyframe {
                guard keyframe, let sps, let pps else { return }
                let info = self.currentInfo()
                let hello = WireProtocol.ServerHello(
                    `protocol`: Int(WireProtocol.version),
                    ok: true,
                    width: info.width,
                    height: info.height,
                    fps: info.fps,
                    bitrate: info.bitrate,
                    codec: "avc",
                    sps: sps.base64EncodedString(),
                    pps: pps.base64EncodedString(),
                    display: info.name,
                    scale: info.scale,
                    server: AppInfo.version
                )
                guard let json = try? JSONEncoder().encode(hello) else { return }
                session.state = .streaming
                session.sps = sps
                session.pps = pps
                self.isStreaming = true
                self.setStatus(.streaming(session.deviceName))
                self.sendRaw(makeHandshakeFrame(json: json), to: session)
                self.sendVideoFrame(payload, keyframe: true, to: session)
                return
            }

            // TCP geri baskısı: 6 MB'tan fazla birikmişse ara kareleri atla.
            if session.pendingBytes > 6_000_000 && !keyframe { return }
            self.sendVideoFrame(payload, keyframe: keyframe, to: session)
        }
    }

    private func sendVideoFrame(_ payload: Data, keyframe: Bool, to session: ClientSession) {
        var flags: UInt8 = 0
        if keyframe {
            flags |= WireProtocol.Flags.keyframe | WireProtocol.Flags.config
        }
        let frame = makeMessage(type: .video, flags: flags, payload: payload)
        sendRaw(frame, to: session)
        framesThisSecond += 1
        bytesThisSecond += frame.count
    }

    private func sendRaw(_ data: Data, to session: ClientSession) {
        session.pendingBytes += data.count
        session.connection.send(content: data, completion: .contentProcessed { [weak self, weak session] error in
            guard let self, let session else { return }
            self.queue.async {
                session.pendingBytes = max(0, session.pendingBytes - data.count)
                if error != nil {
                    self.close(session, reason: "send")
                }
            }
        })
    }

    private func sendError(_ message: String, code: String, to session: ClientSession, closeAfter: Bool) {
        let data = makeServerError(message: message, code: code)
        session.connection.send(content: data, completion: .contentProcessed { [weak self, weak session] _ in
            guard let self, let session else { return }
            if closeAfter {
                self.queue.async { self.close(session, reason: code) }
            }
        })
    }

    // MARK: - İstatistik

    private func startStatsTimer() {
        statsTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let fps = Double(self.framesThisSecond)
            let mbps = Double(self.bytesThisSecond) * 8.0 / 1_000_000.0
            self.framesThisSecond = 0
            self.bytesThisSecond = 0

            if let session = self.session, session.state == .streaming {
                let info = self.currentInfo()
                let stats = WireProtocol.Stats(
                    fps: fps,
                    mbps: (mbps * 10).rounded() / 10,
                    width: info.width,
                    height: info.height
                )
                if let json = try? JSONEncoder().encode(stats) {
                    self.sendRaw(makeMessage(type: .stats, payload: json), to: session)
                }
            }

            DispatchQueue.main.async { [weak self] in
                self?.onStats?(fps, mbps)
            }
        }
        timer.resume()
        statsTimer = timer
    }

    private func currentInfo() -> DisplayInfo {
        displayInfoProvider?() ?? DisplayInfo(
            width: 1280,
            height: 800,
            fps: 60,
            bitrate: 16_000_000,
            scale: 2,
            name: "Kodmoz Screen"
        )
    }

    private func setStatus(_ status: Status) {
        self.status = status
        DispatchQueue.main.async { [weak self] in
            self?.onStatusChange?(status)
        }
    }

    // MARK: - Girdi ayrıştırma

    static func parseInput(_ payload: Data) -> InputEvent? {
        guard let kind = payload.first else { return nil }
        switch kind {
        case WireProtocol.InputKind.move.rawValue:
            guard payload.count >= 5 else { return nil }
            return .move(
                x: Double(payload.beUInt16(at: 1)) / 65535.0,
                y: Double(payload.beUInt16(at: 3)) / 65535.0
            )

        case WireProtocol.InputKind.button.rawValue:
            guard payload.count >= 9 else { return nil }
            return .button(
                x: Double(payload.beUInt16(at: 1)) / 65535.0,
                y: Double(payload.beUInt16(at: 3)) / 65535.0,
                button: Int(payload[5]),
                down: payload[6] != 0,
                clickCount: Int(payload[7])
            )

        case WireProtocol.InputKind.scroll.rawValue:
            guard payload.count >= 5 else { return nil }
            return .scroll(
                dx: Int(Int16(bitPattern: payload.beUInt16(at: 1))),
                dy: Int(Int16(bitPattern: payload.beUInt16(at: 3)))
            )

        case WireProtocol.InputKind.key.rawValue:
            guard payload.count >= 5 else { return nil }
            return .key(
                code: Int(payload.beUInt16(at: 1)),
                down: payload[3] != 0,
                meta: Int(payload[4])
            )

        case WireProtocol.InputKind.text.rawValue:
            let text = String(data: payload.dropFirst(), encoding: .utf8) ?? ""
            return text.isEmpty ? nil : .text(text)

        default:
            return nil
        }
    }

    // MARK: - Bayt okuma

    private func readExactly(_ connection: NWConnection, count: Int, completion: @escaping (Data?) -> Void) {
        guard count > 0 else {
            completion(Data())
            return
        }
        var buffer = Data(capacity: count)

        func attempt() {
            let remaining = count - buffer.count
            guard remaining > 0 else {
                completion(buffer)
                return
            }
            connection.receive(minimumIncompleteLength: remaining, maximumLength: remaining) { data, _, isComplete, error in
                if let data {
                    buffer.append(data)
                }
                if buffer.count >= count {
                    completion(buffer)
                } else if error != nil || isComplete {
                    completion(nil)
                } else {
                    attempt()
                }
            }
        }
        attempt()
    }
}
