import AriKit
import CoreLocation
import MapKit
import Observation
import Photos
import UIKit
import os

/// Seeds your past places from your photos, once: when and where each was taken, read from
/// PhotoKit's metadata (never the images, nothing downloaded from iCloud), sent to the box in
/// batches it keeps as seeded. A place is named on the phone once per area, so trips know their
/// towns and countries. Progress is kept, so a seeding cut short carries on from where it was.
@Observable
final class PhotoSeeding {
    enum State: Equatable {
        case notStarted
        /// Photos access refused: iOS Settings can change it.
        case refused
        case reading
        /// Naming the areas the photos were taken in.
        case naming(done: Int, of: Int)
        case sending(done: Int, of: Int)
        case finished(photos: Int, on: Date)
        /// Stopped short; trying again carries on.
        case stopped(String)
    }

    private(set) var state: State = .notStarted
    /// Only the photos you picked: iOS's limited access.
    private(set) var limited = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var running: Task<Void, Never>?

    private static let logger = Logger(subsystem: "io.github.akai-ito.ari", category: "places")
    /// Photos per batch to the box.
    static let batchSize = 1000

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let on = defaults.object(forKey: Keys.finishedOn) as? Date {
            state = .finished(photos: defaults.integer(forKey: Keys.count), on: on)
        } else if defaults.integer(forKey: Keys.sent) > 0 {
            state = .stopped("Stopped partway.")
        }
    }

    var isRunning: Bool { running != nil }

    /// Asks for Photos, then reads and sends. Safe to call again: it carries on.
    func start(with client: ItoClient?) {
        guard running == nil, let client else { return }
        running = Task {
            await run(client)
            running = nil
        }
    }

    /// A seeding cut short last time carries on, if Photos is still allowed.
    /// Only one that got partway: one turned away at the start waits for you to try again.
    func resumeIfStopped(with client: ItoClient?) {
        let access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard case .stopped = state, defaults.integer(forKey: Keys.sent) > 0,
            access == .authorized || access == .limited
        else { return }
        start(with: client)
    }

    private func run(_ client: ItoClient) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            state = .refused
            return
        }
        limited = status == .limited
        // Carries on for a while if you leave Ito; iOS ends it otherwise, and the next time
        // carries on from what was sent.
        let background = UIApplication.shared.beginBackgroundTask(withName: "Photo places")
        defer { UIApplication.shared.endBackgroundTask(background) }
        state = .reading
        let photos = await Task.detached(priority: .utility) { Self.readPhotos() }.value
        let named = await name(photos)
        let batches = stride(from: 0, to: named.count, by: Self.batchSize).map {
            Array(named[$0..<min($0 + Self.batchSize, named.count)])
        }
        var sent = defaults.integer(forKey: Keys.sent)
        if sent > batches.count { sent = 0 }
        state = .sending(done: sent, of: batches.count)
        while sent < batches.count {
            let seeds = PhotoSeeds(
                batch: "photos-\(sent + 1)-of-\(batches.count)", photos: batches[sent])
            do throws(RequestError) {
                _ = try await client.seedPhotos(seeds)
            } catch {
                Self.logger.notice("photo seeds wait: \(error.plainWords)")
                state = .stopped(
                    error == .refused(status: 404, error: nil, retryAfter: nil)
                        ? "Your box doesn't take places yet." : "Stopped: \(error.plainWords)")
                return
            }
            sent += 1
            defaults.set(sent, forKey: Keys.sent)
            state = .sending(done: sent, of: batches.count)
        }
        let on = Date.now
        defaults.set(on, forKey: Keys.finishedOn)
        defaults.set(named.count, forKey: Keys.count)
        state = .finished(photos: named.count, on: on)
    }

    /// Every photo and video with a place, oldest first: metadata only.
    nonisolated private static func readPhotos() -> [PhotoSeed] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.includeHiddenAssets = false
        let assets = PHAsset.fetchAssets(with: options)
        var seeds: [PhotoSeed] = []
        seeds.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            guard let taken = asset.creationDate, let location = asset.location,
                CLLocationCoordinate2DIsValid(location.coordinate),
                location.coordinate.latitude != 0 || location.coordinate.longitude != 0
            else { return }
            seeds.append(
                PhotoSeed(
                    takenAt: taken, latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude))
        }
        return seeds
    }

    /// Names one photo per day and area (about 10 km), each area asked of Apple's map data once:
    /// most photos are taken near home, so a few hundred lookups cover years.
    private func name(_ photos: [PhotoSeed]) async -> [PhotoSeed] {
        var photos = photos
        var firsts: [Int] = []
        var seen = Set<String>()
        let calendar = Calendar.current
        for (index, photo) in photos.enumerated() {
            let day = calendar.startOfDay(for: photo.takenAt)
            if seen.insert("\(day.timeIntervalSince1970)|\(PhotoSeeding.cell(photo))").inserted {
                firsts.append(index)
            }
        }
        let cells = Array(Set(firsts.map { PhotoSeeding.cell(photos[$0]) }))
        // Names already found, from a seeding cut short: kept so carrying on doesn't ask again.
        var names = Self.namesFound()
        let unnamed = cells.filter { names[$0] == nil }
        for (done, cell) in unnamed.enumerated() {
            state = .naming(done: done, of: unnamed.count)
            let parts = cell.split(separator: ",").compactMap { Double($0) }
            guard parts.count == 2 else { continue }
            names[cell] = await Placemarks.name(latitude: parts[0], longitude: parts[1])
            if done % 20 == 19 { Self.keep(names) }
            // Apple's geocoder turns away a stream of lookups; one a second it takes.
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { break }
        }
        Self.keep(names)
        for index in firsts { photos[index].placemark = names[PhotoSeeding.cell(photos[index])] }
        return photos
    }

    private static var namesFile: URL? {
        try? FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appending(path: "PhotoPlacemarks.json")
    }

    private static func namesFound() -> [String: Placemark] {
        guard let file = namesFile, let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: Placemark].self, from: data)) ?? [:]
    }

    private static func keep(_ names: [String: Placemark]) {
        guard let file = namesFile else { return }
        try? JSONEncoder().encode(names).write(to: file, options: .atomic)
    }

    private static func cell(_ photo: PhotoSeed) -> String {
        String(format: "%.1f,%.1f", photo.latitude, photo.longitude)
    }

    private enum Keys {
        static let sent = "photoSeedBatchesSent"
        static let finishedOn = "photoSeedFinishedOn"
        static let count = "photoSeedCount"
    }
}

/// Apple's name for a spot on the map: the place itself when there is one, its town and country.
enum Placemarks {
    static func name(latitude: Double, longitude: Double) async -> Placemark? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
            let item = try? await request.mapItems.first
        else { return nil }
        let address = item.addressRepresentations
        let category = item.pointOfInterestCategory?.rawValue
            .replacingOccurrences(of: "MKPOICategory", with: "")
        let placemark = Placemark(
            name: item.name, category: category, locality: address?.cityName,
            country: address?.regionName,
            countryCode: address?.region?.identifier)
        return placemark.isEmpty ? nil : placemark
    }
}
