import SwiftUI
import AVFoundation
import Speech

// Voice conversation for Belajar Bahasa: listen (on-device speech recognition) → Apple Intelligence →
// speak the reply → listen again. The mic is closed while the reply plays, so it never hears itself.

final class VoiceChat: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    enum Phase { case idle, listening, thinking, speaking }
    @Published var phase = Phase.idle
    @Published var level: CGFloat = 0          // mic loudness 0…1, drives the orb
    @Published var heard = ""
    @Published var error: String?
    @Published var onDevice = true             // false: this language's recognizer sends audio to Apple
    var lang = Lang.en
    var voiceID: String?                       // chosen in Belajar Bahasa → ⚙︎
    var onUtterance: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private let synth = AVSpeechSynthesizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silence: Timer?

    override init() {
        super.init()
        synth.delegate = self
    }

    func start(_ lang: Lang) {
        self.lang = lang
        error = nil
        SFSpeechRecognizer.requestAuthorization { status in
            AVCaptureDevice.requestAccess(for: .audio) { mic in
                DispatchQueue.main.async {
                    guard status == .authorized, mic else {
                        self.error = tr("Izinkan Mikrofon dan Speech Recognition di System Settings → Privacy & Security")
                        return
                    }
                    self.listen()
                }
            }
        }
    }

    func stop() {
        stopListening()
        synth.stopSpeaking(at: .immediate)
        phase = .idle
    }

    /// Back to listening when a turn couldn't be sent.
    func resume() { if phase != .idle { listen() } }

    private func listen() {
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: lang.voice)), rec.isAvailable else {
            error = String(format: tr("Pengenal suara %@ belum tersedia di Mac ini"), lang.title)
            phase = .idle
            return
        }
        stopListening()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        onDevice = rec.supportsOnDeviceRecognition
        if onDevice { req.requiresOnDeviceRecognition = true } // audio stays on this Mac
        request = req
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buf, _ in
            self?.request?.append(buf)
            guard let ch = buf.floatChannelData?[0], buf.frameLength > 0 else { return }
            var sum: Float = 0
            for i in 0..<Int(buf.frameLength) { sum += ch[i] * ch[i] }
            let rms = CGFloat(sqrt(sum / Float(buf.frameLength)))
            DispatchQueue.main.async { self?.level = min(1, rms * 14) }
        }
        engine.prepare()
        do { try engine.start() } catch { self.error = tr("Mikrofon tidak bisa dipakai"); phase = .idle; return }
        heard = ""
        phase = .listening
        task = rec.recognitionTask(with: req) { [weak self] result, err in
            DispatchQueue.main.async {
                guard let self, self.phase == .listening else { return }
                if let result {
                    self.heard = result.bestTranscription.formattedString
                    // A pause of ~1.3 s ends the turn.
                    self.silence?.invalidate()
                    self.silence = .scheduledTimer(withTimeInterval: 1.3, repeats: false) { [weak self] _ in self?.finish() }
                } else if err != nil {
                    self.heard.isEmpty ? self.listen() : self.finish() // recognizer timed out on silence: keep going
                }
            }
        }
    }

    private func finish() {
        let text = heard.trimmingCharacters(in: .whitespaces)
        stopListening()
        guard !text.isEmpty else { listen(); return }
        phase = .thinking
        onUtterance?(text)
    }

    private func stopListening() {
        silence?.invalidate()
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        level = 0
    }

    func say(_ text: String) {
        guard phase != .idle else { return }
        phase = .speaking
        let u = AVSpeechUtterance(string: text)
        u.voice = voiceID.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? AVSpeechSynthesisVoice(language: lang.voice)
        u.rate = 0.47
        synth.speak(u)
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        DispatchQueue.main.async { if self.phase == .speaking { self.listen() } }
    }
}

/// The reply minus the Indonesian "✏️" correction line, which the target-language voice would mangle.
func spokenPart(_ reply: String) -> String {
    // Also skips the "(romaji)" line Japanese replies end with.
    reply.split(separator: "\n").filter { !$0.hasPrefix("✏️") && !$0.hasPrefix("(") }.joined(separator: " ").replacingOccurrences(of: "*", with: "")
}

struct Orb: View {
    let phase: VoiceChat.Phase
    let level: CGFloat

    var colors: [Color] {
        switch phase {
        case .listening: return [Color(hex: 0x34D399), Color(hex: 0x0EA5E9), Color(hex: 0x6366F1)]
        case .thinking: return [Color(hex: 0xC084FC), Color(hex: 0xEC4899), Color(hex: 0x6366F1)]
        case .speaking: return [Color(hex: 0x60A5FA), Color(hex: 0x6366F1), Color(hex: 0x22D3EE)]
        case .idle: return [Color(hex: 0x64748B), Color(hex: 0x334155), Color(hex: 0x475569)]
        }
    }

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let pulse: CGFloat = switch phase {
            case .listening: level
            case .speaking: 0.3 + 0.2 * CGFloat(sin(t * 7))
            case .thinking: 0.12 + 0.08 * CGFloat(sin(t * 3))
            case .idle: 0.04 * CGFloat(sin(t * 1.5))
            }
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: colors + [colors[0]], center: .center, angle: .degrees(t * 50)))
                    .blur(radius: 22)
                    .scaleEffect(1 + pulse * 0.45)
                    .opacity(0.85)
                Circle()
                    .fill(AngularGradient(colors: colors.reversed() + [colors[2]], center: .center, angle: .degrees(-t * 70)))
                    .overlay(Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 45)))
                    .scaleEffect(0.78 + pulse * 0.22)
                    .shadow(color: colors[0].opacity(0.6), radius: 14)
            }
            .animation(.easeOut(duration: 0.12), value: level)
        }
    }
}
