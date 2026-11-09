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

/// What the charge alert says: the user's own text if they wrote one.
func fullChargeMessage(percent: Int, own: String = UserDefaults.standard.string(forKey: "fullChargeMessage") ?? "") -> String {
    let text = own.trimmingCharacters(in: .whitespaces)
    return text.isEmpty ? "Baterai \(percent)% · boleh cabut charger" : text
}

// MARK: Mic and speaker mute (system-wide: mutes the default device itself, so every app goes quiet)

struct AudioSwitch {
    static let mic = AudioSwitch(scope: kAudioDevicePropertyScopeInput, defaultDevice: kAudioHardwarePropertyDefaultInputDevice, savedVolume: "micVolume")
    static let speaker = AudioSwitch(scope: kAudioDevicePropertyScopeOutput, defaultDevice: kAudioHardwarePropertyDefaultOutputDevice, savedVolume: "speakerVolume")

    let scope: AudioObjectPropertyScope, defaultDevice: AudioObjectPropertySelector, savedVolume: String

    private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    var device: AudioDeviceID? {
        var id = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: defaultDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    private func canMute(_ d: AudioDeviceID) -> Bool {
        var mute = address(kAudioDevicePropertyMute), settable = DarwinBoolean(false)
        return AudioObjectHasProperty(d, &mute) && AudioObjectIsPropertySettable(d, &mute, &settable) == noErr && settable.boolValue
    }

    var muted: Bool {
        guard let d = device else { return false }
        if canMute(d) {
            var mute = address(kAudioDevicePropertyMute), v = UInt32(0), size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(d, &mute, 0, nil, &size, &v)
            return v != 0
        }
        var volume = address(kAudioDevicePropertyVolumeScalar), v = Float32(1), size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(d, &volume, 0, nil, &size, &v)
        return v == 0
    }

    /// Uses the device's mute switch; devices without one get their volume zeroed (and restored).
    @discardableResult
    func set(_ on: Bool) -> Bool {
        guard let d = device else { return false }
        if canMute(d) {
            var mute = address(kAudioDevicePropertyMute), v: UInt32 = on ? 1 : 0
            return AudioObjectSetPropertyData(d, &mute, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
        }
        var volume = address(kAudioDevicePropertyVolumeScalar), v = Float32(0), size = UInt32(MemoryLayout<Float32>.size)
        if on {
            AudioObjectGetPropertyData(d, &volume, 0, nil, &size, &v)
            if v > 0 { UserDefaults.standard.set(v, forKey: savedVolume) }
            v = 0
        } else {
            v = UserDefaults.standard.object(forKey: savedVolume) as? Float32 ?? 0.75
        }
        return AudioObjectSetPropertyData(d, &volume, 0, nil, size, &v) == noErr
    }

    func toggle() -> Bool? { let on = !muted; return set(on) ? on : nil }
}

// MARK: Camera mirror

final class CameraBox: ObservableObject {
    let session = AVCaptureSession()
    @Published var denied = false
    @Published var aspect: CGFloat = 16 / 9 // of the camera's actual picture
    private var configured = false

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async {
                self.denied = !ok
                guard ok else { return }
                if !self.configured, let cam = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: cam),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                    if self.session.canSetSessionPreset(.hd1920x1080) { self.session.sessionPreset = .hd1920x1080 }
                    let d = CMVideoFormatDescriptionGetDimensions(cam.activeFormat.formatDescription)
                    if d.height > 0 { self.aspect = CGFloat(d.width) / CGFloat(d.height) }
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
        layer.videoGravity = .resizeAspect
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

    /// nil clears the whole history.
    static func remove(_ h: String?) {
        UserDefaults.standard.set(h.map { h in recent.filter { $0 != h } } ?? [], forKey: key)
    }
}

extension Color {
    init?(hexString s: String) {
        guard s.hasPrefix("#"), s.count == 7, let v = UInt32(s.dropFirst(), radix: 16) else { return nil }
        self.init(hex: v)
    }
}

// MARK: Downloads

/// Names in `now` that weren't in `old`, skipping hidden files and browsers' in-progress files.
func newDownloads(old: Set<String>, now: [String]) -> [String] {
    let partial = ["crdownload", "download", "part", "tmp", "partial", "opdownload"]
    return now.filter { !old.contains($0) && !$0.hasPrefix(".") && !partial.contains(($0 as NSString).pathExtension.lowercased()) }
}

final class Downloads: ObservableObject {
    static let shared = Downloads()
    static let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    @Published var recent: [URL] = []
    private var source: DispatchSourceFileSystemObject?
    private var known = Set<String>()

    var names: [String] { (try? FileManager.default.contentsOfDirectory(atPath: Self.dir.path)) ?? [] }

    /// Watches the Downloads folder itself; a browser finishing a file renames or adds an entry there.
    func start() {
        guard source == nil else { return }
        let fd = open(Self.dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        known = Set(names)
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        s.setEventHandler { [weak self] in self?.scan() }
        s.setCancelHandler { close(fd) }
        s.resume()
        source = s
    }

    func stop() { source?.cancel(); source = nil }

    private func scan() {
        let now = names
        let fresh = newDownloads(old: known, now: now)
        known = Set(now)
        guard let name = fresh.last else { return }
        recent = Array((fresh.map { Self.dir.appendingPathComponent($0) } + recent).prefix(6))
        Notch.shared.flash("\(name) selesai diunduh")
    }
}

// MARK: Removable drives

final class Volumes: ObservableObject {
    static let shared = Volumes()
    @Published var list: [URL] = []
    private var observers: [Any] = []

    func start() {
        guard observers.isEmpty else { return }
        refresh()
        let nc = NSWorkspace.shared.notificationCenter
        observers = [
            nc.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] n in
                self?.refresh()
                if let url = n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL, self?.list.contains(where: { $0.path == url.path }) == true {
                    Notch.shared.flash("\(url.lastPathComponent) terpasang · eject dari Lainnya")
                }
            },
            nc.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() },
        ]
    }

    func refresh() {
        let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsInternalKey]
        list = (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []).filter {
            let v = try? $0.resourceValues(forKeys: Set(keys))
            return v?.volumeIsEjectable == true && v?.volumeIsInternal != true
        }
    }

    func eject(_ url: URL) {
        let name = url.lastPathComponent
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                DispatchQueue.main.async { self.refresh(); Notch.shared.flash("\(name) aman dicabut") }
            } catch {
                DispatchQueue.main.async { Notch.shared.flash("Gagal eject \(name): sedang dipakai") }
            }
        }
    }
}

// MARK: Views

struct MoreView: View {
    @AppStorage("morePage") private var page = ""
    @AppStorage("fullChargeAlert") private var fullCharge = true
    @AppStorage("fullChargeMessage") private var chargeMessage = ""
    @Local private var colors = ColorPick.recent
    @Local private var hoveredColor: String?
    @StateObject private var camera = CameraBox()
    @ObservedObject private var tools = ToolsModel.shared
    @ObservedObject private var downloads = Downloads.shared
    @ObservedObject private var volumes = Volumes.shared
    @AppStorage("downloadAlert") private var downloadAlert = false
    @Local private var until = Date().addingTimeInterval(3600)

    static let tools: [(id: String, icon: String, title: String, subtitle: String, color: Color)] = [
        ("charge", "battery.100percent.bolt", "Notif baterai penuh", "Kabari saat sampai batas", Palette.green),
        ("camera", "camera.fill", "Kamera cermin", "Cek penampilan sebelum rapat", Palette.accent),
        ("color", "eyedropper", "Pemilih warna", "Ambil warna dari layar", Palette.accent),
        ("awake", "cup.and.saucer.fill", "Tetap menyala", "Cegah Mac tidur sementara", Palette.amber),
        ("downloads", "arrow.down.circle.fill", "Download", "Kabari saat download selesai", Palette.accent),
        ("drives", "eject.fill", "Lepas USB", "Lepas flashdisk dengan aman", Palette.accent),
        ("lang", "character.book.closed.fill", "Belajar Bahasa", "Kuis & ngobrol dengan AI", Palette.accent),
        ("games", "gamecontroller.fill", "Gabut", "Ular, kartu, X-O, kata, catur", Palette.accent),
        ("selfcare", "heart.circle", "Self-care", "Skor harian, istirahat terpandu, mood, kebiasaan", Palette.accent),
        ("update", "arrow.down.circle.fill", "Pembaruan", "Cek dan pasang versi baru", Palette.accent),
    ]

    var body: some View {
        if let tool = Self.tools.first(where: { $0.id == page }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    NButton(icon: "chevron.left", title: "Lainnya") { withAnimation(Motion.ease) { page = "" } }
                    Text(tool.title).font(.system(size: 13, weight: .bold))
                }
                Group {
                    switch tool.id {
                    case "charge": chargePage
                    case "camera": cameraPage
                    case "awake": awakePage
                    case "downloads": downloadsPage
                    case "drives": drivesPage
                    case "lang": LangPage()
                    case "games": GamesPage()
                    case "selfcare": SelfCareView()
                    case "update": NotchUpdatePage()
                    default: colorPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .transition(.opacity)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                // The camera opens from the switches at the top of the island.
                ForEach(Self.tools.filter { $0.id != "camera" }, id: \.id) { t in
                    Button { withAnimation(Motion.ease) { page = t.id } } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: t.icon).font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                                .frame(width: 36, height: 36).background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text(tr(t.title)).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                            Text(tr(t.subtitle)).font(.system(size: 11)).foregroundStyle(.gray).lineLimit(2, reservesSpace: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
                        .padding(12)
                        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.07), lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    var awakePage: some View {
        HStack(spacing: 14) {
            NCard {
                VStack(spacing: 10) {
                    Image(systemName: tools.awake ? "cup.and.saucer.fill" : "moon.zzz.fill").font(.system(size: 30, weight: .bold))
                        .foregroundStyle(tools.awake ? Palette.amber : .gray)
                    Text(tools.awake ? (tools.awakeUntil.map { "Menyala sampai \($0.formatted(date: .omitted, time: .shortened))" } ?? "Menyala sampai dimatikan")
                         : "Mac boleh tidur seperti biasa").font(.system(size: 12, weight: .bold)).multilineTextAlignment(.center)
                    if tools.awake { NButton(icon: "stop.fill", title: "Matikan", tint: Palette.red) { tools.awake = false } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 220)
            NCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("CEGAH SLEEP SELAMA").font(.system(size: 10, weight: .bold)).foregroundStyle(.gray)
                    HStack(spacing: 6) {
                        NButton(icon: "timer", title: "30 menit", tint: Palette.amber) { tools.keepAwake(minutes: 30) }
                        NButton(icon: "timer", title: "1 jam", tint: Palette.amber) { tools.keepAwake(minutes: 60) }
                        NButton(icon: "timer", title: "2 jam", tint: Palette.amber) { tools.keepAwake(minutes: 120) }
                    }
                    HStack(spacing: 6) {
                        DatePicker("", selection: $until, displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
                        NButton(icon: "clock", title: "Sampai jam ini", tint: Palette.amber) {
                            // A time already past today means tomorrow.
                            let d = until > Date() ? until : until.addingTimeInterval(86400)
                            tools.keepAwake(until: d)
                        }
                    }
                    NButton(icon: "infinity", title: "Sampai dimatikan", tint: Palette.amber) { tools.keepAwake() }
                    Spacer(minLength: 0)
                    Text("Mati otomatis, jadi tidak lupa.").font(.system(size: 10)).foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    var downloadsPage: some View {
        NCard {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Kabari saat download selesai", isOn: $downloadAlert).toggleStyle(.switch).controlSize(.small)
                    .font(.system(size: 12, weight: .semibold))
                    .onChange(of: downloadAlert) { on in on ? downloads.start() : downloads.stop() }
                if downloads.recent.isEmpty {
                    Text(downloadAlert ? "Download berikutnya muncul di sini." : "Nyalakan untuk memantau folder Downloads (macOS akan minta izin sekali).")
                        .font(.system(size: 11)).foregroundStyle(.gray)
                }
                ForEach(downloads.recent, id: \.self) { url in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 22, height: 22)
                        Text(url.lastPathComponent).font(.system(size: 11)).lineLimit(1)
                        Spacer()
                        NButton(icon: "magnifyingglass", title: "Tampilkan") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    var drivesPage: some View {
        NCard {
            VStack(alignment: .leading, spacing: 8) {
                if volumes.list.isEmpty {
                    Placeholder(icon: "externaldrive.fill", title: "Tidak ada drive eksternal", subtitle: "Colok flashdisk atau hard disk, lalu eject dari sini")
                }
                ForEach(volumes.list, id: \.self) { url in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 26, height: 26)
                        Text(url.lastPathComponent).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Spacer()
                        NButton(icon: "eject.fill", title: "Lepas", tint: Palette.accent, prominent: true) { volumes.eject(url) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear { volumes.refresh() }
        }
    }

    var chargePage: some View {
        let limit = load(Paths.config, Config()).limit
        return NCard {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Kabari saat baterai mencapai batas", isOn: $fullCharge).toggleStyle(.switch).controlSize(.small)
                    .font(.system(size: 12, weight: .semibold))
                Text("Saat charger tercolok dan baterai mencapai \(limit)%, notch menampilkan pesan di bawah. Batasnya mengikuti pengaturan di tab Baterai.")
                    .font(.system(size: 11)).foregroundStyle(.gray)
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble").foregroundStyle(.gray)
                    TextField(fullChargeMessage(percent: limit, own: ""), text: $chargeMessage).textFieldStyle(.plain)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.white.opacity(0.09), in: Capsule())
                Spacer()
                NButton(icon: "bell.fill", title: "Coba notifikasi", tint: Palette.green, prominent: true) { Notch.shared.flash(fullChargeMessage(percent: limit)) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    var cameraPage: some View {
        ZStack {
            if camera.denied {
                Placeholder(icon: "camera.fill", title: "Izin kamera ditolak", subtitle: "System Settings → Privacy & Security → Camera")
            } else {
                // Whole picture at the camera's own shape, not cropped to the wide notch.
                CameraPreview(session: camera.session)
                    .aspectRatio(camera.aspect, contentMode: .fit)
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
                    Image(systemName: "eyedropper.halffull").font(.system(size: 26, weight: .bold)).foregroundStyle(Palette.accent)
                    NButton(icon: "eyedropper", title: "Ambil warna", tint: Palette.accent, prominent: true) {
                        ColorPick.pick { h in
                            colors = ColorPick.recent
                            if let h { Notch.shared.flash("\(h) disalin") }
                        }
                    }
                    Text("Kode hex langsung tersalin").font(.system(size: 11)).foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 200)
            NCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("TERAKHIR").font(.system(size: 10, weight: .bold)).foregroundStyle(.gray)
                        Spacer()
                        if !colors.isEmpty {
                            Button("Hapus semua") { ColorPick.remove(nil); colors = [] }
                                .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(.gray)
                        }
                    }
                    if colors.isEmpty {
                        Text("Belum ada warna").font(.system(size: 11)).foregroundStyle(.gray)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(colors, id: \.self) { h in
                            Button { copyText(h); Notch.shared.flash("\(h) disalin") } label: {
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 10).fill(Color(hexString: h) ?? .gray).frame(height: 34)
                                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.15)))
                                    Text(h).font(.system(size: 10, design: .monospaced))
                                }
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .topTrailing) {
                                if hoveredColor == h {
                                    Button { ColorPick.remove(h); colors = ColorPick.recent } label: {
                                        Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                                    }
                                    .buttonStyle(.plain).foregroundStyle(.white, .black.opacity(0.6)).offset(x: 5, y: -5).tip("Hapus \(h)")
                                }
                            }
                            .onHover { hoveredColor = $0 ? h : (hoveredColor == h ? nil : hoveredColor) }
                            .contextMenu { Button("Hapus") { ColorPick.remove(h); colors = ColorPick.recent } }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}
