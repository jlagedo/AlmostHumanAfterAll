import Foundation
import AppKit

struct CommentEntry: Identifiable {
    let id = UUID()
    let track: TrackInfo?
    let comment: String
    let personality: Personality
    let thumbnailData: Data?
    let timestamp: Date

    var isReview: Bool { track == nil }

    init(track: TrackInfo, comment: String, personality: Personality, artwork: NSImage? = nil) {
        self.track = track
        self.comment = comment
        self.personality = personality
        self.thumbnailData = Self.makeThumbnail(from: artwork, maxSize: 48)
        self.timestamp = Date()
    }

    init(reviewComment: String, personality: Personality) {
        self.track = nil
        self.comment = reviewComment
        self.personality = personality
        self.thumbnailData = nil
        self.timestamp = Date()
    }

    var thumbnailImage: NSImage? {
        guard let data = thumbnailData else { return nil }
        return NSImage(data: data)
    }

    private static func makeThumbnail(from image: NSImage?, maxSize: CGFloat) -> Data? {
        guard let image else { return nil }
        let size = NSSize(width: maxSize, height: maxSize)
        let thumbnail = NSImage(size: size)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        thumbnail.unlockFocus()

        guard let tiff = thumbnail.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }
}
