// G2 Local — offline ASR for the G2 Voice webview (Even Hub companion).
//
// This app runs a loopback HTTP server + WhisperKit. It owns NO microphone:
// the G2 mic streams through the Even Hub webview, whose page (served by
// the cloud or by this app) POSTs to 127.0.0.1:8321.

import SwiftUI

@main
struct G2LocalApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .task { await app.start() }
        }
    }
}

final class AppModel: ObservableObject {
    @Published var status = "starting"
    @Published var lastText = ""
    @Published var lastSeconds: Double?
    @Published var serverUp = false
    @Published var modelName = "openai_whisper-small"
    @Published var heartbeatOn = false

    private let engine = WhisperEngine()
    private var server: LocalASRServer?
    private var timer: Timer?
    private let heartbeat = BackgroundAudioPlayer()

    /// Shared with the loopback page (same value as the cloud bundle).
    let token = "CZHLxT-CW6ZnLFasS6LWiV07QqTMK0TNuE8aNUUm4UE"

    func start() async {
        status = "loading model (first time downloads it)…"
        do {
            try await engine.load(modelName: modelName)
        } catch {
            status = "model failed: \(error.localizedDescription)"
            return
        }
        let s = LocalASRServer(engine: engine, token: token)
        s.onResult = { [weak self] text, seconds in
            DispatchQueue.main.async {
                guard let self else { return }
                if let text, !text.isEmpty {
                    self.lastText = text
                    self.lastSeconds = seconds
                }
            }
        }
        s.start()
        server = s
        status = "ready"
        NSLog("g2local: loopback server on 127.0.0.1:\(LocalASRServer.port)")
        // Poll server state for the UI dot.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.serverUp = s.isUp }
        }
    }

    /// Starts/stops the silent background heartbeat. While running, iOS
    /// keeps the app alive (screen off, pocket) so 127.0.0.1:8321 stays up.
    /// Cost: "G2 Local" shows in the Now Playing indicator.
    func setHeartbeat(_ on: Bool) {
        heartbeatOn = on
        if on {
            heartbeat.start()
        } else {
            heartbeat.stop()
        }
    }

    func stop() {
        server?.stop()
        timer?.invalidate()
        heartbeat.stop()
    }
}

struct ContentView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Circle()
                    .fill(app.status == "ready" && app.serverUp ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text("G2 Local")
                    .font(.title3.weight(.semibold))
            }
            .padding(.top, 12)

            Text(app.status)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(app.lastText.isEmpty ? "— no transcription yet —" : app.lastText)
                .font(.body)
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

            if let s = app.lastSeconds {
                Text(String(format: "%.1f s · 127.0.0.1:8321", s))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Toggle("Keep alive in background (heartbeat)", isOn: Binding(
                get: { app.heartbeatOn },
                set: { app.setHeartbeat($0) }
            ))
            .font(.callout)
            .padding(.horizontal)

            Spacer()

            GroupBox {
                Text("Keep this app running (or screen on) while using the G2. The Even Hub page sends audio here over localhost — nothing leaves the phone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
        .padding()
            .onChange(of: scenePhase) { phase in
                if phase == .background {
                    // No-op: loopback server keeps running until iOS suspends us.
                }
            }
    }
}
