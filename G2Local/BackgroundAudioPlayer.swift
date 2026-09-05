// Silent background heartbeat — keeps iOS from suspending the app so the
// loopback ASR server stays reachable while the phone is locked.
//
// Plays an inaudible looping buffer (zero-filled) through AVAudioEngine with
// the .playback session category + the app's "audio" background mode.
// No audio files, no network, ~0.01% CPU.
//
// Tradeoff (Apple policy): the Now Playing indicator shows "G2 Local"
// playing while the heartbeat runs. Toggle it off in the app UI anytime.

import AVFoundation
import Foundation

final class BackgroundAudioPlayer {
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default,
                                    options: [.mixWithOthers])
            try session.setActive(true)

            let engine = AVAudioEngine()
            let node = AVAudioPlayerNode()
            engine.attach(node)

            // Silence buffer sized to one second of the output format.
            let format = engine.outputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw NSError(domain: "g2local", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "bad output format"])
            }
            let frameCapacity = AVAudioFrameCount(format.sampleRate)
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCapacity
            )!
            buffer.frameLength = frameCapacity
            if let ch = buffer.floatChannelData?[0] {
                memset(ch, 0, Int(frameCapacity) * MemoryLayout<Float>.size)
            }

            engine.connect(node, to: engine.mainMixerNode, format: format)
            engine.prepare()
            try engine.start()
            node.scheduleBuffer(buffer, at: nil, options: [.loops])
            node.play()

            self.engine = engine
            self.playerNode = node
            self.isRunning = true
            NSLog("g2local: heartbeat started")
        } catch {
            NSLog("g2local: heartbeat failed: \(error)")
            cleanup()
        }
    }

    func stop() {
        guard isRunning else { return }
        cleanup()
        NSLog("g2local: heartbeat stopped")
    }

    private func cleanup() {
        playerNode?.stop()
        engine?.stop()
        if let node = playerNode { engine?.detach(node) }
        playerNode = nil
        engine = nil
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
