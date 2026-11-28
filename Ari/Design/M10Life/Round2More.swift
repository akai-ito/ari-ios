#if DEBUG
    import SwiftUI

    // MARK: - Going on: matters, projects and goals as threads beside time

    struct GoingThread: Identifiable {
        var id: String { title }
        let symbol: String
        let title: String
        let status: String
        let line: String
        /// Days from 1 October; today is 54.
        let from: Double
        var to: Double?
        var knots: [Double] = []
        var ahead: [Double] = []
        /// A goal's end, past the edge of the page.
        var target: String?
        /// Kumo is working on it now.
        var kumo = false
        var lit = false
    }

    struct R2GoingOn: View {
        static let groups: [(String, [GoingThread])] = [
            (
                "Matters",
                [
                    GoingThread(
                        symbol: "briefcase.fill", title: "Northwind", status: "Final today",
                        line: "You came out smiling. I'm watching for their email.", from: 5,
                        knots: [5, 19, 35, 54], kumo: true, lit: true),
                    GoingThread(
                        symbol: "gift.fill", title: "Mira's birthday", status: "Fri 4 Dec",
                        line: "The ceramics class, booked for two.", from: 40, to: 64,
                        knots: [40, 51], ahead: [64]),
                ]
            ),
            (
                "Projects",
                [
                    GoingThread(
                        symbol: "airplane", title: "Lisbon in March",
                        status: "Flights held till Sun",
                        line: "Leo's in, Omar's a maybe. I'll ask you on Saturday.", from: 32,
                        knots: [32, 48], ahead: [59], target: "Mar", kumo: true),
                    GoingThread(
                        symbol: "hammer.fill", title: "The spare room", status: "2 of 5 done",
                        line: "Shelves up. The desk comes on Thursday.", from: 20, to: 82,
                        knots: [20, 38], ahead: [57, 70, 82]),
                ]
            ),
            (
                "Goals",
                [
                    GoingThread(
                        symbol: "figure.run", title: "Spring 10k", status: "Week 4 of 10",
                        line: "Three runs a week. Tonight's is with Leo.", from: 25,
                        knots: stride(from: 25.0, through: 53, by: 3.5).map { $0 },
                        target: "14 Mar"),
                    GoingThread(
                        symbol: "character.bubble.fill", title: "Portuguese",
                        status: "12 days running",
                        line: "Ten minutes a day, for Lisbon. You haven't missed one.", from: 42,
                        knots: stride(from: 43.0, through: 54, by: 1).map { $0 }, target: "Mar"),
                ]
            ),
        ]

        var body: some View {
            LifeScroll(section: .goingOn, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Going on").font(.ariTitle).foregroundStyle(.ariText)
                    Text("Matters, projects, goals · the line is today")
                        .font(.footnote).foregroundStyle(.ariTertiary)
                }
                MonthAxis()
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Self.groups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHead(text: group.0)
                            ForEach(group.1) { thread in
                                GoingRow(thread: thread)
                            }
                        }
                    }
                }
                .overlay { NowLine() }
            }
        }
    }

    struct GoingRow: View {
        let thread: GoingThread

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    DotGlyph(symbol: thread.symbol, side: 26)
                    Text(thread.title).font(.ariName).foregroundStyle(.ariText)
                    Spacer()
                    Text(thread.status)
                        .font(.caption)
                        .foregroundStyle(thread.lit ? Color.ariText : .ariTertiary)
                }
                GoThread(thread: thread)
                    .frame(height: 14)
                    .overlay {
                        if thread.kumo {
                            GeometryReader { geometry in
                                KumoFace(mood: .focused, size: 22, still: true)
                                    .position(
                                        x: MatterThread.x(54, geometry.size.width) + 16,
                                        y: geometry.size.height / 2)
                            }
                        }
                    }
                Text(thread.line)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(.ariSecondary)
                    .lineLimit(1)
            }
        }
    }

    struct GoThread: View {
        let thread: GoingThread

        var body: some View {
            Canvas { context, size in
                let y = size.height / 2
                let now = 54.0
                let end = thread.to ?? 122
                func x(_ d: Double) -> CGFloat { MatterThread.x(d, size.width) }
                var past = Path()
                var ahead = Path()
                var d = thread.from
                let edge = thread.target == nil ? end : 122
                while d <= edge {
                    let p = x(d)
                    if d <= now {
                        past.addEllipse(in: CGRect(x: p - 1, y: y - 1, width: 2, height: 2))
                        d += 4 / Double(size.width) * 122
                    } else {
                        ahead.addEllipse(
                            in: CGRect(x: p - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
                        d += 7 / Double(size.width) * 122
                    }
                }
                context.fill(past, with: .color(.ariSecondary.opacity(0.7)))
                context.fill(ahead, with: .color(.ariTertiary.opacity(0.55)))
                for knot in thread.knots {
                    let p = x(knot)
                    let r: CGFloat = knot == 54 && thread.lit ? 4 : 2.6
                    context.fill(
                        Path(ellipseIn: CGRect(x: p - r, y: y - r, width: r * 2, height: r * 2)),
                        with: .color(knot == 54 && thread.lit ? .ariText : .ariSecondary))
                }
                for knot in thread.ahead {
                    let p = x(knot)
                    context.stroke(
                        Path(ellipseIn: CGRect(x: p - 3.2, y: y - 3.2, width: 6.4, height: 6.4)),
                        with: .color(.ariTertiary), lineWidth: 1.1)
                }
                if let target = thread.target {
                    let label = context.resolve(
                        Text(target).font(.caption2.weight(.semibold)).foregroundStyle(
                            Color.ariSecondary))
                    let width = label.measure(in: size).width
                    let ring = CGRect(x: size.width - 9, y: y - 4.5, width: 9, height: 9)
                    context.fill(
                        Path(
                            roundedRect: CGRect(
                                x: size.width - width - 22, y: y - 8, width: width + 22, height: 16),
                            cornerRadius: 8),
                        with: .color(.ariBackground))
                    context.draw(label, at: CGPoint(x: size.width - 14 - width / 2, y: y))
                    context.stroke(Path(ellipseIn: ring), with: .color(.ariBone), lineWidth: 1.4)
                    context.fill(
                        Path(ellipseIn: ring.insetBy(dx: 2.8, dy: 2.8)), with: .color(.ariBone))
                }
            }
        }
    }

    // MARK: - Made: what Kumo made for you

    struct MadeThing: Identifiable {
        enum Kind { case guide, comparison, menu, steps }
        var id: String { title }
        let title: String
        let kind: Kind
        let detail: String
        var accent = 0
    }

    struct R2Made: View {
        static let lately: [MadeThing] = [
            MadeThing(title: "Lisbon for three", kind: .guide, detail: "Guide · for March"),
            MadeThing(
                title: "Running shoes, side by side", kind: .comparison, detail: "3 pairs · Tue",
                accent: 1),
            MadeThing(
                title: "Dinner for Mira's parents", kind: .menu, detail: "Menu · Sat 12 Dec"),
            MadeThing(
                title: "Ceramics classes", kind: .comparison, detail: "4 studios · last week",
                accent: 2),
        ]
        static let kept: [MadeThing] = [
            MadeThing(title: "Kyoto, slowly", kind: .guide, detail: "Guide · September", accent: 1),
            MadeThing(title: "Bleeding the radiators", kind: .steps, detail: "How-to · 6 steps"),
        ]

        var body: some View {
            LifeScroll(section: .made, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Made for you").font(.ariTitle).foregroundStyle(.ariText)
                    Text("Guides, comparisons, menus · 14 so far")
                        .font(.footnote).foregroundStyle(.ariTertiary)
                }
                SectionHead(text: "Lately")
                MadeGrid(things: Self.lately)
                SectionHead(text: "Kept")
                MadeGrid(things: Self.kept)
            }
        }
    }

    struct MadeGrid: View {
        let things: [MadeThing]

        var body: some View {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                alignment: .leading, spacing: 16
            ) {
                ForEach(things) { thing in
                    MadeCard(thing: thing)
                }
            }
        }
    }

    struct MadeCard: View {
        let thing: MadeThing

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                MadeKindCover(thing: thing)
                    .frame(height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(thing.title)
                    .font(.system(.subheadline, design: .serif).weight(.semibold))
                    .foregroundStyle(.ariText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(thing.detail).font(.caption).foregroundStyle(.ariTertiary)
            }
        }
    }

    /// Each kind has its own cover, drawn in dots.
    struct MadeKindCover: View {
        let thing: MadeThing

        var body: some View {
            ZStack {
                Color.ariSurface
                switch thing.kind {
                case .guide: GuideCover(seed: thing.accent)
                case .comparison: ComparisonCover(lit: thing.accent)
                case .menu: MenuCover()
                case .steps: StepsCover()
                }
            }
        }
    }

    struct GuideCover: View {
        let seed: Int

        var body: some View {
            Canvas { context, size in
                var points: [CGPoint] = []
                for i in 0...40 {
                    let t = CGFloat(i) / 40
                    if seed == 1 {
                        let a: CGFloat = t * 2 * CGFloat.pi * 0.92 - CGFloat.pi / 2
                        let shrink: CGFloat = 1 - 0.25 * t
                        let px: CGFloat = size.width * 0.5 + cos(a) * size.width * 0.3 * shrink
                        let py: CGFloat = size.height * 0.52 + sin(a) * size.height * 0.32 * shrink
                        points.append(CGPoint(x: px, y: py))
                    } else {
                        let wave = sin(t * .pi * 2.2) * 0.22
                        points.append(
                            CGPoint(
                                x: size.width * (0.12 + 0.76 * t),
                                y: size.height * (0.72 - 0.44 * t + wave)))
                    }
                }
                context.fill(
                    MapGrid.dotted(points, every: 4.2, radius: 1.2),
                    with: .color(.ariSecondary.opacity(0.8)))
                for (i, k) in [0, 18, 40].enumerated() {
                    let p = points[k]
                    let r: CGFloat = i == 1 ? 5 : 3.6
                    context.fill(
                        Path(
                            ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                        with: .color(i == 1 ? lampColor : .ariBone))
                }
            }
        }
    }

    struct ComparisonCover: View {
        let lit: Int

        var body: some View {
            Canvas { context, size in
                let columns = 3
                let w = size.width / CGFloat(columns + 1)
                for c in 0..<columns {
                    let x0 = w * 0.5 + CGFloat(c) * w * 1.08
                    let rect = CGRect(
                        x: x0, y: size.height * 0.18, width: w * 0.86, height: size.height * 0.64)
                    let isLit = c == lit % columns
                    context.stroke(
                        Path(roundedRect: rect, cornerRadius: 8),
                        with: .color(isLit ? .ariBone : .ariLine), lineWidth: isLit ? 1.4 : 1)
                    var dots = Path()
                    for row in 0..<4 {
                        let filled = isLit ? 5 : 3 + (row + c) % 2
                        for k in 0..<5 {
                            let p = CGPoint(
                                x: rect.minX + 9 + CGFloat(k) * (rect.width - 18) / 4,
                                y: rect.minY + 14 + CGFloat(row) * (rect.height - 28) / 3)
                            let r: CGFloat = k < filled ? 1.7 : 1
                            dots.addEllipse(
                                in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                        }
                    }
                    context.fill(dots, with: .color(isLit ? .ariBone : .ariTertiary.opacity(0.7)))
                }
            }
        }
    }

    struct StepsCover: View {
        var body: some View {
            Canvas { context, size in
                for i in 0..<6 {
                    let y = size.height * 0.2 + CGFloat(i) * size.height * 0.12
                    let x = size.width * 0.28
                    let done = i < 2
                    let dot = CGRect(x: x - 3.5, y: y - 3.5, width: 7, height: 7)
                    if done {
                        context.fill(Path(ellipseIn: dot), with: .color(.ariBone))
                    } else {
                        context.stroke(
                            Path(ellipseIn: dot), with: .color(.ariTertiary), lineWidth: 1)
                    }
                    var line = Path()
                    var at = x + 12
                    let end = x + 12 + size.width * (0.3 + 0.12 * CGFloat((i * 7) % 3))
                    while at < end {
                        line.addEllipse(in: CGRect(x: at - 1, y: y - 1, width: 2, height: 2))
                        at += 4
                    }
                    context.fill(
                        line, with: .color(done ? .ariSecondary : .ariTertiary.opacity(0.6)))
                }
            }
        }
    }

    struct MenuCover: View {
        var body: some View {
            VStack(spacing: 5) {
                Text("Saturday").font(.system(size: 10, design: .serif).italic())
                    .foregroundStyle(.ariTertiary)
                DotRule(count: 3)
                Text("fennel & orange").font(.system(size: 10, design: .serif))
                Text("slow lamb, flatbread").font(.system(size: 10, design: .serif))
                Text("fig tart").font(.system(size: 10, design: .serif))
            }
            .foregroundStyle(.ariSecondary)
        }
    }

    // MARK: - Behind Kumo on the Desk: what Kumo knows about you

    struct R2DeskKnows: View {
        var body: some View {
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    Spacer().frame(height: 14)
                    VStack(alignment: .leading, spacing: 15) {
                        Capsule().fill(Color.ariLine).frame(width: 38, height: 5)
                            .frame(maxWidth: .infinity)
                        HStack(spacing: 14) {
                            KumoFace(mood: .cosy, size: 52, still: true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("What I know about you")
                                    .font(.ariHeading).foregroundStyle(.ariText)
                                Text("Yours to read. Tap a line to put it right.")
                                    .font(.caption).foregroundStyle(.ariTertiary)
                            }
                        }
                        SectionHead(text: "Portrait")
                        Text(
                            "You plan in bursts, then want it all to just happen. You run to think, cook to unwind, and you'd take one long dinner over three quick drinks."
                        )
                        .font(.ariBody)
                        .foregroundStyle(.ariText)
                        .lineSpacing(4)
                        SectionHead(text: "How to help you")
                        VStack(alignment: .leading, spacing: 7) {
                            KnownLine(text: "Short and straight. Reasons when you ask.")
                            KnownLine(text: "Drafts only. You press send.")
                            KnownLine(text: "Small things, just do. Big ones, ask first.")
                        }
                        SectionHead(text: "Your tastes")
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 7) {
                                SmallChip(text: "Figs")
                                SmallChip(text: "Window seats")
                                SmallChip(text: "Old bookshops")
                            }
                            HStack(spacing: 7) {
                                SmallChip(text: "Spicy, not hot")
                                SmallChip(text: "Long walks")
                                SmallChip(text: "No musicals")
                            }
                        }
                        SectionHead(text: "Lately I learnt")
                        VStack(alignment: .leading, spacing: 7) {
                            Learnt(text: "Friends before family, in your circles", when: "today")
                            Learnt(text: "Dalry on Tuesdays is Omar's five-a-side", when: "Tue")
                            Learnt(text: "Under half an hour, you'd rather walk", when: "Sun")
                        }
                        SectionHead(text: "Getting to know you · 2 to ask")
                        VStack(alignment: .leading, spacing: 11) {
                            KnowRow(title: "Your mornings", lit: 6)
                            KnowRow(title: "Your places", lit: 5)
                            KnowRow(title: "Your people", lit: 3, new: true)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 34, topTrailingRadius: 34, style: .continuous
                        )
                        .fill(Color.ariBackground)
                    )
                    .ignoresSafeArea(edges: .bottom)
                }
            }
        }
    }

    struct SmallChip: View {
        let text: String

        var body: some View {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.ariText)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .overlay { Capsule().stroke(Color.ariLine, lineWidth: 1) }
                .fixedSize()
        }
    }

    struct Learnt: View {
        let text: String
        let when: String

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle().fill(Color.ariBone).frame(width: 4, height: 4).offset(y: -3)
                Text(text)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(.ariText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(when).font(.caption).foregroundStyle(.ariTertiary)
            }
        }
    }
#endif
