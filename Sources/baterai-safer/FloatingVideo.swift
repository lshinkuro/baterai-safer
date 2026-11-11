import AppKit
import WebKit

/// The 11-character video id in a youtube.com/watch, youtu.be, /shorts, /embed or /live link.
func youtubeID(_ link: String) -> String? {
    guard let u = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)), var host = u.host?.lowercased() else { return nil }
    for p in ["www.", "m.", "music."] where host.hasPrefix(p) { host.removeFirst(p.count) }
    let path = u.path.split(separator: "/").map(String.init)
    var id: String?
    if host == "youtu.be" { id = path.first }
    if host == "youtube.com" {
        id = path.first == "watch" ? u.queryItems?.first { $0.name == "v" }?.value
            : ["shorts", "embed", "live"].contains(path.first ?? "") && path.count > 1 ? path[1] : nil
    }
    return id.flatMap { $0.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil ? $0 : nil }
}

/// A YouTube video in a small always-on-top window, picked up from the browser tab that was playing it.
final class FloatingVideo: NSObject, NSWindowDelegate {
    static let shared = FloatingVideo()
    private var panel: NSPanel?
    private var web: WKWebView?
    var isOpen: Bool { panel != nil }

    /// URL of the browser tab playing `title` (YouTube puts the video title in the tab title), else the front tab.
    /// Safari names it `name`/`current tab`; Chrome, Arc, Dia, Brave and Edge use `title`/`active tab`.
    static func tabURL(browser: String, title: String) -> String? {
        let safari = browser == "com.apple.Safari"
        let t = String(title.prefix(40)).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let src = """
        tell application id "\(browser)"
            repeat with w in windows
                repeat with x in tabs of w
                    if (URL of x) contains "youtu" and (\(safari ? "name" : "title") of x) contains "\(t)" then return URL of x
                end repeat
            end repeat
            return URL of \(safari ? "current tab" : "active tab") of front window
        end tell
        """
        var err: NSDictionary?
        return NSAppleScript(source: src)?.executeAndReturnError(&err).stringValue
    }

    func open(_ id: String, start: Int) {
        let c = WKWebViewConfiguration()
        c.mediaTypesRequiringUserActionForPlayback = []
        let w = WKWebView(frame: .zero, configuration: c)
        // The embed refuses to play without a referrer (YouTube error 153), so it sits in a page with a base URL.
        w.loadHTMLString("""
        <html><body style="margin:0;background:#000;overflow:hidden">
        <iframe src="https://www.youtube.com/embed/\(id)?autoplay=1&playsinline=1&start=\(start)" style="border:0;width:100vw;height:100vh"
          allow="autoplay; encrypted-media; fullscreen; picture-in-picture" referrerpolicy="strict-origin-when-cross-origin"></iframe>
        </body></html>
        """, baseURL: URL(string: "https://github.com/lshinkuro/poni"))
        panel?.close()
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
                        styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentAspectRatio = NSSize(width: 16, height: 9)
        p.minSize = NSSize(width: 256, height: 144)
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.backgroundColor = .black
        p.contentView = w
        p.delegate = self
        if let s = NSScreen.main?.visibleFrame { p.setFrameOrigin(NSPoint(x: s.maxX - 500, y: s.minY + 20)) }
        p.orderFrontRegardless()
        panel = p
        web = w
    }

    func close() { panel?.close() }

    func windowWillClose(_ notification: Notification) {
        web?.loadHTMLString("", baseURL: nil) // stops the sound now, not when the view is freed
        web = nil
        panel = nil
    }
}
