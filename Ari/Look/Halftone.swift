import CoreGraphics
import SwiftUI

/// A photo in Ari's halftone: bone dots on a dark ground, bigger where the picture is lighter, on a
/// hex grid like print, filling its frame as a photo would. Without a photo yet, a quiet dusk of
/// dots stands in, so a chapter's cover never shows as a hole.
struct HalftoneImage: View {
    let image: CGImage?
    var step: CGFloat = 5

    @State private var light: Lightness?

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.ground))
            let rowStep = step * 0.866
            var dots = Path()
            var row = 0
            var y = rowStep / 2
            while y < size.height + step {
                var x = row.isMultiple(of: 2) ? step / 2 : step
                while x < size.width + step {
                    let shade =
                        light?.at(x: x, y: y, in: size) ?? Self.dusk(y / max(size.height, 1))
                    let radius = step * 0.56 * shade.squareRoot()
                    if radius > 0.3 {
                        dots.addEllipse(
                            in: CGRect(
                                x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                        )
                    }
                    x += step
                }
                y += rowStep
                row += 1
            }
            context.fill(dots, with: .color(.ariBone.opacity(0.9)))
        }
        .task(id: image.map { ObjectIdentifier($0) }) {
            if let image {
                light = await Lightness.of(image)
            } else {
                light = nil
            }
        }
        .accessibilityHidden(true)
    }

    private static let ground = Color(red: 0.115, green: 0.13, blue: 0.15)

    /// A low evening sky: brighter near the horizon, dark above.
    private static func dusk(_ v: Double) -> Double {
        0.08 + 0.32 * max(0, min(1, (v - 0.15) / 0.85))
    }
}

/// How light a photo is across a small grid, stretched to its own darkest and lightest, so a dim
/// photo still reads in dots.
private struct Lightness: Sendable {
    let width: Int
    let height: Int
    let values: [Double]

    @concurrent static func of(_ image: CGImage) async -> Lightness? {
        let longest = 180
        let scale = Double(longest) / Double(max(image.width, image.height, 1))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        var bytes = [UInt8](repeating: 0, count: width * height)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let sorted = bytes.sorted()
        let low = Double(sorted[sorted.count / 50])
        let high = Double(sorted[sorted.count - 1 - sorted.count / 50])
        let range = max(high - low, 24)
        return Lightness(
            width: width, height: height,
            values: bytes.map { max(0, min(1, (Double($0) - low) / range)) })
    }

    /// The lightness under a point of a frame the photo fills, cropped to keep its shape.
    func at(x: CGFloat, y: CGFloat, in size: CGSize) -> Double {
        let scale = max(size.width / CGFloat(width), size.height / CGFloat(height))
        let offsetX = (CGFloat(width) * scale - size.width) / 2
        let offsetY = (CGFloat(height) * scale - size.height) / 2
        let column = Int((x + offsetX) / scale)
        let row = Int((y + offsetY) / scale)
        guard (0..<width).contains(column), (0..<height).contains(row) else { return 0 }
        return values[row * width + column]
    }
}
