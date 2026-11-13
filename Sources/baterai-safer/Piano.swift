import SwiftUI
import AVFoundation

// Piano in Gabut: two octaves played with the mouse or the keyboard (tracker layout: Z row lower octave, Q row upper).

final class Piano: ObservableObject {
    static let shared = Piano()
    // Lives here, not in the view: the key monitor holds a copy of the view from when the page opened.
    @Published var octave = UserDefaults.standard.object(forKey: "pianoOctave") as? Int ?? 4 {
        didSet { UserDefaults.standard.set(octave, forKey: "pianoOctave") }
    }
    @Published var held: Set<UInt8> = []
    private let engine = AVAudioEngine(), sampler = AVAudioUnitSampler()

    private init() {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        // macOS ships a General MIDI bank. Without it the sampler plays a plain tone.
        use(UInt8(UserDefaults.standard.integer(forKey: "pianoSound")))
    }

    /// General MIDI program numbers from the same bank.
    static let sounds: [(program: UInt8, title: String)] = [(0, "Klasik"), (4, "Elektrik"), (6, "Harpsichord"), (19, "Organ"), (11, "Vibrafon"), (10, "Kotak musik")]

    func use(_ program: UInt8) {
        let bank = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
        try? sampler.loadSoundBankInstrument(at: bank, program: program, bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(kAUSampler_DefaultBankLSB))
    }

    func down(_ note: UInt8) {
        if !engine.isRunning { try? engine.start() }
        sampler.startNote(note, withVelocity: 90, onChannel: 0)
    }

    func up(_ note: UInt8) { sampler.stopNote(note, onChannel: 0) }

    // The engine keeps the audio hardware busy, so it only runs while the page is open.
    func stop() { engine.stop() }
}

struct PianoPage: View {
    /// Labels for the 25 keys in order, and their keyCodes: Z S X D C V G B H N J M, then Q 2 W 3 E R 5 T 6 Y 7 U I.
    static let letters = "ZSXDCVGBHNJMQ2W3ER5T6Y7UI".map(String.init)
    static let typing: [UInt16: UInt8] = Dictionary(uniqueKeysWithValues: zip([6, 1, 7, 2, 8, 9, 5, 11, 4, 45, 38, 46, 12, 19, 13, 20, 14, 15, 23, 17, 22, 16, 26, 32, 34], 0...24))
    static let octaves = 1...6 // lowest C shown: C1…C6

    @AppStorage("pianoSound") private var sound = 0
    @ObservedObject private var piano = Piano.shared

    var octave: Int { piano.octave }
    var held: Set<UInt8> { piano.held }
    var low: UInt8 { UInt8((Piano.shared.octave + 1) * 12) }
    var whites: [UInt8] { (0..<15).map { low + [0, 2, 4, 5, 7, 9, 11][$0 % 7] + UInt8($0 / 7 * 12) } }
    @State private var monitors: [Any] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Piano.sounds, id: \.program) { s in
                    let on = sound == Int(s.program)
                    Button { sound = Int(s.program); Piano.shared.use(s.program) } label: {
                        Text(tr(s.title)).font(.system(size: 11, weight: on ? .bold : .medium))
                            .foregroundStyle(on ? Palette.onAccent : .white.opacity(0.8))
                            .padding(.horizontal, 10).frame(minHeight: 24)
                            .background(on ? AnyShapeStyle(Palette.accentFill) : AnyShapeStyle(Color.white.opacity(0.06)), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 8)
                shiftButton("chevron.left", -1)
                Text("C\(octave)–C\(octave + 2)").font(.system(size: 11, weight: .semibold)).monospacedDigit().frame(minWidth: 52)
                    .accessibilityLabel(String(format: tr("Oktaf %@"), "\(octave)"))
                shiftButton("chevron.right", 1)
            }
            keyboard
        }
        .onAppear(perform: listen)
        .onDisappear {
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
            Piano.shared.held.forEach(release)
            Piano.shared.stop()
        }
    }

    func shiftButton(_ icon: String, _ d: Int) -> some View {
        Button { shift(d) } label: {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 24)
                .background(Color.white.opacity(0.08), in: Circle()).contentShape(Circle())
        }
        .buttonStyle(.plain).disabled(!Self.octaves.contains(octave + d))
        .tip(d < 0 ? "Oktaf turun (←)" : "Oktaf naik (→)")
    }

    /// Moves the keys a whole octave; notes still sounding are let go so none get stuck.
    func shift(_ d: Int) {
        guard Self.octaves.contains(Piano.shared.octave + d) else { return }
        Piano.shared.held.forEach(release)
        withAnimation(Motion.snap) { Piano.shared.octave += d }
    }

    var keyboard: some View {
        GeometryReader { geo in
            let w = geo.size.width / CGFloat(whites.count), bw = w * 0.62
            ZStack(alignment: .topLeading) {
                HStack(spacing: 2) {
                    ForEach(whites, id: \.self) { n in key(n, black: false).frame(maxWidth: .infinity) }
                }
                ForEach(Array(whites.enumerated()), id: \.offset) { i, n in
                    // C, D, F, G and A have a black key on their right.
                    if [0, 2, 5, 7, 9].contains(Int(n) % 12), i < whites.count - 1 {
                        key(n + 1, black: true).frame(width: bw, height: geo.size.height * 0.6).offset(x: CGFloat(i + 1) * w - bw / 2)
                    }
                }
            }
        }
    }

    func key(_ n: UInt8, black: Bool) -> some View {
        let on = held.contains(n), shape = UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6, style: .continuous)
        let label = Self.letters[Int(n - low)]
        return shape.fill(on ? AnyShapeStyle(Palette.accentFill) : AnyShapeStyle(black ? Color(white: 0.12) : Color.white.opacity(0.92)))
            .overlay(shape.strokeBorder(.white.opacity(black ? 0.12 : 0), lineWidth: 1))
            .overlay(alignment: .bottom) {
                VStack(spacing: 1) {
                    Text(label).font(.system(size: 9, weight: .semibold)).opacity(0.6)
                    if n % 12 == 0 { Text("C\(n / 12 - 1)").font(.system(size: 9, weight: .bold)) }
                }
                .foregroundStyle(black || on ? Color.white : Color.black.opacity(0.7)).padding(.bottom, 5)
            }
            .contentShape(shape)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !held.contains(n) { press(n) } }
                .onEnded { _ in release(n) })
            .accessibilityElement().accessibilityLabel("C C# D D# E F F# G G# A A# B".split(separator: " ")[Int(n % 12)] + "\(n / 12 - 1)")
            .accessibilityAddTraits(.isButton).accessibilityAction { press(n); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { release(n) } }
    }

    func press(_ n: UInt8) { Piano.shared.held.insert(n); Piano.shared.down(n) }
    func release(_ n: UInt8) { Piano.shared.held.remove(n); Piano.shared.up(n) }

    func listen() {
        // Letters only reach the page while the island is the key window.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0 is NotchPanel }?.makeKey()
        monitors = [NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard e.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return e }
            if e.keyCode == 123 || e.keyCode == 124 { shift(e.keyCode == 123 ? -1 : 1); return nil } // ← →
            guard let i = Self.typing[e.keyCode] else { return e }
            if !e.isARepeat { press(low + i) }
            return nil
        },
        NSEvent.addLocalMonitorForEvents(matching: .keyUp) { e in
            guard let i = Self.typing[e.keyCode] else { return e }
            release(low + i)
            return nil
        }].compactMap { $0 }
    }
}
