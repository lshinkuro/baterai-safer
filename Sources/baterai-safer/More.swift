import SwiftUI
import AVFoundation
import CoreAudio

// "Lainnya" tab: a grid of smaller tools; picking one swaps in its page (full notch size) with a back button.

/// Fires once each time the battery reaches `target` while plugged in; re-arms after it drops 2% or unplugs.
struct FullChargeAlert {
    private var fired = false

    mutating func step(percent: Int, ac: Bool, target: Int) -> Bool {
        if !ac || percent < target - 2 { fired = false; return false }
        guard percent >= target, !fired else { return false }
        fired = true
        return true
    }
}

// MARK: Mic mute (system-wide: mutes the default input device itself, so every meeting app goes quiet)

enum Mic {
    private static var mute = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    private static var volume = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    private static let savedVolume = "micVolume"

    static var device: AudioDeviceID? {
        var id = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    private static func canMute(_ d: AudioDeviceID) -> Bool {
        var settable = DarwinBoolean(false)
        return AudioObjectHasProperty(d, &mute) && AudioObjectIsPropertySettable(d, &mute, &settable) == noErr && settable.boolValue
    }

    static var muted: Bool {
        guard let d = device else { return false }
        if canMute(d) {
            var v = UInt32(0), size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(d, &mute, 0, nil, &size, &v)
            return v != 0
        }
        var v = Float32(1), size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(d, &volume, 0, nil, &size, &v)
        return v == 0
    }

    /// Uses the device's mute switch; mics without one get their input volume zeroed (and restored).
    @discardableResult
    static func set(_ on: Bool) -> Bool {
        guard let d = device else { return false }
        if canMute(d) {
            var v: UInt32 = on ? 1 : 0
            return AudioObjectSetPropertyData(d, &mute, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
        }
        var v = Float32(0), size = UInt32(MemoryLayout<Float32>.size)
        if on {
            AudioObjectGetPropertyData(d, &volume, 0, nil, &size, &v)
            if v > 0 { UserDefaults.standard.set(v, forKey: savedVolume) }
            v = 0
        } else {
            v = UserDefaults.standard.object(forKey: savedVolume) as? Float32 ?? 0.75
        }
        return AudioObjectSetPropertyData(d, &volume, 0, nil, size, &v) == noErr
    }

    static func toggle() -> Bool? { let on = !muted; return set(on) ? on : nil }
}

// MARK: Camera mirror

final class CameraBox: ObservableObject {
    let session = AVCaptureSession()
    @Published var denied = false
    private var configured = false

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async {
                self.denied = !ok
                guard ok else { return }
                if !self.configured, let cam = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: cam),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.configured = true
                }
                DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
            }
        }
    }

    // The camera light goes off as soon as the page closes.
    func stop() { DispatchQueue.global(qos: .userInitiated).async { self.session.stopRunning() } }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let c = layer.connection, c.isVideoMirroringSupported {
            c.automaticallyAdjustsVideoMirroring = false
            c.isVideoMirrored = true
        }
        v.layer = layer
        v.wantsLayer = true
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {}
}

// MARK: Color picker

enum ColorPick {
    static let key = "pickedColors"
    static var recent: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func hex(_ c: NSColor) -> String? {
        guard let s = c.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int((s.redComponent * 255).rounded()), Int((s.greenComponent * 255).rounded()), Int((s.blueComponent * 255).rounded()))
    }

    /// System magnifier picker (no screen-recording permission); the hex lands on the clipboard.
    static func pick(done: @escaping (String?) -> Void) {
        NSColorSampler().show { c in
            guard let c, let h = hex(c) else { done(nil); return }
            copyText(h)
            UserDefaults.standard.set(Array(([h] + recent.filter { $0 != h }).prefix(8)), forKey: key)
            done(h)
        }
    }
}

extension Color {
    init?(hexString s: String) {
        guard s.hasPrefix("#"), s.count == 7, let v = UInt32(s.dropFirst(), radix: 16) else { return nil }
        self.init(hex: v)
    }
}

// MARK: Views

struct MoreView: View {
    @AppStorage("morePage") private var page = ""
    @AppStorage("fullChargeAlert") private var fullCharge = true
    @Local private var micMuted = Mic.muted
    @Local private var colors = ColorPick.recent
    @StateObject private var camera = CameraBox()

    static let tools: [(id: String, icon: String, title: String, subtitle: String, color: Color)] = [
        ("charge", "battery.100percent.bolt", "Notif baterai penuh", "Kabari saat sampai batas", Palette.green),
        ("mic", "mic.slash.fill", "Mic Mute", "Bisukan mic di semua aplikasi · ⌃⌥M", Palette.red),
        ("camera", "camera.fill", "Kamera cermin", "Cek penampilan sebelum rapat", Palette.sky),
        ("color", "eyedropper", "Color picker", "Ambil warna dari layar", Palette.pink),
    ]

    var body: some View {
        if let tool = Self.tools.first(where: { $0.id == page }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    NButton(icon: "chevron.left", title: "Lainnya") { withAnimation(.easeInOut(duration: 0.2)) { page = "" } }
                    Text(tool.title).font(.system(size: 13, weight: .bold))
                }
                Group {
                    switch tool.id {
                    case "charge": chargePage
                    case "mic": micPage
                    case "camera": cameraPage
                    default: colorPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .transition(.opacity)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(Self.tools, id: \.id) { t in
                    Button { withAnimation(.easeInOut(duration: 0.2)) { page = t.id } } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: t.icon).font(.system(size: 16, weight: .bold)).foregroundStyle(t.color)
                                .frame(width: 38, height: 38).background(t.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            Text(t.title).font(.system(size: 12.5, weight: .bold))
                            Text(t.subtitle).font(.system(size: 10.5)).foregroundStyle(.gray).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                        .padding(12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    var chargePage: some View {
        let limit = load(Paths.config, Config()).limit
        return NCard {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Kabari saat baterai mencapai batas", isOn: $fullCharge).toggleStyle(.switch).controlSize(.small)
                    .font(.system(size: 12.5, weight: .semibold))
                Text("Saat charger tercolok dan baterai mencapai \(limit)%, notch menampilkan \"Baterai \(limit)% · boleh cabut charger\". Batasnya mengikuti pengaturan di tab Baterai.")
                    .font(.system(size: 11)).foregroundStyle(.gray)
                Spacer()
                NButton(icon: "bell.fill", title: "Coba notifikasi", tint: Palette.green, prominent: true) { Notch.shared.flash("Baterai \(limit)% · boleh cabut charger") }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    var micPage: some View {
        let color = micMuted ? Palette.red : Palette.green
        return VStack(spacing: 12) {
            Button {
                if let on = Mic.toggle() { micMuted = on }
            } label: {
                Image(systemName: micMuted ? "mic.slash.fill" : "mic.fill").font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 96, height: 96).background(color.gradient, in: Circle()).shadow(color: color.opacity(0.6), radius: 16)
            }
            .buttonStyle(.plain)
            Text(micMuted ? "Mic dibisukan" : "Mic aktif").font(.system(size: 14, weight: .bold))
            Text(Mic.device == nil ? "Tidak ada mikrofon" : "Berlaku untuk semua aplikasi (Zoom, Meet, Teams). Shortcut ⌃⌥M.")
                .font(.system(size: 11)).foregroundStyle(.gray)
        }
        .onAppear { micMuted = Mic.muted }
    }

    var cameraPage: some View {
        ZStack {
            if camera.denied {
                Placeholder(icon: "camera.fill", title: "Izin kamera ditolak", subtitle: "System Settings → Privacy & Security → Camera", color: Palette.sky)
            } else {
                CameraPreview(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    var colorPage: some View {
        HStack(spacing: 14) {
            NCard {
                VStack(spacing: 10) {
                    Image(systemName: "eyedropper.halffull").font(.system(size: 26, weight: .bold)).foregroundStyle(Palette.pink)
                    NButton(icon: "eyedropper", title: "Ambil warna", tint: Palette.pink, prominent: true) {
                        ColorPick.pick { h in
                            colors = ColorPick.recent
                            if let h { Notch.shared.flash("\(h) disalin") }
                        }
                    }
                    Text("Kode hex langsung tersalin").font(.system(size: 10.5)).foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 200)
            NCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TERAKHIR").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.gray)
                    if colors.isEmpty {
                        Text("Belum ada warna").font(.system(size: 11)).foregroundStyle(.gray)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(colors, id: \.self) { h in
                            Button { copyText(h); Notch.shared.flash("\(h) disalin") } label: {
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 8).fill(Color(hexString: h) ?? .gray).frame(height: 34)
                                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.15)))
                                    Text(h).font(.system(size: 9.5, design: .monospaced))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}
