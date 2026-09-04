import SwiftUI
import AppKit

@MainActor
func renderIcon(_ path: String) {
    let renderer = ImageRenderer(content: IconView(side: 1024))
    renderer.scale = 1
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("render icon thất bại"); exit(1)
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("đã ghi \(path)")
    exit(0)
}
