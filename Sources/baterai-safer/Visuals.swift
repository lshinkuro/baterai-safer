import SwiftUI
import WebKit

// AI → Visual: diagrams, charts, flowcharts, icons and animations the AI draws as SVG, self-contained
// HTML or Lottie JSON, previewed in the chat and saved as PNG / SVG / HTML / JSON.

struct Visual: Equatable {
    enum Kind: String { case svg, html, lottie }
    let kind: Kind
    let code: String

    var ext: String { kind == .lottie ? "json" : kind.rawValue }

    /// Bundled lottie-web light player (SVG renderer, no expressions); nil outside the .app.
    static let lottiePlayer = Bundle.main.url(forResource: "lottie_light.min", withExtension: "js").flatMap { try? String(contentsOf: $0, encoding: .utf8) }

    /// The page shown in the preview and opened in the browser, on a white canvas.
    var page: String {
        let head = """
        <!doctype html><meta charset="utf-8"><style>html,body{margin:0;height:100%;background:#fff}\
        body{display:flex;align-items:center;justify-content:center}svg{max-width:100%;max-height:100%;height:auto}\
        #a{width:100%;height:100%}</style>
        """
        switch kind {
        case .html: return code
        case .svg: return head + code
        case .lottie:
            guard let player = Self.lottiePlayer else { return head + "<p style=\"font:13px -apple-system\">Lottie preview needs Poni.app</p>" }
            // JSON is a JS literal; only a "</" could close the script tag early.
            let data = code.replacingOccurrences(of: "</", with: "<\\/")
            return head + "<div id=a></div><script>\(player)</script><script>lottie.loadAnimation({container:document.getElementById('a'),renderer:'svg',loop:true,autoplay:true,animationData:\(data)})</script>"
        }
    }

    /// Source file contents; a standalone .svg needs the namespace, which inline SVG often omits.
    var file: String {
        guard kind == .svg, !code.contains("xmlns=") else { return code }
        return code.replacingOccurrences(of: "<svg", with: "<svg xmlns=\"http://www.w3.org/2000/svg\"", options: .caseInsensitive, range: code.range(of: "<svg", options: .caseInsensitive))
    }
}

/// Splits an AI answer into prose and the first drawable block: a ```svg / ```html / ```xml fence,
/// an unlabeled fence holding <svg> or a page, or a bare <svg>…</svg>.
func extractVisual(_ answer: String) -> (text: String, visual: Visual?) {
    let ns = answer as NSString
    let fence = try! NSRegularExpression(pattern: "```([A-Za-z]*)[ \\t]*\\n([\\s\\S]*?)```")
    for m in fence.matches(in: answer, range: NSRange(location: 0, length: ns.length)) {
        let lang = ns.substring(with: m.range(at: 1)).lowercased()
        let body = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = body.lowercased()
        let kind: Visual.Kind? = isLottie(body) ? .lottie
            : lang == "html" || lower.hasPrefix("<!doctype") || lower.contains("<html") || lower.contains("<script") ? .html
            : ["svg", "xml", ""].contains(lang) && lower.contains("<svg") ? .svg : nil
        guard let kind else { continue }
        let text = ns.replacingCharacters(in: m.range, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (text, Visual(kind: kind, code: body))
    }
    if let r = answer.range(of: "<svg[\\s\\S]*?</svg>", options: [.regularExpression, .caseInsensitive]) {
        var text = answer
        text.removeSubrange(r)
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), Visual(kind: .svg, code: String(answer[r])))
    }
    return (answer, nil)
}

/// Bodymovin JSON: an object with layers and a frame rate or version.
func isLottie(_ s: String) -> Bool {
    guard s.hasPrefix("{"), let o = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] else { return false }
    return o["layers"] is [Any] && (o["fr"] != nil || o["v"] != nil)
}

/// Writes into ~/Downloads without overwriting anything (poni-visual.png, poni-visual-2.png, …).
func saveToDownloads(_ data: Data, ext: String) -> URL? {
    let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    var url = dir.appendingPathComponent("poni-visual.\(ext)"), n = 1
    while FileManager.default.fileExists(atPath: url.path) { n += 1; url = dir.appendingPathComponent("poni-visual-\(n).\(ext)") }
    do { try data.write(to: url); return url } catch { return nil }
}

final class WebBox: NSObject, ObservableObject, WKNavigationDelegate {
    weak var web: WKWebView?

    func png(_ done: @escaping (Data?) -> Void) {
        guard let web else { done(nil); return }
        web.takeSnapshot(with: nil) { img, _ in
            done(img?.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) })
        }
    }

    // Generated pages can't navigate the preview away; their links open in the browser.
    func webView(_ w: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.navigationType == .linkActivated, let url = action.request.url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
}

struct WebPreview: NSViewRepresentable {
    let html: String
    let box: WebBox

    func makeNSView(context: Context) -> WKWebView {
        let w = WKWebView()
        w.navigationDelegate = box
        box.web = w
        w.loadHTMLString(html, baseURL: nil)
        return w
    }

    func updateNSView(_ w: WKWebView, context: Context) {}
}

struct VisualCard: View {
    let v: Visual
    @StateObject private var box = WebBox()

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            WebPreview(html: v.page, box: box)
                .frame(height: 200)
                .clipShape(shape)
                .overlay(shape.strokeBorder(.white.opacity(0.07), lineWidth: 1))
            HStack(spacing: 6) {
                NButton(icon: "arrow.down.circle", title: "PNG", tint: Palette.accent, prominent: true) {
                    box.png { data in saved(data.flatMap { saveToDownloads($0, ext: "png") }) }
                }
                NButton(icon: "chevron.left.forwardslash.chevron.right", title: v.ext.uppercased()) {
                    saved(saveToDownloads(Data(v.file.utf8), ext: v.ext))
                }
                NButton(icon: "safari") { openInBrowser() }.tip("Buka di browser")
                NButton(icon: "doc.on.doc") { copyText(v.file); Notch.shared.flash("Kode disalin") }.tip("Salin kode")
            }
        }
    }

    func saved(_ url: URL?) {
        Notch.shared.flash(url.map { String(format: tr("Disimpan ke Downloads · %@"), $0.lastPathComponent) } ?? tr("Gagal menyimpan"))
    }

    func openInBrowser() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poni-visual-\(UUID().uuidString.prefix(8)).html")
        guard (try? Data(v.page.utf8).write(to: url)) != nil else { return }
        NSWorkspace.shared.open(url)
    }
}
