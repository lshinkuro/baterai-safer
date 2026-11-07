// Renders the Poni app icon: swift scripts/icon.swift out.png, then sips sizes + iconutil (see README).
import AppKit

// Poni app icon: a friendly face whose bangs ("poni") are the Mac notch.
let size = 1024.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
// Apple icon grid: 824pt squircle centred in 1024, with a soft drop shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: c(0x000000, 0.35))
ctx.addPath(squircle); ctx.setFillColor(c(0x34D399)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(squircle); ctx.clip()
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [c(0x5EEAD4), c(0x34D399), c(0x6366F1)] as CFArray, locations: [0, 0.45, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 160, y: 924), end: CGPoint(x: 900, y: 100), options: [])
// soft top highlight
let hl = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [c(0xFFFFFF, 0.28), c(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(hl, startCenter: CGPoint(x: 340, y: 860), startRadius: 0, endCenter: CGPoint(x: 340, y: 860), endRadius: 520, options: [])
// The notch: flush with the top edge, rounded at the bottom — the bangs.
let notch = CGMutablePath()
let nw = 420.0, nh = 170.0, nx = 512 - nw / 2, top = 924.0, r = 70.0
notch.move(to: CGPoint(x: nx - 30, y: top + 10))
notch.addLine(to: CGPoint(x: nx + nw + 30, y: top + 10))
notch.addQuadCurve(to: CGPoint(x: nx + nw, y: top - 30), control: CGPoint(x: nx + nw, y: top + 10))
notch.addLine(to: CGPoint(x: nx + nw, y: top - nh + r))
notch.addQuadCurve(to: CGPoint(x: nx + nw - r, y: top - nh), control: CGPoint(x: nx + nw, y: top - nh))
notch.addLine(to: CGPoint(x: nx + r, y: top - nh))
notch.addQuadCurve(to: CGPoint(x: nx, y: top - nh + r), control: CGPoint(x: nx, y: top - nh))
notch.addLine(to: CGPoint(x: nx, y: top - 30))
notch.addQuadCurve(to: CGPoint(x: nx - 30, y: top + 10), control: CGPoint(x: nx, y: top + 10))
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: c(0x0F172A, 0.45))
ctx.addPath(notch); ctx.setFillColor(c(0x0B0B0F)); ctx.fillPath()
ctx.restoreGState()
// tiny camera lens in the notch
ctx.setFillColor(c(0x1E293B)); ctx.fillEllipse(in: CGRect(x: 512 - 22, y: top - 95, width: 44, height: 44))
ctx.setFillColor(c(0x38BDF8, 0.85)); ctx.fillEllipse(in: CGRect(x: 512 - 9, y: top - 82, width: 18, height: 18))
// eyes
ctx.setFillColor(c(0x0B0B0F))
for x in [372.0, 652.0] { ctx.fillEllipse(in: CGRect(x: x - 42, y: 470, width: 84, height: 112)) }
ctx.setFillColor(c(0xFFFFFF))
for x in [386.0, 666.0] { ctx.fillEllipse(in: CGRect(x: x - 14, y: 538, width: 28, height: 30)) }
// cheeks
ctx.setFillColor(c(0xFB7185, 0.75))
for x in [270.0, 754.0] { ctx.fillEllipse(in: CGRect(x: x - 52, y: 400, width: 104, height: 60)) }
// smile
ctx.setStrokeColor(c(0x0B0B0F)); ctx.setLineWidth(30); ctx.setLineCap(.round)
ctx.addArc(center: CGPoint(x: 512, y: 430), radius: 92, startAngle: .pi * 1.18, endAngle: .pi * 1.82, clockwise: false)
ctx.strokePath()
ctx.restoreGState()
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
