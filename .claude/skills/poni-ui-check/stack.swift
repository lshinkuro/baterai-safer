import AppKit
// Stacks PNGs vertically into one image (to review several screens at once).
let files = Array(CommandLine.arguments.dropFirst(2))
let imgs = files.compactMap { NSImage(contentsOfFile: $0) }
let w = imgs.map(\.size.width).max()!, h = imgs.map(\.size.height).reduce(0, +) + CGFloat(imgs.count) * 6
let out = NSImage(size: NSSize(width: w, height: h), flipped: true) { _ in
    NSColor.darkGray.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
    var y: CGFloat = 0
    for i in imgs { i.draw(in: NSRect(x: 0, y: y, width: i.size.width, height: i.size.height)); y += i.size.height + 6 }
    return true
}
let rep = NSBitmapImageRep(data: out.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
