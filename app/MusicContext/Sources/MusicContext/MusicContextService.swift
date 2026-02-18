import Foundation
import MusicKit

public actor MusicContextService {
    private let musicKit: MusicKitProvider
    private let genius: GeniusProvider?

    public init(geniusAccessToken: String? = nil) {
        self.musicKit = MusicKitProvider()
        self.genius = geniusAccessToken.map { GeniusProvider(accessToken: $0) }
    }

    /// Fetch metadata from MusicKit + Genius in parallel, format into v17 section blocks.
    /// Always returns at least a `[Song]` section — both lookups are failable.
    public func fetch(name: String, artist: String, album: String, genre: String) async -> String {
        // MusicKit + Genius in parallel (both non-fatal)
        async let songResult: Song? = {
            do {
                let result = try await musicKit.searchSong(artist: artist, track: name, album: album)
                NSLog("[MusicContext] MusicKit match: \"%@\" by %@", result.title, result.artistName)
                return result
            } catch {
                NSLog("[MusicContext] MusicKit lookup failed (non-fatal): %@", error.localizedDescription)
                return nil
            }
        }()

        async let geniusResult: MusicContextData? = {
            guard let genius else {
                NSLog("[MusicContext] Genius: skipped (no token)")
                return nil
            }
            do {
                NSLog("[MusicContext] Genius: searching \"%@\" by %@", name, artist)
                let data = try await genius.fetchContext(artist: artist, track: name, album: album)
                NSLog("[MusicContext] Genius match: \"%@\" by %@", data.track.title, data.artist.name)
                return data
            } catch {
                NSLog("[MusicContext] Genius lookup failed (non-fatal): %@", error.localizedDescription)
                return nil
            }
        }()

        let song = await songResult
        let geniusData = await geniusResult

        let sections = PromptBuilder.build(
            name: name, artist: artist, album: album, genre: genre,
            song: song, geniusData: geniusData
        )

        NSLog("[MusicContext] Built sections (%d chars):\n%@", sections.count, sections)
        return sections
    }

    /// Request MusicKit authorization.
    public static func requestAuthorization() async -> MusicAuthorization.Status {
        await MusicKitProvider.authorize()
    }
}
