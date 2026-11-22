import Foundation
import Network
import AVFoundation
import MediaPlayer
import UIKit

final class Receiver: ObservableObject {
    @Published var status = "Starting"

    private let queue = DispatchQueue(label: "sidespeaker.rx", qos: .userInteractive)
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var listener: NWListener?
    private var conn: NWConnection?
    private var buf = Data()
    private var fmt: AVAudioFormat?
    private var channels = 2
    private var queuedFrames = 0
    private var playing = false
    private var rateHz = 48000
    private var underruns = 0
    private var resyncs = 0
    private var isBackground = false
    private var prebufferFrames = 0
    private var maxFrames = 0
    private var generation = 0
    private var started = false
    private var lastData = Date()
    private var timer: DispatchSourceTimer?
    private let timeout: TimeInterval
    private let port: UInt16
    private let prebufferMs: Int
    private let maxBufferMs: Int
    private let bgPrebufferMs: Int
    private let bgMaxBufferMs: Int

    init() {
        let info = Bundle.main.infoDictionary
        port = UInt16((info?["SidePort"] as? Int) ?? 5000)
        let prebuffer = (info?["SidePrebufferMs"] as? Int) ?? 30
        let maxBuffer = (info?["SideMaxBufferMs"] as? Int) ?? 60
        prebufferMs = prebuffer
        maxBufferMs = maxBuffer
        bgPrebufferMs = (info?["SideBgPrebufferMs"] as? Int) ?? prebuffer
        bgMaxBufferMs = (info?["SideBgMaxBufferMs"] as? Int) ?? maxBuffer
        timeout = Double((info?["SideTimeoutMs"] as? Int) ?? 3000) / 1000.0
        engine.attach(player)
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.setMode(background: true) }
        }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.setMode(background: false) }
        }
    }

    private func setStatus(_ s: String) {
        DispatchQueue.main.async { self.status = s }
    }

    func start() {
        if started { return }
        started = true
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try? session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
            setupNowPlaying()
            let l = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.start(queue: queue)
            listener = l
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 0.5, repeating: 0.5)
            t.setEventHandler { [weak self] in
                guard let self = self, self.conn != nil else { return }
                if Date().timeIntervalSince(self.lastData) > self.timeout { self.teardown(); return }
                if self.fmt != nil {
                    let ms = self.queuedFrames * 1000 / max(1, self.rateHz)
                    let route = session.currentRoute.outputs.map(\.portName).joined(separator: ", ")
                    let ioMs = Int((session.ioBufferDuration * 1000).rounded())
                    let outputMs = Int((session.outputLatency * 1000).rounded())
                    let queueStatus = "buffer \(ms) ms · underruns \(self.underruns) · resyncs \(self.resyncs)"
                    let routeStatus = "\(route) · I/O \(ioMs) ms · output \(outputMs) ms"
                    self.setStatus("Streaming \(self.rateHz) Hz\n\(queueStatus)\n\(routeStatus)")
                }
            }
            t.resume()
            timer = t
            setStatus("Waiting for PC on port \(port)")
        } catch {
            setStatus("Error: \(error.localizedDescription)")
        }
    }

    private func setupNowPlaying() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { _ in .success }
        commands.pauseCommand.addTarget { _ in .success }
        commands.togglePlayPauseCommand.addTarget { _ in .success }
        DispatchQueue.main.async {
            let center = MPNowPlayingInfoCenter.default()
            center.nowPlayingInfo = [
                MPMediaItemPropertyTitle: "Sidespeaker",
                MPMediaItemPropertyArtist: "Playing PC audio over USB",
                MPNowPlayingInfoPropertyIsLiveStream: true,
                MPNowPlayingInfoPropertyPlaybackRate: 1.0
            ]
            center.playbackState = .playing
        }
    }

    private func accept(_ c: NWConnection) {
        teardown()
        conn = c
        lastData = Date()
        c.start(queue: queue)
        read(c)
    }

    private func read(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self = self, c === self.conn else { return }
            if let data = data, !data.isEmpty {
                self.lastData = Date()
                self.buf.append(data)
                self.process()
            }
            if done || err != nil {
                self.teardown()
                return
            }
            self.read(c)
        }
    }

    private func process() {
        if fmt == nil {
            guard buf.count >= 8 else { return }
            let rate = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
            let ch = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }
            buf.removeSubrange(0..<8)
            guard rate > 0, ch >= 1, ch <= 2,
                  let f = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: AVAudioChannelCount(ch)) else {
                teardown()
                return
            }
            channels = Int(ch)
            rateHz = Int(rate)
            underruns = 0
            resyncs = 0
            fmt = f
            applyBuffers()
            queuedFrames = 0
            playing = false
            engine.connect(player, to: engine.mainMixerNode, format: f)
            do {
                try engine.start()
                setStatus("Streaming \(rate) Hz")
            } catch {
                setStatus("Engine error: \(error.localizedDescription)")
                teardown()
                return
            }
        }
        guard let f = fmt else { return }
        let ch = channels
        let bytesPerFrame = 2 * ch
        let receivedFrames = buf.count / bytesPerFrame
        if receivedFrames == 0 { return }
        var firstFrame = 0
        if queuedFrames + receivedFrames > maxFrames {
            // Stop playing stale audio and restart from the newest available frames.
            resetPlaybackQueue()
            resyncs += 1
            firstFrame = max(0, receivedFrames - prebufferFrames)
        }
        let frames = receivedFrames - firstFrame

        guard let pcm = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: AVAudioFrameCount(frames)),
              let chData = pcm.floatChannelData else { return }
        pcm.frameLength = AVAudioFrameCount(frames)
        buf.withUnsafeBytes { raw in
            for i in 0..<frames {
                for c in 0..<ch {
                    let offset = (i + firstFrame) * bytesPerFrame + c * 2
                    let v = raw.loadUnaligned(fromByteOffset: offset, as: Int16.self)
                    chData[c][i] = Float(Int16(littleEndian: v)) / 32768.0
                }
            }
        }
        buf.removeSubrange(0..<(receivedFrames * bytesPerFrame))

        queuedFrames += frames
        let g = generation
        player.scheduleBuffer(pcm, completionCallbackType: .dataRendered) { [weak self] _ in
            self?.queue.async {
                guard let self = self, g == self.generation else { return }
                self.queuedFrames = max(0, self.queuedFrames - frames)
                if self.queuedFrames == 0 && self.playing {
                    self.player.pause()
                    self.playing = false
                    self.underruns += 1
                }
            }
        }
        if !playing && queuedFrames >= prebufferFrames {
            player.play()
            playing = true
        }
    }

    private func applyBuffers() {
        let pre = isBackground ? bgPrebufferMs : prebufferMs
        let mx = isBackground ? bgMaxBufferMs : maxBufferMs
        prebufferFrames = max(1, rateHz * pre / 1000)
        maxFrames = max(prebufferFrames, rateHz * mx / 1000)
    }

    private func setMode(background: Bool) {
        isBackground = background
        applyBuffers()
    }

    private func resetPlaybackQueue() {
        generation += 1
        player.stop()
        queuedFrames = 0
        playing = false
    }

    private func teardown() {
        generation += 1
        conn?.cancel()
        conn = nil
        buf = Data()
        queuedFrames = 0
        playing = false
        if fmt != nil {
            player.stop()
            engine.stop()
            engine.disconnectNodeOutput(player)
            fmt = nil
        }
        setStatus("Waiting for PC on port \(port)")
    }
}
