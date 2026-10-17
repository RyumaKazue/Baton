// Baton のアプリのアイコンを描いて、アセットカタログ（AppIcon.appiconset）に書き出す。
// 使い方：リポジトリの直下で swift scripts/make-app-icon.swift
//
// デザイン（2026-10-16 に決定、#58）：青のグラデーションの角丸の四角に、白いヘッドホン（SF Symbols の headphones）。
// macOS のアプリのアイコンの決まりに合わせて、1024 の画面の真ん中に 824 の角丸の四角（角の半径 185）を置く。
import AppKit

let outputDirectory = URL(fileURLWithPath: "BatonMac/Resources/Assets.xcassets/AppIcon.appiconset")

/// アイコンを、指定したピクセル数の正方形で描く
func renderIcon(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let canvas = CGFloat(pixels)
    let inset = canvas * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
    let radius = body.width * 185 / 824
    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    // 下に薄い影を付けて、他の macOS のアイコンと並んだときになじませる
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = canvas * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -canvas * 0.01)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.set()
    let top = NSColor(calibratedRed: 0.30, green: 0.60, blue: 1.00, alpha: 1)
    let bottom = NSColor(calibratedRed: 0.10, green: 0.30, blue: 0.85, alpha: 1)
    NSGradient(starting: top, ending: bottom)!.draw(in: shape, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // 白いヘッドホン
    let configuration = NSImage.SymbolConfiguration(pointSize: body.width * 0.42, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
        let size = symbol.size
        symbol.draw(in: NSRect(x: body.midX - size.width / 2, y: body.midY - size.height / 2, width: size.width, height: size.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// macOS のアプリのアイコンに必要な大きさ（ポイントの大きさ × 1倍・2倍）
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let filename = "icon_\(points)x\(points)@\(scale)x.png"
        try renderIcon(pixels: pixels).write(to: outputDirectory.appendingPathComponent(filename))
        images.append(["idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)", "filename": filename])
        print("書き出した：\(filename)（\(pixels)×\(pixels)）")
    }
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputDirectory.appendingPathComponent("Contents.json"))
print("書き出した：Contents.json")
