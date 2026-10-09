// Renders the ChatBar app icon (1024x1024 PNG) with CoreGraphics.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

/// Rounded-rect speech bubble with a tail at the bottom-left or bottom-right.
func bubble(_ r: CGRect, radius: CGFloat, tailLeft: Bool) -> CGPath {
    let p = CGMutablePath()
    p.addRoundedRect(in: r, cornerWidth: radius, cornerHeight: radius)
    let tw = r.width * 0.16, th = r.height * 0.24
    let x = tailLeft ? r.minX + r.width * 0.16 : r.maxX - r.width * 0.16
    let dir: CGFloat = tailLeft ? -1 : 1
    p.move(to: CGPoint(x: x - tw / 2, y: r.minY + 2))
    p.addLine(to: CGPoint(x: x + dir * tw * 0.55, y: r.minY - th))
    p.addLine(to: CGPoint(x: x + tw / 2, y: r.minY + 2))
    p.closeSubpath()
    return p
}

// macOS-style squircle tile, inset per Apple's icon grid (824 of 1024).
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil))
ctx.setFillColor(rgb(0x1E2230))
ctx.fillPath()
ctx.restoreGState()

// Back bubble (warm) and front bubble (light), overlapping: many chats, one place.
let back = CGRect(x: 214, y: 470, width: 470, height: 330)
ctx.addPath(bubble(back, radius: 110, tailLeft: true))
ctx.setFillColor(rgb(0xE07A52))
ctx.fillPath()

let front = CGRect(x: 360, y: 250, width: 450, height: 320)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: rgb(0x000000, 0.35))
ctx.addPath(bubble(front, radius: 106, tailLeft: false))
ctx.setFillColor(rgb(0xF4F1EA))
ctx.fillPath()
ctx.restoreGState()

// List lines inside the front bubble.
ctx.setFillColor(rgb(0x1E2230, 0.85))
for (i, w) in [CGFloat(290), 220, 260].enumerated() {
    let y = front.maxY - 92 - CGFloat(i) * 62
    ctx.addPath(CGPath(roundedRect: CGRect(x: front.minX + 80, y: y, width: w, height: 30),
                       cornerWidth: 15, cornerHeight: 15, transform: nil))
}
ctx.fillPath()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
