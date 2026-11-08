#!/bin/zsh
# Export platform icon assets from the project's original artwork.
set -euo pipefail
icon_project="${0:A:h:h}"
icon_source="${1:-${icon_project}/flutter_app/assets/branding/app-icon-master.png}"
[[ -f "$icon_source" ]] || { print -u2 "Missing icon master: $icon_source"; exit 2; }
mkdir -p "${icon_project}/work/app-icon" "${icon_project}/outputs/app-icon" "${icon_project}/flutter_app/assets/branding"
/usr/bin/swift - "$icon_project" "$icon_source" <<'SWIFT'
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let project = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let input = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      image.width == image.height, image.width >= 1024 else {
    fatalError("Icon source must be square and at least 1024 pixels.")
}
let manager = FileManager.default
func writePNG(_ size: Int, to file: URL, mac: Bool = false) throws {
    let alpha = mac ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast
    guard let context = CGContext(data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: size * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: alpha.rawValue) else {
        fatalError("Cannot create icon canvas.")
    }
    context.interpolationQuality = .high
    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    if mac {
        let inset = CGFloat(size) * 0.08
        let tile = canvas.insetBy(dx: inset, dy: inset)
        let path = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.22,
                          cornerHeight: tile.height * 0.22, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -CGFloat(size) * 0.01),
                          blur: CGFloat(size) * 0.018,
                          color: CGColor(gray: 0, alpha: 0.2))
        context.addPath(path)
        context.setFillColor(CGColor(red: 0, green: 0.35, blue: 0.34, alpha: 1))
        context.fillPath()
        context.restoreGState()
        context.addPath(path)
        context.clip()
        context.draw(image, in: tile)
    } else {
        context.setFillColor(CGColor(red: 0, green: 0.35, blue: 0.34, alpha: 1))
        context.fill(canvas)
        context.draw(image, in: canvas)
    }
    guard let result = context.makeImage() else { fatalError("Cannot render icon.") }
    let pending = file.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".png")
    guard let output = CGImageDestinationCreateWithURL(pending as CFURL,
        UTType.png.identifier as CFString, 1, nil) else { fatalError("Cannot write icon.") }
    CGImageDestinationAddImage(output, result, nil)
    guard CGImageDestinationFinalize(output) else { fatalError("Icon encoding failed.") }
    if manager.fileExists(atPath: file.path) { try manager.removeItem(at: file) }
    try manager.moveItem(at: pending, to: file)
}
for platform in ["macos", "ios"] {
    let folder = project.appendingPathComponent("flutter_app/\(platform)/Runner/Assets.xcassets/AppIcon.appiconset")
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("Contents.json"))) as! [String: Any]
    var files = [String: Int]()
    for item in manifest["images"] as! [[String: Any]] {
        guard let name = item["filename"] as? String,
              let size = item["size"] as? String, let scale = item["scale"] as? String,
              let points = Double(size.components(separatedBy: "x")[0]),
              let factor = Double(scale.replacingOccurrences(of: "x", with: "")) else {
            fatalError("Invalid platform icon manifest.")
        }
        let pixels = Int((points * factor).rounded())
        if let existing = files[name], existing != pixels { fatalError("Conflicting icon slot.") }
        files[name] = pixels
    }
    for (name, size) in files.sorted(by: { $0.key < $1.key }) {
        try writePNG(size, to: folder.appendingPathComponent(name), mac: platform == "macos")
    }
    print("Exported \(files.count) \(platform) icon images.")
}
try writePNG(1024, to: project.appendingPathComponent("flutter_app/assets/branding/app-icon-master.png"))
try writePNG(256, to: project.appendingPathComponent("flutter_app/assets/branding/app-icon.png"))
try writePNG(512, to: project.appendingPathComponent("outputs/app-icon/macos-preview.png"), mac: true)
SWIFT
icon_set="${icon_project}/work/app-icon/CD List.iconset"
mkdir -p "$icon_set"
for icon_size in 16 32 128 256 512; do
  cp "${icon_project}/flutter_app/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_${icon_size}.png" "${icon_set}/icon_${icon_size}x${icon_size}.png"
  icon_double=$((icon_size * 2))
  cp "${icon_project}/flutter_app/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_${icon_double}.png" "${icon_set}/icon_${icon_size}x${icon_size}@2x.png"
done
/usr/bin/iconutil --convert icns "$icon_set" --output "${icon_project}/outputs/app-icon/CD List.icns"
print -r -- 'Platform icons exported. Rebuild/relaunch the app for Dock and Command–Tab changes.'
