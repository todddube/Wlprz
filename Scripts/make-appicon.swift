#!/usr/bin/env swift
//
//  make-appicon.swift
//  Scripts · Wlprz
//
//  Draws the app icon at every size the asset catalogue needs.
//

import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]

func draw(pixels: Int) -> Data? {
    let s = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    path.addClip()
    NSGradient(colors: [NSColor(red: 0.03, green: 0.04, blue: 0.12, alpha: 1),
                        NSColor(red: 0.10, green: 0.08, blue: 0.28, alpha: 1)])?.draw(in: rect, angle: 90)
    // Three aurora ribbons.
    let ribbons: [(NSColor, CGFloat)] = [(.systemGreen, 0.62), (.systemTeal, 0.50), (.systemPurple, 0.38)]
    for (color, height) in ribbons {
        let ribbon = NSBezierPath()
        ribbon.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * height))
        ribbon.curve(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * (height + 0.06)),
                     controlPoint1: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + rect.height * (height + 0.22)),
                     controlPoint2: CGPoint(x: rect.minX + rect.width * 0.6, y: rect.minY + rect.height * (height - 0.18)))
        ribbon.lineWidth = max(1, s * 0.07)
        ribbon.lineCapStyle = .round
        color.withAlphaComponent(0.85).setStroke()
        ribbon.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

var images: [[String: String]] = []
for (points, scale) in sizes {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    if let data = draw(pixels: points * scale) { try data.write(to: output.appendingPathComponent(name)) }
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
