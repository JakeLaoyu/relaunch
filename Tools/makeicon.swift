// Renders the Relaunch app icon (a rocket on a blue→violet squircle) to a PNG.
// Usage: swift Tools/makeicon.swift <output.png> [size]
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size = CGFloat(CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2]) ?? 1024 : 1024)

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = CGRect(x: 0, y: 0, width: size, height: size)
let clip = NSBezierPath(roundedRect: rect, xRadius: size * 0.2237, yRadius: size * 0.2237)
clip.addClip()

// Background gradient.
let top = NSColor(srgbRed: 0.36, green: 0.55, blue: 1.0, alpha: 1)    // #5B8CFF
let bottom = NSColor(srgbRed: 0.42, green: 0.24, blue: 0.96, alpha: 1) // #6B3DF5
NSGradient(starting: top, ending: bottom)!.draw(in: rect, angle: 270)

// Soft highlight near the top.
NSGradient(colors: [NSColor(white: 1, alpha: 0.22), NSColor(white: 1, alpha: 0)])!
    .draw(in: rect, relativeCenterPosition: NSPoint(x: 0, y: 0.55))

// Rocket glyph, tinted white.
let names = ["square.grid.3x3.fill", "rocket.fill", "paperplane.fill"]
var base: NSImage?
for n in names {
    if let s = NSImage(systemSymbolName: n, accessibilityDescription: nil) {
        base = s
        FileHandle.standardError.write("symbol: \(n)\n".data(using: .utf8)!)
        break
    }
}
if let base {
    let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .semibold)
    let conf = base.withSymbolConfiguration(cfg) ?? base
    let s = conf.size
    let tint = NSImage(size: s)
    tint.lockFocus()
    conf.draw(at: .zero, from: NSRect(origin: .zero, size: s), operation: .sourceOver, fraction: 1)
    NSColor.white.set()
    NSRect(origin: .zero, size: s).fill(using: .sourceAtop)
    tint.unlockFocus()

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.28)
    shadow.shadowBlurRadius = size * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.set()
    tint.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2,
                         width: s.width, height: s.height))
}

image.unlockFocus()

if let tiff = image.tiffRepresentation,
   let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try! png.write(to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath)")
}
