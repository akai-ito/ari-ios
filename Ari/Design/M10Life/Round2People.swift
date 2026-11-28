#if DEBUG
    import Contacts
    import ContactsUI
    import MapKit
    import SwiftUI

    // MARK: - People (made up), with drawn stand-ins for their Contacts photos

    enum HairStyle { case short, long, curly, bob, cropped, bun }

    struct PhotoLook {
        let top: Color
        let bottom: Color
        let skin: Color
        let hair: Color
        let shirt: Color
        let hair2: HairStyle
        var beard = false
    }

    struct LifePerson: Identifiable {
        let id: String
        let name: String
        let last: String
        var next: String?
        var soon = false
        let look: PhotoLook
    }

    private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255)
    }

    enum People {
        static let mira = LifePerson(
            id: "mira", name: "Mira", last: "This morning · home", next: "Birthday · Fri 4",
            soon: true,
            look: PhotoLook(
                top: rgb(214, 150, 120), bottom: rgb(120, 74, 70), skin: rgb(226, 184, 152),
                hair: rgb(58, 36, 28), shirt: rgb(196, 152, 64), hair2: .long))
        static let leo = LifePerson(
            id: "leo", name: "Leo", last: "Thursday · his place", next: "Run tonight", soon: true,
            look: PhotoLook(
                top: rgb(96, 140, 132), bottom: rgb(42, 70, 72), skin: rgb(238, 200, 176),
                hair: rgb(176, 92, 48), shirt: rgb(40, 54, 92), hair2: .short))
        static let omar = LifePerson(
            id: "omar", name: "Omar", last: "Friday · Orrin's", next: "Lisbon? · March",
            look: PhotoLook(
                top: rgb(120, 136, 160), bottom: rgb(52, 60, 80), skin: rgb(170, 118, 84),
                hair: rgb(24, 20, 20), shirt: rgb(150, 60, 50), hair2: .cropped))
        static let tilly = LifePerson(
            id: "tilly", name: "Tilly", last: "Not since August", next: "Back on the 3rd",
            soon: true,
            look: PhotoLook(
                top: rgb(160, 140, 190), bottom: rgb(80, 66, 110), skin: rgb(240, 208, 186),
                hair: rgb(222, 190, 120), shirt: rgb(170, 84, 56), hair2: .bob))
        static let priya = LifePerson(
            id: "priya", name: "Priya", last: "Two weeks ago", next: nil,
            look: PhotoLook(
                top: rgb(200, 180, 120), bottom: rgb(110, 90, 50), skin: rgb(160, 110, 80),
                hair: rgb(20, 16, 16), shirt: rgb(40, 110, 110), hair2: .bun))
        static let jonah = LifePerson(
            id: "jonah", name: "Jonah", last: "September", next: nil,
            look: PhotoLook(
                top: rgb(130, 150, 110), bottom: rgb(60, 72, 50), skin: rgb(120, 80, 58),
                hair: rgb(26, 20, 18), shirt: rgb(210, 200, 180), hair2: .curly))
        static let mum = LifePerson(
            id: "mum", name: "Mum", last: "Called Sunday", next: "Here 19 Dec",
            look: PhotoLook(
                top: rgb(110, 150, 100), bottom: rgb(50, 80, 50), skin: rgb(196, 146, 110),
                hair: rgb(80, 74, 72), shirt: rgb(130, 40, 60), hair2: .bob))
        static let dad = LifePerson(
            id: "dad", name: "Dad", last: "Called Sunday", next: nil,
            look: PhotoLook(
                top: rgb(190, 170, 140), bottom: rgb(100, 86, 66), skin: rgb(186, 136, 100),
                hair: rgb(150, 146, 140), shirt: rgb(60, 90, 140), hair2: .cropped))
        static let anya = LifePerson(
            id: "anya", name: "Anya", last: "Her wedding · July", next: "Birthday · 12 Jan",
            look: PhotoLook(
                top: rgb(210, 140, 160), bottom: rgb(110, 60, 80), skin: rgb(190, 140, 104),
                hair: rgb(22, 18, 18), shirt: rgb(30, 120, 120), hair2: .long))
        static let clara = LifePerson(
            id: "clara", name: "Clara Voss", last: "Today · the final", next: "Answer by Friday",
            soon: true,
            look: PhotoLook(
                top: rgb(150, 150, 156), bottom: rgb(70, 70, 76), skin: rgb(240, 212, 192),
                hair: rgb(140, 64, 40), shirt: rgb(30, 30, 34), hair2: .bob))
        static let sam = LifePerson(
            id: "sam", name: "Sam", last: "Coffee · 12 Nov", next: nil,
            look: PhotoLook(
                top: rgb(90, 110, 130), bottom: rgb(40, 50, 64), skin: rgb(96, 64, 46),
                hair: rgb(16, 12, 12), shirt: rgb(220, 214, 200), hair2: .curly))
        static let ines = LifePerson(
            id: "ines", name: "Inês", last: "October", next: nil,
            look: PhotoLook(
                top: rgb(170, 120, 90), bottom: rgb(90, 56, 40), skin: rgb(220, 176, 140),
                hair: rgb(70, 40, 24), shirt: rgb(90, 110, 70), hair2: .long))

        static let haddad = LifePerson(
            id: "haddad", name: "Omar Haddad", last: "", look: omar.look)
        static let lindqvist = LifePerson(
            id: "lindqvist", name: "Omar Lindqvist", last: "",
            look: PhotoLook(
                top: rgb(170, 186, 200), bottom: rgb(80, 96, 110), skin: rgb(236, 206, 184),
                hair: rgb(210, 180, 120), shirt: rgb(110, 110, 116), hair2: .short))
    }

    /// A drawn stand-in for a Contacts photo: soft light, a head and shoulders.
    struct PhotoStandIn: View {
        let look: PhotoLook
        var side: CGFloat = 44

        var body: some View {
            Canvas { context, size in
                let s = size.width
                func r(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
                    CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
                }
                context.fill(
                    Path(r(0, 0, 1, 1)),
                    with: .linearGradient(
                        Gradient(colors: [look.top, look.bottom]), startPoint: .zero,
                        endPoint: CGPoint(x: s * 0.3, y: s)))
                context.fill(
                    Path(ellipseIn: r(-0.2, -0.3, 0.9, 0.8)),
                    with: .radialGradient(
                        Gradient(colors: [.white.opacity(0.22), .clear]),
                        center: CGPoint(x: s * 0.2, y: s * 0.1), startRadius: 0,
                        endRadius: s * 0.6))
                switch look.hair2 {
                case .long:
                    context.fill(
                        Path(roundedRect: r(0.27, 0.19, 0.46, 0.62), cornerRadius: s * 0.2),
                        with: .color(look.hair))
                case .bob:
                    context.fill(
                        Path(roundedRect: r(0.28, 0.19, 0.44, 0.44), cornerRadius: s * 0.19),
                        with: .color(look.hair))
                default: break
                }
                context.fill(Path(ellipseIn: r(0.1, 0.72, 0.8, 0.62)), with: .color(look.shirt))
                context.fill(
                    Path(roundedRect: r(0.43, 0.55, 0.14, 0.2), cornerRadius: s * 0.04),
                    with: .color(look.skin.opacity(0.8)))
                context.fill(
                    Path(roundedRect: r(0.43, 0.55, 0.14, 0.2), cornerRadius: s * 0.04),
                    with: .color(.black.opacity(0.18)))
                context.fill(Path(ellipseIn: r(0.335, 0.22, 0.33, 0.41)), with: .color(look.skin))
                if look.beard {
                    var beard = Path()
                    beard.addArc(
                        center: CGPoint(x: s * 0.5, y: s * 0.43), radius: s * 0.165,
                        startAngle: .degrees(10), endAngle: .degrees(170), clockwise: false)
                    context.stroke(beard, with: .color(look.hair.opacity(0.9)), lineWidth: s * 0.07)
                }
                switch look.hair2 {
                case .short:
                    context.fill(Path(ellipseIn: r(0.32, 0.17, 0.36, 0.2)), with: .color(look.hair))
                case .cropped:
                    context.fill(
                        Path(ellipseIn: r(0.335, 0.195, 0.33, 0.14)), with: .color(look.hair))
                case .curly:
                    for (x, y) in [
                        (0.33, 0.25), (0.38, 0.19), (0.45, 0.16), (0.53, 0.16), (0.6, 0.19),
                        (0.65, 0.25),
                    ] {
                        context.fill(
                            Path(ellipseIn: r(x - 0.07, y - 0.06, 0.14, 0.13)),
                            with: .color(look.hair))
                    }
                case .bun:
                    context.fill(
                        Path(ellipseIn: r(0.335, 0.195, 0.33, 0.15)), with: .color(look.hair))
                    context.fill(Path(ellipseIn: r(0.43, 0.1, 0.14, 0.13)), with: .color(look.hair))
                case .long, .bob:
                    context.fill(
                        Path(ellipseIn: r(0.32, 0.18, 0.36, 0.16)), with: .color(look.hair))
                }
            }
            .blur(radius: side * 0.012)
            .frame(width: side, height: side)
            .clipShape(Circle())
        }
    }

    struct PhotoStack: View {
        let people: [LifePerson]
        var side: CGFloat = 26

        var body: some View {
            HStack(spacing: -side * 0.32) {
                ForEach(people) { person in
                    PhotoStandIn(look: person.look, side: side)
                        .overlay { Circle().stroke(Color.ariSurface, lineWidth: 2) }
                }
            }
        }
    }

    struct PersonRow: View {
        let person: LifePerson
        let detail: String

        var body: some View {
            HStack(spacing: 12) {
                PhotoStandIn(look: person.look, side: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name).font(.ariName).foregroundStyle(.ariText)
                    Text(detail).font(.caption).foregroundStyle(.ariTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.ariTertiary)
            }
        }
    }

    // MARK: - (a) A calm list of circles, in your order

    struct Circle2 {
        let name: String
        let count: Int
        let people: [LifePerson]
        var more: [LifePerson] = []
    }

    extension People {
        static let circles: [Circle2] = [
            Circle2(name: "Partner", count: 1, people: [mira]),
            Circle2(name: "Friends", count: 7, people: [leo, omar, tilly], more: [priya, jonah]),
            Circle2(name: "Family", count: 5, people: [mum, anya], more: [dad]),
            Circle2(name: "Work", count: 6, people: [clara, sam], more: [ines]),
            Circle2(name: "Others", count: 29, people: []),
        ]
    }

    struct R2People: View {
        var body: some View {
            LifeScroll(section: .people, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your people").font(.ariTitle).foregroundStyle(.ariText)
                        Text("48 from your contacts · in your order")
                            .font(.footnote).foregroundStyle(.ariTertiary)
                    }
                    Spacer()
                    OrderButton()
                }
                ForEach(People.circles.prefix(4), id: \.name) { circle in
                    CircleBlock(circle: circle)
                }
            }
        }
    }

    struct OrderButton: View {
        var body: some View {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                Text("Order")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.ariSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.ariField, in: Capsule())
        }
    }

    struct CircleBlock: View {
        let circle: Circle2

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                SectionHead(
                    text: circle.count > 1 ? "\(circle.name) · \(circle.count)" : circle.name)
                ForEach(circle.people) { person in
                    CirclePersonRow(person: person)
                }
                if !circle.more.isEmpty {
                    HStack(spacing: 12) {
                        PhotoStack(people: circle.more, side: 26)
                            .frame(width: 42, alignment: .leading)
                        Text(
                            circle.more.map(\.name).joined(separator: ", ")
                                + " and \(circle.count - circle.people.count - circle.more.count) more"
                        )
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
                    }
                }
            }
        }
    }

    struct CirclePersonRow: View {
        let person: LifePerson

        var body: some View {
            HStack(spacing: 12) {
                PhotoStandIn(look: person.look, side: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name).font(.ariName).foregroundStyle(.ariText)
                    Text(person.last).font(.caption).foregroundStyle(.ariTertiary)
                }
                Spacer()
                if let next = person.next {
                    HStack(spacing: 6) {
                        if person.soon {
                            Circle().fill(lampColor).frame(width: 6, height: 6)
                        }
                        Text(next)
                            .font(.caption)
                            .foregroundStyle(person.soon ? Color.ariText : .ariTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Reordering the circles

    struct R2PeopleOrder: View {
        var body: some View {
            R2People()
                .sheet(isPresented: .constant(true)) {
                    CircleOrder()
                        .presentationDetents([.height(610)])
                        .presentationBackground(Color.ariSurface)
                        .presentationDragIndicator(.visible)
                }
        }
    }

    struct CircleOrder: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Your circles").font(.ariHeading).foregroundStyle(.ariText)
                    Spacer()
                    Text("Done").font(.body.weight(.semibold)).foregroundStyle(.ariText)
                }
                Text(
                    "Hold and drag. Closest first: this is the order I'll use for people everywhere."
                )
                .font(.footnote)
                .foregroundStyle(.ariSecondary)
                VStack(spacing: 8) {
                    OrderRow(circle: People.circles[0])
                    OrderRow(circle: People.circles[1])
                    OrderRow(circle: People.circles[2], lifted: true)
                    OrderRow(circle: People.circles[3])
                    OrderRow(circle: People.circles[4], people: [People.ines, People.jonah])
                }
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                    Text("New circle")
                    Spacer()
                    Text("Five-a-side? Book club?").foregroundStyle(.ariTertiary)
                }
                .font(.subheadline)
                .foregroundStyle(.ariSecondary)
                .padding(14)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.ariLine, style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)
        }
    }

    struct OrderRow: View {
        let circle: Circle2
        var lifted = false
        var people: [LifePerson]?

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(lifted ? Color.ariText : .ariTertiary)
                Text(circle.name).font(.ariName).foregroundStyle(.ariText)
                Text("\(circle.count)").font(.caption).foregroundStyle(.ariTertiary)
                Spacer()
                PhotoStack(
                    people: Array((people ?? (circle.people + circle.more)).prefix(3)), side: 26)
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(
                lifted ? Color.ariLine : Color.ariField,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .scaleEffect(lifted ? 1.04 : 1)
            .shadow(color: .black.opacity(lifted ? 0.55 : 0), radius: 14, y: 8)
            .offset(y: lifted ? -14 : 0)
            .zIndex(lifted ? 1 : 0)
        }
    }

    // MARK: - (b) My own: orbits, closest in the middle

    struct R2Orbits: View {
        var body: some View {
            LifeScroll(section: .people, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your people").font(.ariTitle).foregroundStyle(.ariText)
                    Text("Closest in the middle · drag a ring in or out to reorder")
                        .font(.footnote).foregroundStyle(.ariTertiary)
                }
                OrbitView().frame(height: 360)
                KumoSays(
                    mood: .calm, text: "Tilly's drifted: not since August. She's back on the 3rd.",
                    size: 30)
                VStack(alignment: .leading, spacing: 10) {
                    SectionHead(text: "Coming up")
                    ForEach(
                        [
                            ("Tonight", "Run with Leo, then Orrin's with Mira"),
                            ("Thu 3 Dec", "Tilly's back in town"),
                            ("Fri 4 Dec", "Mira's birthday"),
                        ], id: \.0
                    ) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(item.0)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.ariTertiary)
                                .frame(width: 66, alignment: .leading)
                            Text(item.1)
                                .font(.system(.subheadline, design: .serif))
                                .foregroundStyle(.ariText)
                        }
                    }
                }
            }
        }
    }

    struct OrbitView: View {
        static let rings: [CGFloat] = [42, 84, 125, 163]
        static let names = ["partner", "friends", "family", "work"]
        /// Who, on which ring, at what angle, and whether you've seen them lately.
        static let placed: [(LifePerson, Int, Double, Bool)] = [
            (People.mira, 0, 200, true),
            (People.leo, 1, 150, true), (People.omar, 1, 25, true), (People.tilly, 1, 270, false),
            (People.priya, 1, 95, true), (People.jonah, 1, 330, false),
            (People.mum, 2, 120, true), (People.dad, 2, 60, true), (People.anya, 2, 205, false),
            (People.clara, 3, 345, true), (People.sam, 3, 160, true), (People.ines, 3, 235, false),
        ]

        var body: some View {
            GeometryReader { geometry in
                let c = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                ZStack {
                    Canvas { context, _ in
                        for (i, r) in Self.rings.enumerated() {
                            var dots = Path()
                            let count = Int(2 * .pi * r / 6)
                            for k in 0..<count {
                                let a = Double(k) / Double(count) * 2 * .pi
                                let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                                dots.addEllipse(
                                    in: CGRect(x: p.x - 0.9, y: p.y - 0.9, width: 1.8, height: 1.8))
                            }
                            context.fill(
                                dots,
                                with: .color(.ariSecondary.opacity(0.55 - Double(i) * 0.08)))
                        }
                        let me = CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)
                        context.stroke(
                            Path(ellipseIn: me.insetBy(dx: 1, dy: 1)), with: .color(.ariText),
                            lineWidth: 1.3)
                        context.fill(
                            Path(ellipseIn: me.insetBy(dx: 3.8, dy: 3.8)), with: .color(.ariText))
                    }
                    Text("you")
                        .font(.caption2)
                        .foregroundStyle(.ariTertiary)
                        .position(x: c.x, y: c.y + 15)
                    ForEach(Array(Self.names.enumerated()), id: \.offset) { i, name in
                        let a = -62.0 * .pi / 180
                        Text(name)
                            .font(.caption2)
                            .foregroundStyle(.ariTertiary)
                            .padding(.horizontal, 4)
                            .background(Color.ariBackground)
                            .position(
                                x: c.x + cos(a) * Self.rings[i], y: c.y + sin(a) * Self.rings[i])
                    }
                    ForEach(Self.placed, id: \.0.id) { item in
                        let a = item.2 * .pi / 180
                        let r = Self.rings[item.1]
                        OrbitFace(person: item.0, recent: item.3)
                            .position(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                        Text(item.0.name.split(separator: " ").first.map(String.init) ?? "")
                            .font(.system(size: 10))
                            .foregroundStyle(item.3 ? Color.ariSecondary : .ariTertiary)
                            .padding(.horizontal, 3)
                            .background(Color.ariBackground.opacity(0.8), in: Capsule())
                            .position(
                                x: c.x + cos(a) * r, y: c.y + sin(a) * r + (item.3 ? 26 : 22))
                    }
                }
            }
        }
    }

    struct OrbitFace: View {
        let person: LifePerson
        let recent: Bool

        var body: some View {
            let side: CGFloat = recent ? 36 : 28
            PhotoStandIn(look: person.look, side: side)
                .opacity(recent ? 1 : 0.45)
                .overlay {
                    Circle()
                        .stroke(
                            recent ? Color.ariBackground : Color.ariSecondary,
                            style: StrokeStyle(
                                lineWidth: recent ? 3 : 1, dash: recent ? [] : [1.5, 3])
                        )
                }
                .overlay(alignment: .topTrailing) {
                    if person.soon {
                        Circle().fill(lampColor).frame(width: 9, height: 9)
                            .overlay { Circle().stroke(Color.ariBackground, lineWidth: 2) }
                            .offset(x: 2, y: -2)
                    }
                }
        }
    }

    // MARK: - A person's page

    struct R2Person: View {
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("People")
                    }
                    .font(.body)
                    .foregroundStyle(.ariSecondary)
                    HStack(spacing: 16) {
                        PhotoStandIn(look: People.omar.look, side: 84)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Omar").font(.ariTitle).foregroundStyle(.ariText)
                            Text("A friend · five-a-side")
                                .font(.subheadline).foregroundStyle(.ariSecondary)
                            HStack(spacing: 5) {
                                Image(systemName: "person.text.rectangle")
                                Text("Contact card")
                                Image(systemName: "chevron.right").font(.caption2)
                            }
                            .font(.footnote)
                            .foregroundStyle(.ariTertiary)
                        }
                    }
                    QuietActions()
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ComingChip(text: "Tue · five-a-side", soon: true)
                            ComingChip(text: "9 Jan · his birthday")
                            ComingChip(text: "March · Lisbon, a maybe")
                        }
                    }
                    .scrollIndicators(.hidden)
                    .padding(.horizontal, -20)
                    .contentMargins(.horizontal, 20)
                    VStack(alignment: .leading, spacing: 9) {
                        SectionHead(text: "What I know")
                        KnownLine(text: "Plays five-a-side in Dalry on Tuesdays.")
                        KnownLine(text: "Vegetarian. Always orders the fig thing.")
                        KnownLine(text: "Wants to come to Lisbon if work lets him.")
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        SectionHead(text: "Together lately")
                        Moment(when: "Fri 20 Nov", text: "Orrin's. The best fig thing all month.")
                        Moment(when: "Tue 17 Nov", text: "Five-a-side, then chips in the rain.")
                        Moment(when: "Sat 3 Oct", text: "Orrin's with Leo; we stayed till close.")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHead(text: "Places you share")
                        MapCard(
                            scene: MapScene(
                                region: MKCoordinateRegion(
                                    center: .init(latitude: 55.9512, longitude: -3.2120),
                                    span: .init(latitudeDelta: 0.03, longitudeDelta: 0.07)),
                                heat: [
                                    HeatPoint(coordinate: LifeData.orrins.coordinate, weight: 0.7),
                                    HeatPoint(
                                        coordinate: LifeData.dalryPitch.coordinate, weight: 0.85),
                                ], spread: 13,
                                labels: [
                                    MapLabel(
                                        text: "Orrin's", coordinate: LifeData.orrins.coordinate,
                                        below: false),
                                    MapLabel(
                                        text: "Five-a-side",
                                        coordinate: LifeData.dalryPitch.coordinate),
                                ]),
                            height: 124, zoom: 14)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(Color.ariBackground)
        }
    }

    /// Call, Message, FaceTime, Email, Directions: quiet, one tap each, iOS does the rest.
    struct QuietActions: View {
        static let actions: [(String, String)] = [
            ("phone.fill", "Call"), ("message.fill", "Message"), ("video.fill", "FaceTime"),
            ("envelope.fill", "Email"), ("arrow.triangle.turn.up.right.diamond.fill", "Directions"),
        ]

        var body: some View {
            HStack(spacing: 0) {
                ForEach(Self.actions, id: \.1) { action in
                    VStack(spacing: 5) {
                        Image(systemName: action.0)
                            .font(.system(size: 14))
                            .foregroundStyle(.ariSecondary)
                            .frame(width: 38, height: 38)
                            .background(Color.ariField, in: Circle())
                        Text(action.1).font(.caption2).foregroundStyle(.ariTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    struct ComingChip: View {
        let text: String
        var soon = false

        var body: some View {
            HStack(spacing: 6) {
                if soon { Circle().fill(lampColor).frame(width: 6, height: 6) }
                Text(text).font(.footnote).foregroundStyle(soon ? Color.ariText : .ariSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.ariSurface, in: Capsule())
        }
    }

    struct KnownLine: View {
        let text: String

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle().fill(Color.ariBone).frame(width: 4, height: 4).offset(y: -3)
                Text(text).font(.system(.subheadline, design: .serif)).foregroundStyle(.ariText)
            }
        }
    }

    struct Moment: View {
        let when: String
        let text: String

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(when)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.ariTertiary)
                    .frame(width: 66, alignment: .leading)
                Text(text)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(.ariSecondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Apple's own contact card, inside Ito

    struct R2PersonCard: View {
        var body: some View {
            R2Person()
                .sheet(isPresented: .constant(true)) {
                    NativeContactCard()
                        .ignoresSafeArea()
                        .presentationDetents([.fraction(0.8)])
                }
        }
    }

    /// ContactsUI's CNContactViewController, the same card as the Contacts app.
    struct NativeContactCard: UIViewControllerRepresentable {
        func makeUIViewController(context: Context) -> UINavigationController {
            let contact = CNMutableContact()
            contact.givenName = "Omar"
            contact.familyName = "Haddad"
            contact.phoneNumbers = [
                CNLabeledValue(
                    label: CNLabelPhoneNumberMobile,
                    value: CNPhoneNumber(stringValue: "07700 900142"))
            ]
            contact.emailAddresses = [
                CNLabeledValue(label: CNLabelHome, value: "omar.haddad@example.com" as NSString)
            ]
            let address = CNMutablePostalAddress()
            address.street = "21 Kestrel Lane"
            address.city = "Edinburgh"
            address.postalCode = "EH11 2AB"
            address.country = "United Kingdom"
            contact.postalAddresses = [CNLabeledValue(label: CNLabelHome, value: address)]
            contact.birthday = DateComponents(year: 1993, month: 1, day: 9)
            let renderer = ImageRenderer(
                content: PhotoStandIn(look: People.omar.look, side: 320))
            renderer.scale = 2
            contact.imageData = renderer.uiImage?.pngData()
            // Saved to the Simulator's Contacts when the sketch may (so the card is the real,
            // linked one); otherwise shown as an unsaved card.
            let store = CNContactStore()
            let keys = [CNContactViewController.descriptorForRequiredKeys()]
            let named = CNContact.predicateForContacts(matchingName: "Omar Haddad")
            var linked = try? store.unifiedContacts(matching: named, keysToFetch: keys).first
            if linked == nil, CNContactStore.authorizationStatus(for: .contacts) == .authorized {
                let save = CNSaveRequest()
                save.add(contact, toContainerWithIdentifier: nil)
                try? store.execute(save)
                linked = try? store.unifiedContacts(matching: named, keysToFetch: keys).first
            }
            let card = CNContactViewController(for: linked ?? contact)
            card.contactStore = linked == nil ? nil : store
            card.allowsEditing = false
            card.allowsActions = true
            return UINavigationController(rootViewController: card)
        }

        func updateUIViewController(_ controller: UINavigationController, context: Context) {}
    }

    // MARK: - Getting to know you: linking people to Contacts

    struct R2Linking: View {
        var body: some View {
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    Spacer().frame(height: 14)
                    VStack(alignment: .leading, spacing: 20) {
                        Capsule().fill(Color.ariLine).frame(width: 38, height: 5)
                            .frame(maxWidth: .infinity)
                        HStack(spacing: 12) {
                            KumoFace(mood: .bright, size: 40, still: true)
                            Text("Getting to know you").font(.ariHeading).foregroundStyle(.ariText)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            KnowRow(title: "Your mornings", lit: 6)
                            KnowRow(title: "Your places", lit: 5)
                            KnowRow(title: "Your people", lit: 3, new: true)
                        }
                        SectionHead(text: "People I'm not sure about · 2")
                        LinkCard()
                            .background(alignment: .trailing) {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(Color.ariSurface.opacity(0.6))
                                    .frame(width: 60)
                                    .padding(.vertical, 14)
                                    .offset(x: 34)
                            }
                        Text(
                            "I link the ones I'm sure of on my own. I only ask when two could fit."
                        )
                        .font(.footnote)
                        .foregroundStyle(.ariTertiary)
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

    struct LinkCard: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                ZStack(alignment: .top) {
                    MentionsBackdrop().frame(height: 196)
                    KumoOnMap(size: 62, mood: .bright)
                        .padding(.top, 96)
                    SpeechLine(text: "Is this Omar from your contacts?")
                        .padding(.top, 16)
                        .padding(.horizontal, 16)
                }
                .frame(height: 196)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous))
                VStack(alignment: .leading, spacing: 12) {
                    Text("Mentioned 14 times: five-a-side, Orrin's, Lisbon.")
                        .font(.caption).foregroundStyle(.ariTertiary)
                    HStack(spacing: 10) {
                        CandidateCard(
                            person: People.haddad, lines: ["mobile · Edinburgh", "in Five-a-side"])
                        CandidateCard(
                            person: People.lindqvist, lines: ["work · Halcyon", "added in 2023"])
                    }
                    HStack {
                        Text("Neither").font(.footnote).foregroundStyle(.ariTertiary)
                        Text("·").foregroundStyle(.ariTertiary)
                        Text("Not in my contacts").font(.footnote).foregroundStyle(.ariTertiary)
                        Text("·").foregroundStyle(.ariTertiary)
                        Text("Skip").font(.footnote).foregroundStyle(.ariTertiary)
                        Spacer()
                        HStack(spacing: 5) {
                            ForEach(0..<2, id: \.self) { i in
                                Circle()
                                    .fill(i == 0 ? Color.ariBone : Color.ariLine)
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(
                Color.ariSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    /// Where Kumo met the name: the words it was said with, faint, in a field of dots.
    struct MentionsBackdrop: View {
        static let words: [(String, CGFloat, CGFloat)] = [
            ("five-a-side", 0.16, 0.5), ("Orrin's", 0.82, 0.46), ("Lisbon?", 0.2, 0.83),
            ("the fig thing", 0.8, 0.82), ("Tuesdays", 0.5, 0.97),
        ]

        var body: some View {
            GeometryReader { geometry in
                ZStack {
                    Color.ariField
                    Dots(step: 7, size: 0.22).opacity(0.18)
                    ForEach(Self.words, id: \.0) { word in
                        Text(word.0)
                            .font(.system(.footnote, design: .serif).italic())
                            .foregroundStyle(.ariSecondary.opacity(0.7))
                            .position(
                                x: geometry.size.width * word.1, y: geometry.size.height * word.2)
                    }
                }
            }
        }
    }

    struct CandidateCard: View {
        let person: LifePerson
        let lines: [String]

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                PhotoStandIn(look: person.look, side: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ariText)
                        .lineLimit(1)
                    ForEach(lines, id: \.self) { line in
                        Text(line).font(.caption).foregroundStyle(.ariTertiary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ariField, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.ariLine, lineWidth: 1)
            }
        }
    }
#endif
