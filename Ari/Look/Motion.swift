import Foundation

func clamp(_ x: Double, _ low: Double = 0, _ high: Double = 1) -> Double {
    min(max(x, low), high)
}

enum Ease {
    static func inOut(_ x: Double) -> Double {
        let x = clamp(x)
        return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    static func out(_ x: Double) -> Double {
        1 - pow(1 - clamp(x), 3)
    }
}

/// How much each timed segment counts at `t`: each eases in over `fade` seconds while the one
/// before eases out, so anything built as a weighted sum of per-segment values blends smoothly.
func segmentWeights(_ starts: [Double], at t: Double, fade: Double) -> [Double] {
    let rise = starts.enumerated().map { index, start in
        index == 0 ? 1 : Ease.inOut((t - start) / fade)
    }
    return rise.indices.map { index in
        rise[index] - (index + 1 < rise.count ? rise[index + 1] : 0)
    }
}

/// A sine that dwells at -1 and 1 and moves briskly between them: a glance, then a hold.
func smoothSquare(_ u: Double, sharpness: Double = 3.5) -> Double {
    tanh(sharpness * sin(2 * .pi * u)) / tanh(sharpness)
}
