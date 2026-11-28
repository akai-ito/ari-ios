#if DEBUG
    import MapKit
    import SwiftUI

    // MARK: - Round 2: Life as one tab, by time, with the lit map for longer stretches

    /// The sections across the top of Life, under the search field.
    enum LifeSection: Int, CaseIterable {
        case days, places, people, goingOn, made

        static let words = ["Days", "Places", "People", "Going on", "Made"]
    }

    /// Search your life, or ask: Kumo answers first, then the day, the place, the people.
    struct LifeSearchField: View {
        var text: String?

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.ariTertiary)
                Text(text ?? "Search your life, or ask")
                    .foregroundStyle(text == nil ? Color.ariTertiary : .ariText)
                Spacer()
                Image(systemName: text == nil ? "mic" : "xmark.circle.fill")
                    .foregroundStyle(.ariTertiary)
            }
            .font(.body)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Color.ariField.opacity(0.92), in: Capsule())
        }
    }

    /// The search field, then the sections, the one you're on lit.
    struct LifeTop: View {
        let section: LifeSection

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                LifeSearchField()
                LensRow(lenses: LifeSection.words, current: section.rawValue)
            }
        }
    }

    /// A section of Life that scrolls, with the search and the sections at the top.
    struct LifeScroll<Content: View>: View {
        let section: LifeSection
        var spacing: CGFloat = 20
        @ViewBuilder var content: Content

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: spacing) {
                    LifeTop(section: section)
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(Color.ariBackground)
        }
    }

    /// A section of Life over the full-screen lit map: the search and the sections float at the
    /// top, the zoom under them, and a sheet rests at the bottom.
    struct LifeOverMap<Ground: View, Sheet: View>: View {
        let section: LifeSection
        var zoom: Int?
        let sheetHeight: CGFloat
        @ViewBuilder var ground: Ground
        @ViewBuilder var sheet: Sheet

        var body: some View {
            ZStack(alignment: .top) {
                ground.ignoresSafeArea()
                LinearGradient(
                    stops: [
                        .init(color: Color.ariBackground.opacity(0.96), location: 0),
                        .init(color: Color.ariBackground.opacity(0.8), location: 0.55),
                        .init(color: Color.ariBackground.opacity(0), location: 1),
                    ], startPoint: .top, endPoint: .bottom
                )
                .frame(height: 250)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                VStack(spacing: 12) {
                    LifeTop(section: section)
                    if let zoom {
                        ZoomScale(current: zoom)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                RestingSheet(height: sheetHeight) { sheet }
            }
            .background(Color.ariBackground)
        }
    }

    // MARK: - Heat that saturates, home included

    extension LifeData {
        /// How brightly a place glows for the hours spent there: rises fast, then caps at `full`
        /// hours, so home and the office are simply full and a two-hour dinner still shows.
        static func glow(_ hours: Double, full: Double) -> Double {
            min(1, (1 - exp(-3 * hours / full)) / (1 - exp(-3)))
        }

        static func glow(_ spots: [Spot], full: Double) -> [HeatPoint] {
            spots.map {
                HeatPoint(coordinate: $0.place.coordinate, weight: glow($0.hours, full: full))
            }
        }

        /// A view filling the screen's width with `span` degrees of longitude, centred so that
        /// `lat` sits `lift` points above the middle of the screen.
        static func wide(lat: Double, lon: Double, span: Double) -> MKCoordinateRegion {
            MKCoordinateRegion(
                center: .init(latitude: lat, longitude: lon),
                span: .init(latitudeDelta: 0.0005, longitudeDelta: span))
        }

        static let dalryPitch = LifePlace(
            id: "pitch", name: "Five-a-side", what: "Dalry · Tuesdays", symbol: "soccerball",
            lat: 55.9436, lon: -3.2215)
    }

    // MARK: - The year away: trips across continents (made up)

    struct LifeTrip: Identifiable {
        var id: String { name }
        let name: String
        let country: String
        let lat: Double
        let lon: Double
        /// Month, 0-based, with where in it (0…1).
        let month: Double
        let days: Int
        let why: String
    }

    extension LifeData {
        static let trips: [LifeTrip] = [
            LifeTrip(
                name: "Marrakech", country: "Morocco", lat: 31.63, lon: -7.99, month: 1.5,
                days: 6, why: "Winter sun, and the Atlas"),
            LifeTrip(
                name: "Lisbon", country: "Portugal", lat: 38.72, lon: -9.14, month: 4.4, days: 8,
                why: "Between jobs"),
            LifeTrip(
                name: "Kochi & Goa", country: "India", lat: 9.93, lon: 76.27, month: 6.6, days: 14,
                why: "Anya's wedding"),
            LifeTrip(
                name: "Kyoto & Tokyo", country: "Japan", lat: 35.01, lon: 135.77, month: 8.5,
                days: 12, why: "The trip you'd put off for years"),
        ]

        /// Chapters of the year: from, to (months, 0-based), and the name.
        static let chapters: [(from: Double, to: Double, name: String)] = [
            (0, 2.6, "Winter at the old job"), (2.6, 5.5, "Leaving, then Lisbon"),
            (5.5, 9, "The long summer"), (9, 10.77, "The Northwind autumn"),
        ]

        static let nowMonth = 10.77
    }
#endif
