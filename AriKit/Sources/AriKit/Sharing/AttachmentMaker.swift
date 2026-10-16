import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns what you picked into attachments. Photos are scaled to about 2048 pixels on the long edge,
/// as JPEG, roughly what the model looks at, and lose their location and other metadata on the
/// way. Files go as they are, except images the model can't read, such as HEIC, which become JPEG.
public enum AttachmentMaker {
    /// The most a message carries.
    public static let mostPerMessage = 10
    /// Anything larger isn't read at all; the server refuses a little less than this.
    public static let largest = 20 * 1024 * 1024

    public struct TooLarge: Error {
        public let name: String

        public init(name: String) {
            self.name = name
        }
    }

    @concurrent public static func photo(_ data: Data, name: String) async
        -> PendingAttachment?
    {
        guard let jpeg = jpeg(from: data, longest: 2048) else { return nil }
        return PendingAttachment(name: name, mediaType: "image/jpeg", bytes: jpeg)
    }

    @concurrent public static func file(at url: URL) async throws -> PendingAttachment {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= largest else { throw TooLarge(name: name) }
        let data = try Data(contentsOf: url)
        let type = UTType(filenameExtension: url.pathExtension)
        if let type, type.conforms(to: .image), !seen.contains(where: type.conforms(to:)),
            let jpeg = jpeg(from: data, longest: 2048)
        {
            let stem = url.deletingPathExtension().lastPathComponent
            return PendingAttachment(name: stem + ".jpg", mediaType: "image/jpeg", bytes: jpeg)
        }
        return PendingAttachment(
            name: name, mediaType: type?.preferredMIMEType ?? "application/octet-stream",
            bytes: data)
    }

    /// The images the agent sees as they are.
    private static let seen: [UTType] = [.jpeg, .png, .gif, .webP]

    public static func jpeg(from data: Data, longest: Int) -> Data? {
        guard let image = image(from: data, longest: longest) else { return nil }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    /// The image, upright, at most `longest` pixels on its long edge.
    public static func image(from data: Data, longest: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
