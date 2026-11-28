#if DEBUG
    import MapKit
    import SwiftUI

    // MARK: - Search: Kumo answers first, then the day, the place, the people

    struct R2Search: View {
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        LifeSearchField(text: "dinner with Omar")
                        Text("Cancel").font(.body).foregroundStyle(.ariSecondary)
                    }
                    KumoSays(
                        mood: .bright,
                        text:
                            "Orrin's, last Friday, 19:40 to 22:10. You wrote that the fig thing was the best you'd had all month.",
                        size: 36)
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHead(text: "The day")
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Friday 20 November")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.ariText)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                                    .foregroundStyle(.ariTertiary)
                            }
                            DayStrip(stops: [(19.6, 22.2)])
                            Text("Worked from home all day. Orrin's with Omar, and the fig thing.")
                                .font(.system(.subheadline, design: .serif))
                                .foregroundStyle(.ariSecondary)
                        }
                        .padding(14)
                        .background(
                            Color.ariSurface,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Text("And twice before: 3 October with Leo too, and in Lisbon in May.")
                            .font(.caption)
                            .foregroundStyle(.ariTertiary)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHead(text: "The place")
                        MapCard(
                            scene: MapScene(
                                region: LifeData.around(LifeData.toOrrins, pad: 1.9),
                                trails: [LifeData.toOrrins],
                                heat: [
                                    HeatPoint(coordinate: LifeData.orrins.coordinate, weight: 0.6)
                                ],
                                spread: 18,
                                labels: [
                                    MapLabel(
                                        text: "Orrin's · Stockbridge",
                                        coordinate: LifeData.orrins.coordinate, below: false,
                                        strong: true),
                                    MapLabel(text: "Home", coordinate: LifeData.home.coordinate),
                                ],
                                selected: LifeData.orrins.coordinate),
                            height: 150, zoom: 14)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHead(text: "The people")
                        PersonRow(person: People.omar, detail: "A friend · last seen Friday")
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

    // MARK: - Your places, muted, home in, with the year's trips

    struct R2Places: View {
        var body: some View {
            LifeScroll(section: .places, spacing: 18) {
                ZoomHeader(
                    title: "Your places", subtitle: "November · 23 places · 2 new", zoom: 1,
                    levels: ["Week", "Month", "Year"])
                MapCard(
                    scene: MapScene(
                        region: LifeData.city, heat: LifeData.glow(LifeData.month, full: 40),
                        spread: 13,
                        labels: [LifeData.office, LifeData.gym, LifeData.home, LifeData.leo].map {
                            MapLabel(text: $0.name, coordinate: $0.coordinate)
                        }),
                    look: .muted, height: 196, zoom: 14)
                VStack(alignment: .leading, spacing: 10) {
                    SectionHead(text: "Trips this year · 4")
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(LifeData.trips.reversed()) { trip in
                                TripCard(trip: trip)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .padding(.horizontal, -20)
                    .contentMargins(.horizontal, 20)
                }
                VStack(alignment: .leading, spacing: 14) {
                    SectionHead(text: "Where the month went")
                    ForEach(Array(S1Places.rows.prefix(5).enumerated()), id: \.offset) { _, row in
                        PlaceRow(spot: row.0)
                    }
                }
            }
        }
    }

    struct PlaceRow: View {
        let spot: LifeData.Spot

        var body: some View {
            HStack(spacing: 12) {
                DotGlyph(symbol: spot.place.symbol, side: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(spot.place.name).font(.ariName).foregroundStyle(.ariText)
                    Text(spot.place.what).font(.caption).foregroundStyle(.ariTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(Int(spot.hours)) h")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.ariSecondary)
                    HoursDots(fraction: spot.hours / 160, count: 10)
                }
            }
        }
    }

    struct TripCard: View {
        let trip: LifeTrip

        private var when: String {
            ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][
                Int(trip.month)]
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(trip.country).font(.ariName).foregroundStyle(.ariText)
                    Spacer()
                    Circle().fill(lampColor).frame(width: 7, height: 7)
                }
                Text(trip.name).font(.caption).foregroundStyle(.ariSecondary)
                Text("\(when) · \(trip.days) days").font(.caption2).foregroundStyle(.ariTertiary)
            }
            .padding(12)
            .frame(width: 142, alignment: .leading)
            .background(
                Color.ariSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - A place's page, over the map

    extension LifeData {
        static let officeToOrrins: [CLLocationCoordinate2D] = [
            (55.9530, -3.2000), (55.9545, -3.2030), (55.9562, -3.2058), (55.9575, -3.2078),
            (55.9585, -3.2090),
        ].map { .init(latitude: $0.0, longitude: $0.1) }
    }

    struct R2Place: View {
        var body: some View {
            LifeOverMap(section: .places, sheetHeight: 506) {
                LifeMap(
                    scene: MapScene(
                        region: LifeData.wide(lat: 55.9500, lon: -3.2060, span: 0.035),
                        faintTrails: [LifeData.toOrrins, LifeData.officeToOrrins],
                        heat: [HeatPoint(coordinate: LifeData.orrins.coordinate, weight: 0.75)],
                        spread: 34,
                        labels: [
                            MapLabel(
                                text: "Orrin's", coordinate: LifeData.orrins.coordinate,
                                below: false, strong: true)
                        ],
                        selected: LifeData.orrins.coordinate),
                    zoom: 15, credit: false)
            } sheet: {
                VStack(alignment: .leading, spacing: 15) {
                    HStack(spacing: 12) {
                        DotGlyph(symbol: "fork.knife", side: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Orrin's").font(.ariHeading).foregroundStyle(.ariText)
                            Text("My name for it · Apple calls it Orrin's Kitchen")
                                .font(.caption).foregroundStyle(.ariTertiary)
                        }
                        Spacer()
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.ariSecondary)
                            .frame(width: 30, height: 30)
                            .background(Color.ariField, in: Circle())
                    }
                    Text("3 visits since October · Fridays, about 2 h 30")
                        .font(.subheadline).foregroundStyle(.ariSecondary)
                    VisitThread()
                    HStack(spacing: 10) {
                        PhotoStack(people: [People.omar, People.leo, People.mira], side: 28)
                        Text("Omar twice, Leo once · Mira tonight")
                            .font(.footnote).foregroundStyle(.ariSecondary)
                    }
                    Text(
                        "You come back for the fig thing. Tonight's table is at 19:30, by the window."
                    )
                    .font(.ariBody).foregroundStyle(.ariText).lineSpacing(3)
                    Moment(when: "Fri 20 Nov", text: "“The fig thing was the best all month.”")
                    HStack(spacing: 8) {
                        Chip(text: "Rename")
                        Chip(text: "Every visit")
                        Chip(text: "Not a place")
                    }
                }
            }
        }
    }

    /// Visits as knots on the months, with tonight's still to come.
    struct VisitThread: View {
        static let months = ["Oct", "Nov", "Dec"]

        var body: some View {
            VStack(spacing: 4) {
                Canvas { context, size in
                    func x(_ m: Double) -> CGFloat { CGFloat(m / 3) * size.width }
                    let y = size.height / 2
                    let now = 1.77
                    var past = Path()
                    var ahead = Path()
                    var at: CGFloat = 1
                    while at <= size.width {
                        if at <= x(now) {
                            past.addEllipse(in: CGRect(x: at - 1, y: y - 1, width: 2, height: 2))
                            at += 4
                        } else {
                            ahead.addEllipse(
                                in: CGRect(x: at - 0.7, y: y - 0.7, width: 1.4, height: 1.4))
                            at += 7
                        }
                    }
                    context.fill(past, with: .color(.ariSecondary.opacity(0.7)))
                    context.fill(ahead, with: .color(.ariTertiary.opacity(0.55)))
                    for m in [0.1, 0.35, 1.63] {
                        let p = x(m)
                        context.fill(
                            Path(ellipseIn: CGRect(x: p - 4, y: y - 4, width: 8, height: 8)),
                            with: .color(.ariBone))
                    }
                    let tonight = x(now + 0.02)
                    context.stroke(
                        Path(ellipseIn: CGRect(x: tonight - 5, y: y - 5, width: 10, height: 10)),
                        with: .color(.ariText), lineWidth: 1.3)
                }
                .frame(height: 12)
                HStack(spacing: 0) {
                    ForEach(Self.months, id: \.self) { m in
                        Text(m).font(.caption2).foregroundStyle(.ariTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
#endif
