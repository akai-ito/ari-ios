#if DEBUG
    import MapKit
    import SwiftUI

    /// What a map shows: where, the trail, the heat of where the time went, the stops, Kumo.
    struct MapScene {
        var region: MKCoordinateRegion
        var trails: [[CLLocationCoordinate2D]] = []
        /// Ahead, or a past range's faint routes.
        var faintTrails: [[CLLocationCoordinate2D]] = []
        var heat: [HeatPoint] = []
        /// How far one place's heat spreads, in points at full weight.
        var spread: CGFloat = 30
        var stops: [CLLocationCoordinate2D] = []
        var labels: [MapLabel] = []
        var kumo: CLLocationCoordinate2D?
        var kumoSize: CGFloat = 46
        var kumoMood: FaceMood = .calm
        var selected: CLLocationCoordinate2D?
    }

    struct MapLabel: Identifiable {
        var id: String { text }
        let text: String
        let coordinate: CLLocationCoordinate2D
        var below = true
        var strong = false
    }

    enum MapLook { case muted, halftone }

    /// Kumo's lamp, for heat.
    let lampColor = Color(red: 0.96, green: 0.70, blue: 0.44)

    // MARK: - The map's ground

    /// Map tiles kept on the Simulator for these stills: Esri's World Dark Gray
    /// styles, standing in for MapKit's muted dark map, whose tiles don't load on this network.
    enum Tiles {
        static let root = URL.documentsDirectory.appending(path: "tiles").path

        static func world(_ c: CLLocationCoordinate2D, zoom: Int) -> CGPoint {
            let n = pow(2.0, Double(zoom)) * 256
            let x = (c.longitude + 180) / 360 * n
            let lat = c.latitude * .pi / 180
            let y = (1 - log(tan(lat) + 1 / cos(lat)) / .pi) / 2 * n
            return CGPoint(x: x, y: y)
        }

        private static var cache: [String: UIImage] = [:]

        static func image(style: String, zoom: Int, x: Int, y: Int) -> UIImage? {
            let path = "\(root)/\(style)/\(zoom)/\(x)_\(y).png"
            if let kept = cache[path] { return kept }
            let image = UIImage(contentsOfFile: path)
            cache[path] = image
            return image
        }
    }

    /// Where a region falls in a view, filling it.
    struct MapProjection {
        let zoom: Int
        let center: CGPoint
        let k: CGFloat
        let size: CGSize

        init(region: MKCoordinateRegion, zoom: Int, size: CGSize) {
            self.zoom = zoom
            self.size = size
            center = Tiles.world(region.center, zoom: zoom)
            let nw = Tiles.world(
                .init(
                    latitude: region.center.latitude + region.span.latitudeDelta / 2,
                    longitude: region.center.longitude - region.span.longitudeDelta / 2),
                zoom: zoom)
            let se = Tiles.world(
                .init(
                    latitude: region.center.latitude - region.span.latitudeDelta / 2,
                    longitude: region.center.longitude + region.span.longitudeDelta / 2),
                zoom: zoom)
            k = min(size.width / max(1, se.x - nw.x), size.height / max(1, se.y - nw.y))
        }

        func point(_ c: CLLocationCoordinate2D) -> CGPoint {
            let w = Tiles.world(c, zoom: zoom)
            return CGPoint(
                x: (w.x - center.x) * k + size.width / 2, y: (w.y - center.y) * k + size.height / 2)
        }

        /// Each tile in view and where it goes.
        var tiles: [(x: Int, y: Int, rect: CGRect)] {
            let left = center.x - size.width / 2 / k
            let top = center.y - size.height / 2 / k
            let right = center.x + size.width / 2 / k
            let bottom = center.y + size.height / 2 / k
            var all: [(Int, Int, CGRect)] = []
            for x in Int(floor(left / 256))...Int(floor(right / 256)) {
                for y in Int(floor(top / 256))...Int(floor(bottom / 256)) {
                    let origin = CGPoint(
                        x: (CGFloat(x * 256) - center.x) * k + size.width / 2,
                        y: (CGFloat(y * 256) - center.y) * k + size.height / 2)
                    all.append(
                        (
                            x, y,
                            CGRect(origin: origin, size: CGSize(width: 256 * k, height: 256 * k))
                        ))
                }
            }
            return all
        }
    }

    /// The map's ground, with heat, the trail, stops, labels and Kumo over it.
    struct LifeMap: View {
        let scene: MapScene
        var look: MapLook = .muted
        var step: CGFloat = 5
        var zoom = 15
        var credit = true

        var body: some View {
            GeometryReader { geometry in
                let projection = MapProjection(
                    region: scene.region, zoom: zoom, size: geometry.size)
                ZStack(alignment: .topLeading) {
                    Color.ariBackground
                    switch look {
                    case .muted:
                        Canvas { context, _ in
                            for tile in projection.tiles {
                                guard
                                    let image = Tiles.image(
                                        style: "esri", zoom: zoom, x: tile.x, y: tile.y)
                                else { continue }
                                context.draw(Image(uiImage: image), in: tile.rect)
                            }
                        }
                        .colorMultiply(Color(red: 0.86, green: 0.91, blue: 1.0))
                        .saturation(0.6)
                        Canvas { context, _ in
                            MapMarks.drawGlow(scene: scene, projection: projection, in: &context)
                        }
                    case .halftone:
                        HalftoneGround(
                            scene: scene, projection: projection, step: step, zoom: zoom)
                    }
                    Canvas { context, _ in
                        MapMarks.drawTrails(scene: scene, projection: projection, in: &context)
                    }
                    ForEach(scene.labels) { label in
                        MapTag(label: label).position(projection.point(label.coordinate))
                    }
                    if let selected = scene.selected {
                        SelectedRing().position(projection.point(selected))
                    }
                    if let kumo = scene.kumo {
                        let p = projection.point(kumo)
                        KumoOnMap(size: scene.kumoSize, mood: scene.kumoMood)
                            .position(x: p.x, y: p.y - scene.kumoSize * 0.46)
                    }
                    if credit {
                        Text("Esri, HERE, Garmin, © OpenStreetMap")
                            .font(.system(size: 8))
                            .foregroundStyle(.ariTertiary.opacity(0.7))
                            .padding(6)
                            .frame(
                                maxWidth: .infinity, maxHeight: .infinity,
                                alignment: .bottomTrailing)
                    }
                }
            }
            .clipped()
        }
    }

    enum MapMarks {
        static func drawGlow(
            scene: MapScene, projection: MapProjection, in context: inout GraphicsContext
        ) {
            for point in scene.heat {
                let p = projection.point(point.coordinate)
                let r = scene.spread * (0.7 + 1.1 * point.weight)
                let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .radialGradient(
                        Gradient(colors: [
                            lampColor.opacity(0.3 + 0.55 * point.weight),
                            lampColor.opacity(0.1 + 0.16 * point.weight), lampColor.opacity(0),
                        ]), center: p, startRadius: 0, endRadius: r))
            }
        }

        static func drawTrails(
            scene: MapScene, projection: MapProjection, in context: inout GraphicsContext
        ) {
            for trail in scene.faintTrails {
                context.fill(
                    MapGrid.dotted(trail.map(projection.point), every: 6.5, radius: 1.15),
                    with: .color(.ariSecondary.opacity(0.65)))
            }
            for trail in scene.trails {
                context.fill(
                    MapGrid.dotted(trail.map(projection.point), every: 3.6, radius: 1.55),
                    with: .color(.ariBone))
            }
            for stop in scene.stops {
                StopRing.draw(at: projection.point(stop), in: &context)
            }
        }
    }

    // MARK: - The same map in Ari's dots

    /// The map read once and redrawn as a halftone of dots: streets as rows of bigger dots, water
    /// left dark, and heat as Kumo's lamp.
    struct HalftoneGround: View {
        let scene: MapScene
        let projection: MapProjection
        let step: CGFloat
        let zoom: Int

        var body: some View {
            let grid = MapGrid.make(projection: projection, step: step, zoom: zoom)
            Canvas { context, _ in grid?.draw(in: &context, scene: scene, projection: projection) }
        }
    }

    struct MapGrid {
        enum Ground: UInt8 { case land, road, water }

        let step: CGFloat
        let cols: Int
        let rows: Int
        let ground: [Ground]
        let value: [Double]

        static func make(projection: MapProjection, step: CGFloat, zoom: Int) -> MapGrid? {
            let cols = Int(projection.size.width / step)
            let rows = Int(projection.size.height / step)
            guard cols > 2, rows > 2 else { return nil }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let width = Int(projection.size.width)
            let height = Int(projection.size.height)
            let full = UIGraphicsImageRenderer(
                size: CGSize(width: width, height: height), format: format
            ).image { _ in
                for tile in projection.tiles {
                    Tiles.image(style: "esri", zoom: zoom, x: tile.x, y: tile.y)?.draw(
                        in: tile.rect)
                }
            }
            guard let image = full.cgImage else { return nil }
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            pixels.withUnsafeMutableBytes { buffer in
                guard
                    let context = CGContext(
                        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            // Each cell's mean (for water) and its brightest pixel (so thin streets still count).
            var mean = [Double](repeating: 0, count: cols * rows)
            var peak = [Double](repeating: 0, count: cols * rows)
            for row in 0..<rows {
                for col in 0..<cols {
                    var sum = 0.0
                    var most = 0.0
                    var n = 0.0
                    let x0 = Int(CGFloat(col) * step)
                    let y0 = Int(CGFloat(row) * step)
                    for y in y0..<min(height, Int(CGFloat(row + 1) * step)) {
                        for x in x0..<min(width, Int(CGFloat(col + 1) * step)) {
                            let i = (y * width + x) * 4
                            let l =
                                0.3 * Double(pixels[i]) + 0.59 * Double(pixels[i + 1]) + 0.11
                                * Double(pixels[i + 2])
                            sum += l
                            most = max(most, l)
                            n += 1
                        }
                    }
                    mean[row * cols + col] = sum / max(n, 1)
                    peak[row * cols + col] = most
                }
            }
            let sortedMean = mean.sorted()
            let median = sortedMean[sortedMean.count / 2]
            let darkest = sortedMean[sortedMean.count / 100]
            let sortedPeak = peak.sorted()
            let peakBase = sortedPeak[sortedPeak.count / 2]
            let top = sortedPeak[min(sortedPeak.count - 1, Int(Double(sortedPeak.count) * 0.985))]
            var ground = [Ground](repeating: .land, count: cols * rows)
            var value = [Double](repeating: 0, count: cols * rows)
            let waterLine = darkest + (median - darkest) * 0.5
            for i in 0..<(cols * rows) {
                if median - darkest > 5 && mean[i] < waterLine {
                    ground[i] = .water
                    continue
                }
                let v = max(0, min(1, (peak[i] - peakBase - 4) / max(8, top - peakBase)))
                value[i] = v
                if v > 0.1 { ground[i] = .road }
            }
            return MapGrid(step: step, cols: cols, rows: rows, ground: ground, value: value)
        }

        func draw(in context: inout GraphicsContext, scene: MapScene, projection: MapProjection) {
            var land = Path()
            var road = Path()
            var roadBright = Path()
            var warm: [Path] = Array(repeating: Path(), count: 5)
            let heat = scene.heat.map { (projection.point($0.coordinate), $0.weight) }
            let spread = Double(scene.spread)
            for row in 0..<rows {
                for col in 0..<cols {
                    let i = row * cols + col
                    let x = (CGFloat(col) + 0.5) * step
                    let y = (CGFloat(row) + 0.5) * step
                    var h = 0.0
                    for (p, w) in heat {
                        let dx = Double(x - p.x)
                        let dy = Double(y - p.y)
                        let s = spread * (0.4 + 0.7 * w)
                        h += w * exp(-(dx * dx + dy * dy) / (2 * s * s))
                    }
                    h = min(1, h)
                    if h > 0.07 && ground[i] != .water {
                        let r = step * (0.17 + 0.3 * h)
                        warm[min(4, Int(h * 5))].addEllipse(
                            in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                        continue
                    }
                    switch ground[i] {
                    case .water: continue
                    case .land:
                        let r = step * 0.11
                        land.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    case .road:
                        let v = value[i]
                        let r = step * (0.14 + 0.25 * v)
                        let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                        if v > 0.55 {
                            roadBright.addEllipse(in: rect)
                        } else {
                            road.addEllipse(in: rect)
                        }
                    }
                }
            }
            context.fill(land, with: .color(.ariDusk.opacity(0.26)))
            context.fill(road, with: .color(.ariDusk.opacity(0.75)))
            context.fill(roadBright, with: .color(.ariSecondary.opacity(0.9)))
            for (band, path) in warm.enumerated() {
                context.fill(path, with: .color(lampColor.opacity(0.4 + 0.14 * Double(band))))
            }
        }

        static func dotted(_ points: [CGPoint], every gap: CGFloat, radius: CGFloat) -> Path {
            var path = Path()
            guard points.count > 1 else { return path }
            var carry: CGFloat = 0
            for (a, b) in zip(points, points.dropFirst()) {
                let length = hypot(b.x - a.x, b.y - a.y)
                var at = carry
                while at <= length {
                    let t = at / max(length, 0.001)
                    let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                    path.addEllipse(
                        in: CGRect(
                            x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
                    )
                    at += gap
                }
                carry = at - length
            }
            return path
        }
    }

    // MARK: - Small marks

    /// A stop on the trail: a dark dot ringed in bone, like now on the day's thread.
    struct StopRing: View {
        var body: some View {
            Canvas { context, size in
                StopRing.draw(at: CGPoint(x: size.width / 2, y: size.height / 2), in: &context)
            }
            .frame(width: 14, height: 14)
        }

        static func draw(at p: CGPoint, in context: inout GraphicsContext) {
            let ring = CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: ring), with: .color(.ariBackground))
            context.stroke(
                Path(ellipseIn: ring.insetBy(dx: 0.8, dy: 0.8)), with: .color(.ariBone),
                lineWidth: 1.4)
            context.fill(Path(ellipseIn: ring.insetBy(dx: 3.3, dy: 3.3)), with: .color(.ariBone))
        }
    }

    struct SelectedRing: View {
        var body: some View {
            ZStack {
                Circle().stroke(Color.ariBone.opacity(0.35), lineWidth: 1).frame(
                    width: 46, height: 46)
                Circle().stroke(Color.ariBone, lineWidth: 1.6).frame(width: 22, height: 22)
                Circle().fill(Color.ariBone).frame(width: 8, height: 8)
            }
        }
    }

    struct MapTag: View {
        let label: MapLabel

        var body: some View {
            Text(label.text)
                .font(label.strong ? .caption.weight(.semibold) : .caption2)
                .foregroundStyle(label.strong ? Color.ariText : Color.ariSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.ariBackground.opacity(0.72), in: Capsule())
                .fixedSize()
                .offset(y: label.below ? 15 : -15)
        }
    }

    /// Kumo standing on the map at a spot, with its little shadow.
    struct KumoOnMap: View {
        var size: CGFloat = 46
        var mood: FaceMood = .calm

        var body: some View {
            VStack(spacing: -size * 0.12) {
                KumoFace(mood: mood, size: size, still: true)
                Ellipse()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: size * 0.62, height: size * 0.14)
                    .blur(radius: 2)
            }
        }
    }
#endif
