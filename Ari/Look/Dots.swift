import SwiftUI

/// A symbol drawn in Ari's bone dots on a faint disc of them, the way the character and a person's
/// monogram are: the Library's shelves, a place without a photo.
struct DotGlyph: View {
    let symbol: String
    var side: CGFloat = 46

    var body: some View {
        ZStack {
            Dots(step: 3.4 * side / 46, size: 0.34).opacity(0.22)
            Dots(step: 2.0 * side / 46, size: 0.44)
                .mask {
                    Image(systemName: symbol)
                        .font(.system(size: 21 * side / 46, weight: .heavy))
                }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// A disc of bone dots on a square grid, `size` being each dot's radius as a share of the step.
struct Dots: View {
    let step: CGFloat
    let size: CGFloat

    var body: some View {
        Canvas { context, canvas in
            let radius = canvas.width / 2
            var dots = Path()
            var y = step / 2
            while y < canvas.height {
                var x = step / 2
                while x < canvas.width {
                    let dx = x - radius
                    let dy = y - radius
                    if (dx * dx + dy * dy).squareRoot() < radius {
                        let r = step * size
                        dots.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    }
                    x += step
                }
                y += step
            }
            context.fill(dots, with: .color(.ariBone))
        }
    }
}
