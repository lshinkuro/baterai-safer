import SwiftUI
import AVFoundation
import Speech

// Voice conversation for Belajar Bahasa: listen (on-device speech recognition) → Apple Intelligence →
// speak the reply → listen again. The mic is closed while the reply plays, so it never hears itself.

final class VoiceChat: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    enum Phase: Hashable { case idle, listening, thinking, speaking }
    @Published var phase = Phase.idle
    @Published var level: CGFloat = 0          // mic loudness 0…1, drives the face
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

/// The Poni logo, alive: tinted by phase, blinks, mouth moves while it speaks, eyes drift up while it thinks,
/// and the notch camera lights with the mic while it listens.
struct PoniFace: View {
    let phase: VoiceChat.Phase
    let level: CGFloat

    var tint: [Color] {
        switch phase {
        case .listening: [Color(hex: 0x5EEAD4), Color(hex: 0x818CF8)]
        case .thinking: [Color(hex: 0xC084FC), Color(hex: 0xEC4899)]
        case .speaking: [Color(hex: 0x22D3EE), Color(hex: 0x6366F1)]
        case .idle: [Color(hex: 0x94A3B8), Color(hex: 0x475569)]
        }
    }

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let blink = t.truncatingRemainder(dividingBy: 3.7) < 0.12
            let mouth: CGFloat = phase == .speaking ? 0.3 + 0.7 * abs(CGFloat(sin(t * 9))) : 0
            let look: CGFloat = phase == .thinking ? 1 : 0
            Canvas { g, size in
                let s = size.width, ink = Color.black.opacity(0.85)
                func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
                func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: (x - w / 2) * s, y: (y - h / 2) * s, width: w * s, height: h * s) }
                let body = Path(roundedRect: box(0.5, 0.5, 0.9, 0.9), cornerRadius: s * 0.2, style: .continuous)
                g.fill(body, with: .linearGradient(Gradient(colors: tint), startPoint: at(0.1, 0.05), endPoint: at(0.9, 0.95)))
                g.fill(Path(roundedRect: box(0.5, 0.08, 0.42, 0.16), cornerRadius: s * 0.05, style: .continuous), with: .color(ink))
                let cam = phase == .listening ? Palette.accent.opacity(0.5 + 0.5 * level) : Color.white.opacity(0.25)
                g.fill(Path(ellipseIn: box(0.5, 0.11, 0.045, 0.045)), with: .color(cam))
                let eyeY = 0.5 - look * 0.05
                for d in [-1.0, 1.0] as [CGFloat] {
                    g.fill(Path(ellipseIn: box(0.5 + d * 0.33, 0.6, 0.12, 0.07)), with: .color(Color(hex: 0xFB7185).opacity(0.45)))
                    let ex = 0.5 + d * 0.19 + look * 0.04, eh: CGFloat = blink ? 0.015 : 0.14
                    g.fill(Path(ellipseIn: box(ex, eyeY, 0.11, eh)), with: .color(ink))
                    if !blink { g.fill(Path(ellipseIn: box(ex - 0.025, eyeY - 0.04, 0.035, 0.035)), with: .color(.white)) }
                }
                if mouth > 0 {
                    g.fill(Path(ellipseIn: box(0.5, 0.7, 0.14, 0.12 * mouth)), with: .color(ink))
                } else {
                    var smile = Path()
                    smile.move(to: at(0.42, 0.66))
                    smile.addQuadCurve(to: at(0.58, 0.66), control: at(0.5, 0.76))
                    g.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))
                }
                if phase == .thinking {
                    for k in 0..<3 {
                        let on = (t * 2 + Double(k) * 0.33).truncatingRemainder(dividingBy: 1) < 0.5
                        g.fill(Path(ellipseIn: box(0.76 + CGFloat(k) * 0.09, 0.3, 0.05, 0.05)), with: .color(.white.opacity(on ? 0.95 : 0.35)))
                    }
                }
            }
            .shadow(color: tint[0].opacity(0.3 + 0.5 * (phase == .listening ? level : 0)), radius: 14)
            .scaleEffect(1 + 0.015 * CGFloat(sin(t * 1.6)))
            .animation(.easeOut(duration: 0.12), value: level)
        }
    }
}
