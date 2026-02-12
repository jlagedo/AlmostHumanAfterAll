import AppKit
import Foundation

final class ArtworkService {
    private var lastTempURL: URL?

    func fetchArtwork() async -> NSImage? {
        NSLog("[Artwork] Fetching artwork via AppleScript...")
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let script = """
                tell application "Music"
                    if player state is playing then
                        try
                            set artData to raw data of artwork 1 of current track
                            return artData
                        end try
                    end if
                end tell
                """

                let appleScript = NSAppleScript(source: script)
                var errorDict: NSDictionary?
                let result = appleScript?.executeAndReturnError(&errorDict)

                guard let result else {
                    NSLog("[Artwork] No result from AppleScript (Music not playing or no artwork)")
                    continuation.resume(returning: nil)
                    return
                }

                let data = result.data
                let image = NSImage(data: data)
                NSLog("[Artwork] Got artwork: %dx%d (%d bytes)", Int(image?.size.width ?? 0), Int(image?.size.height ?? 0), data.count)
                continuation.resume(returning: image)
            }
        }
    }

    func saveArtworkToTemp(_ image: NSImage) -> URL? {
        // Clean up previous temp file
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
