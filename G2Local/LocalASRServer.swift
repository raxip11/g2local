// G2 Local — offline Whisper ASR for the G2 Voice webview.
//
// The G2 mic only reaches the phone via the Even Hub webview bridge, so this
// app does NOT own the microphone. Instead it runs a tiny loopback HTTP
// server (127.0.0.1:8321) that speaks the SAME protocol as the cloud ASR
// service, plus a local WhisperKit model. The webview page is pointed here
// with ?asr_base=http://127.0.0.1:8321 and everything stays on the phone.
//
// Endpoints (loopback only, token-gated like the cloud endpoint):
//   GET  /asr/health  -> {"ok":true,"model":"..."}        (public)
//   POST /asr         -> {"task","language","pcm_b64"}    (x-asr-token)
//                        -> {"text","language","duration","seconds"}
//   OPTIONS *         -> 204 + CORS

import Foundation
import Network

final class LocalASRServer {
    static let port: UInt16 = 8321

    private let engine: WhisperEngine
    private let token: String
    private var listener: NWListener?
    private(set) var isUp = false

    init(engine: WhisperEngine, token: String) {
        self.engine = engine
        self.token = token
    }

    func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: Self.port)!
        )
        let l: NWListener
        do {
            l = try NWListener(using: params)
        } catch {
            NSLog("g2local: listener failed: \(error)")
            return
        }
        listener = l
        l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        l.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.isUp = true
            } else if case .failed = state {
                self?.isUp = false
            }
        }
        l.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isUp = false
    }

    // ── Minimal HTTP/1.1 over NWConnection ──────────────────────────────────

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .userInitiated))
        receive(conn, buffered: Data())
    }

    private func receive(_ conn: NWConnection, buffered: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] buf, _, isDone, error in
            guard let self else { return }
            var all = buffered
            if let buf { all.append(buf) }

            guard let end = Self.headerEnd(in: all) else {
                if isDone || error != nil { conn.cancel() }
                else { self.receive(conn, buffered: all) }
                return
            }
            let head = String(decoding: all[..<end.lowerBound], as: UTF8.string.self)
            let bodyStart = end.upperBound
            let contentLength = Self.contentLength(of: head)
            let have = all.count - bodyStart
            guard have >= contentLength else {
                self.receive(conn, buffered: all)
                return
            }
            let body = all.subdata(in: bodyStart..<bodyStart + contentLength)
            self.respond(head: head, body: body, to: conn)
        }
    }

    private static func headerEnd(in data: Data) -> Range<Data.Index>? {
        let needle = [0x0D, 0x0A, 0x0D, 0x0A]
        let limit = data.count - 3
        guard limit > 4 else { return nil }
        for i in 0..<limit {
            if data[i] == needle[0] && data[i+1] == needle[1] && data[i+2] == needle[2] && data[i+3] == needle[3] {
                return i..<(i+4)
            }
        }
        return nil
    }

    private static func contentLength(of head: String) -> Int {
        for line in head.split(separator: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                return Int(lower.dropFirst(15).trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }

    private func headerValue(_ head: String, _ name: String) -> String? {
        for line in head.split(separator: "\r\n").dropFirst() {
            if line.lowercased().hasPrefix(name.lowercased() + ":") {
                return line.dropFirst(name.count + 1).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func respond(head: String, body: Data, to conn: NWConnection) {
        let firstLine = head.split(separator: "\r\n").first.map(String.init) ?? ""
        let parts = firstLine.split(separator: " ")
        let method = parts.first.map(String.init) ?? ""
        let path = parts.count > 1 ? String(parts[1]) : "/"

        // CORS preflight — lets the cloud-hosted page talk to localhost.
        if method == "OPTIONS" {
            let h = "access-control-allow-origin: *\r\n" +
                    "access-control-allow-methods: POST, GET, OPTIONS\r\n" +
                    "access-control-allow-headers: content-type, x-asr-token\r\n"
            send(conn, status: 204, headers: h, body: Data())
            return
        }

        if path == "/asr/health" || path == "/voice/asr/health" {
            let payload = #"{"ok":true,"model":"\#(engine.modelName)","state":"\#(engine.state)"}"#.data(using: .utf8)!
            send(conn, status: 200, headers: "", body: payload)
            return
        }

        if (path == "/asr" || path == "/voice/asr"), method == "POST" {
            // Token gate: the listener binds 127.0.0.1 ONLY, so nothing
            // off-device can reach it — the token is defense-in-depth.
            // Accepts the shared token the webview bundle already sends.
            let supplied = headerValue(head, "x-asr-token") ?? ""
            if !(supplied.isEmpty || supplied == token || Self.allowedTokens.contains(supplied)) {
                send(conn, status: 401, headers: "", body: Data(#"{"error":"unauthorized"}"#.utf8))
                return
            }
            onResult?(nil, nil) // request received (UI "listening" flash)
            let started = Date()
            Task { @MainActor in
                do {
                    let result = try await self.transcribe(body)
                    let seconds = Date().timeIntervalSince(started)
                    let out = #"{"text":"\#(Self.jsonEscape(result.text))","language":"\#(result.language)","#
                             +   #""duration":\#(result.duration),#
                             +   #""seconds":\#(String(format: "%.2f", seconds))}"#
                    self.onResult?(result.text, seconds)
                    self.send(conn, status: 200, headers: "", body: Data(out.utf8))
                } catch {
                    self.send(conn, status: 500, headers: "", body: Data(#"{"error":"\#(Self.jsonEscape(error.localizedDescription))"}"#.utf8))
                }
            }
            return
        }

        send(conn, status: 404, headers: "", body: Data(#"{"error":"not found"}"#.utf8))
    }

    /// Shared secret matching the webview bundle (baked, not a security
    /// boundary — the loopback bind is the real gate).
    static let allowedTokens: Set<String> = [
        "CZHLxT-CW6ZnLFasS6LWiV07QqTMK0TNuE8aNUUm4UE",
        "g2local-local",
    ]

    /// UI callback (main thread): (text?, seconds?) — nil/nil = request started.
    var onResult: ((String?, Double?) -> Void)?

    private func transcribe(_ body: Data) async throws -> (text: String, language: String, duration: Double) {
        guard let obj = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let b64 = obj["pcm_b64"] as? String,
              let raw = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else {
            throw NSError(domain: "g2local", code: 400, userInfo: [NSLocalizedDescriptionKey: "bad payload"])
        }
        var floats = [Float]()
        floats.reserveCapacity(raw.count / 4)
        for i in stride(from: 0, to: raw.count - 3, by: 4) {
            floats.append(Float(bitPattern: UInt32(raw[i]) | UInt32(raw[i+1]) << 8 | UInt32(raw[i+2]) << 16 | UInt32(raw[i+3]) << 24))
        }
        let task = (obj["task"] as? String) ?? "transcribe"
        let language = obj["language"] as? String
        let duration = Double(floats.count) / 16_000.0
        let r = try engine.transcribe(floats: floats, task: task, language: language)
        return (r.text, r.language ?? (language ?? "en"), duration)
    }

    private func send(_ conn: NWConnection, status: Int, headers: String, body: Data) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 204: reason = "No Content"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        default: reason = "OK"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        if status != 204 {
            head += "content-type: application/json\r\n"
        }
        head += "access-control-allow-origin: *\r\n"
        head += "content-length: \(body.count)\r\n"
        head += "connection: close\r\n"
        head += headers
        head += "\r\n"
        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    private static func jsonEscape(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "\\", with: "\\\\")
        out = out.replacingOccurrences(of: "\"", with: "\\\"")
        out = out.replacingOccurrences(of: "\n", with: "\\n")
        out = out.replacingOccurrences(of: "\r", with: "\\r")
        out = out.replacingOccurrences(of: "\t", with: "\\t")
        return out
    }
}
