import AppKit
import Foundation

final class ArtworkService {
    private var lastTempURL: URL?

    func fetchArtwork() async -> NSImage? {
        // TODO: Replace with MusicKit catalog artwork fetch
        return nil
    }

    func saveArtworkToTemp(_ image: NSImage) -> URL? {
        cleanupTempFile()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ficino_coverart_\(UUID().uuidString).png")

        do {
            try pngData.write(to: tempURL)
            lastTempURL = tempURL
            return tempURL
        } catch {
            return nil
        }
    }

    func cleanupTempFile() {
        guard let url = lastTempURL else { return }
        try? FileManager.default.removeItem(at: url)
        lastTempURL = nil
    }
}
