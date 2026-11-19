import AVFoundation
import Foundation
import UIKit

/// Haptics, pre-warmed once and reused (no per-event allocation).
@MainActor
final class HapticsService {
    var isEnabled = true
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let notify = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    enum Effect {
        case coin, laneChange, nearMiss(Int), bump, crash, success, warning, select
    }

    func prepare() {
        guard isEnabled else { return }
        light.prepare()
        medium.prepare()
        heavy.prepare()
    }

    func play(_ effect: Effect) {
        guard isEnabled else { return }
        switch effect {
        case .coin: light.impactOccurred(intensity: 0.5)
        case .laneChange: selection.selectionChanged()
        case .nearMiss(let combo): rigid.impactOccurred(intensity: min(1, 0.5 + Double(combo) * 0.1))
        case .bump: medium.impactOccurred()
        case .crash: heavy.impactOccurred()
        case .success: notify.notificationOccurred(.success)
        case .warning: notify.notificationOccurred(.warning)
        case .select: selection.selectionChanged()
        }
    }
}

/// Procedurally synthesised sound effects: no audio assets to license, and
/// all buffers are rendered once at start-up. Uses the `.ambient` session so
/// the silent switch is respected and the player's own music keeps playing.
@MainActor
final class SoundService {
    enum Sound: CaseIterable {
        case coin, water, nearMiss, crash, bell, finish, star, whoosh, penalty, boost
    }

    var isEnabled = true
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0
    private var started = false
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    func start() {
        guard !started else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            return
        }
        for _ in 0..<6 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            players.append(node)
        }
        engine.mainMixerNode.outputVolume = 0.7
        for sound in Sound.allCases { buffers[sound] = render(sound) }
        do {
            try engine.start()
            players.forEach { $0.play() }
            started = true
        } catch {
            started = false
        }
    }

    func play(_ sound: Sound, pitch: Float = 1) {
        guard isEnabled, started, let buffer = buffers[sound], !players.isEmpty else { return }
        if !engine.isRunning { try? engine.start() }
        let node = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !node.isPlaying { node.play() }
    }

    // MARK: Synthesis

    private func render(_ sound: Sound) -> AVAudioPCMBuffer? {
        let sr = format.sampleRate
        func tone(_ duration: Double, _ fill: (Double, Double) -> Double) -> AVAudioPCMBuffer? {
            let frames = AVAudioFrameCount(duration * sr)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
                  let data = buffer.floatChannelData?[0] else { return nil }
            buffer.frameLength = frames
            var noiseState: UInt32 = 0x1234_5678
            for i in 0..<Int(frames) {
                let t = Double(i) / sr
                let p = t / duration
                noiseState = noiseState &* 1_664_525 &+ 1_013_904_223
                let noise = Double(noiseState) / Double(UInt32.max) * 2 - 1
                data[i] = Float(fill(t, p) + (sound == .crash || sound == .whoosh ? noise * noiseAmount(sound, p) : 0))
            }
            return buffer
        }
        func env(_ p: Double, attack: Double = 0.02) -> Double {
            p < attack ? p / attack : pow(1 - (p - attack) / (1 - attack), 2)
        }
        let twoPi = 2 * Double.pi
        switch sound {
        case .coin:
            return tone(0.16) { t, p in
                let f = t < 0.05 ? 1320.0 : 1760.0
                return sin(twoPi * f * t) * 0.35 * env(p)
            }
        case .water:
            return tone(0.25) { t, p in sin(twoPi * (500 + 700 * p) * t) * 0.3 * env(p) }
        case .nearMiss:
            return tone(0.12) { t, p in sin(twoPi * 980 * t) * 0.25 * env(p, attack: 0.01) }
        case .crash:
            return tone(0.45) { t, p in sin(twoPi * 90 * t) * 0.4 * env(p, attack: 0.005) }
        case .bell:
            return tone(0.5) { t, p in
                (sin(twoPi * 2093 * t) + 0.5 * sin(twoPi * 3136 * t)) * 0.18 * env(p, attack: 0.005)
            }
        case .finish:
            return tone(0.7) { t, p in
                let f = p < 0.33 ? 784.0 : (p < 0.66 ? 988.0 : 1175.0)
                return sin(twoPi * f * t) * 0.3 * env(p)
            }
        case .star:
            return tone(0.22) { t, p in sin(twoPi * (1200 + 600 * p) * t) * 0.3 * env(p) }
        case .whoosh:
            return tone(0.25) { _, _ in 0 }
        case .penalty:
            return tone(0.35) { t, p in sin(twoPi * (330 - 120 * p) * t) * 0.3 * env(p) }
        case .boost:
            return tone(0.4) { t, p in sin(twoPi * (300 + 900 * p * p) * t) * 0.25 * env(p) }
        }
    }

    private func noiseAmount(_ sound: Sound, _ p: Double) -> Double {
        switch sound {
        case .crash: return 0.5 * pow(1 - p, 3)
        case .whoosh: return 0.18 * sin(Double.pi * p)
        default: return 0
        }
    }
}
