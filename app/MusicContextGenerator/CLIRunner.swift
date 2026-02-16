import Foundation
import MusicKit
import MusicContext
import os

enum CLIRunner {
    static func run(_ args: [String]) async {
        do {
            let parsed = try parseArguments(args)

            switch parsed.arguments {
            case .musicBrainz(let artist, let album, let track, let durationMs):
                logger.info("MusicBrainz: fetching context for \(track, privacy: .public) by \(artist, privacy: .public)")

                let provider = MusicBrainzProvider(
                    appName: "MusicContextGenerator",
                    version: "0.1.0",
                    contact: "musiccontext@example.com"
                )

                let durationInfo = durationMs.map { " (\($0)ms)" } ?? ""
                print("Fetching context for: \"\(track)\" by \(artist) from \"\(album)\"\(durationInfo)...")
                print()

                logger.debug("MusicBrainz: searching for artist=\(artist, privacy: .public) track=\(track, privacy: .public) album=\(album, privacy: .public)")
                let context = try await provider.fetchContext(
                    artist: artist, track: track, album: album, durationMs: durationMs
                )
                logger.info("MusicBrainz: context fetched, MBID: \(context.track.musicBrainzId ?? "nil", privacy: .public)")
                MusicBrainzFormatter.printContext(context)

            case .musicKit(let artist, let album, let track):
                logger.info("MusicKit: searching for \(track, privacy: .public) by \(artist, privacy: .public)")
                try await ensureAuthorized()

                let provider = MusicKitProvider()
                print("Searching Apple Music for: \"\(track)\" by \(artist) from \"\(album)\"...")
                print()

                logger.debug("MusicKit: catalog search initiated")
                let song = try await provider.searchSong(artist: artist, track: track, album: album)
                logger.info("MusicKit: found song ID \(song.id.rawValue, privacy: .public)")
                MusicKitFormatter.printSong(song)
                await MusicKitFormatter.printFullContext(song: song, provider: provider)

            case .musicKitID(let catalogID):
                logger.info("MusicKit: fetching catalog ID \(catalogID, privacy: .public)")
                try await ensureAuthorized()

                let provider = MusicKitProvider()
                print("Fetching song with catalog ID: \(catalogID)...")
                print()

                logger.debug("MusicKit: resource request for ID \(catalogID, privacy: .public)")
                let song = try await provider.fetchSong(catalogID: catalogID)
                logger.info("MusicKit: fetched \(song.title, privacy: .public) by \(song.artistName, privacy: .public)")
                MusicKitFormatter.printSong(song)
                await MusicKitFormatter.printFullContext(song: song, provider: provider)

            case .musicKitPlaylist(let name):
                logger.info("MusicKit: searching for playlist \(name, privacy: .public)")
                try await ensureAuthorized()

                let provider = MusicKitProvider()
                CLIHelpers.printErr("Searching Apple Music for playlist: \"\(name)\"...")

                logger.debug("MusicKit: playlist search initiated")
                let playlist = try await provider.searchPlaylist(name: name)
                logger.info("Playlist: found '\(playlist.name, privacy: .public)'")

                let tracks = try await provider.fetchPlaylistTracks(playlist: playlist)
                logger.info("Playlist: '\(playlist.name, privacy: .public)' has \(tracks.count) tracks")
                CLIHelpers.printErr("Found \(tracks.count) tracks.")

                print(CLIHelpers.formatCSV(tracks: tracks), terminator: "")

            case .genius(let artist, let album, let track):
                logger.info("Genius: fetching context for \(track, privacy: .public) by \(artist, privacy: .public)")

                guard let token = Bundle.main.infoDictionary?["GeniusAccessToken"] as? String,
                      !token.isEmpty, token != "your_genius_access_token_here" else {
                    print("Error: GeniusAccessToken not configured in Secrets.xcconfig")
                    exit(1)
                }

                let provider = GeniusProvider(accessToken: token)
                print("Fetching Genius context for: \"\(track)\" by \(artist) from \"\(album)\"...")
                print()

                logger.debug("Genius: search initiated")
                let context = try await provider.fetchContext(artist: artist, track: track, album: album)
                logger.info("Genius: context fetched for \(context.track.title, privacy: .public)")
                GeniusFormatter.printContext(context)
            }

            if case .musicKitPlaylist = parsed.arguments {
                CLIHelpers.printErr("Done.")
            } else {
                print("Done.")
            }

        } catch let error as ArgumentError {
            logger.error("Argument error: \(error.description, privacy: .public)")
            print("Error: \(error.description)")
            exit(1)
        } catch let error as MusicContextError {
            logger.error("MusicContext error: \(error.description, privacy: .public)")
            print("Error: \(error.description)")
            exit(1)
        } catch {
            logger.error("Command failed: \(error, privacy: .public)")
            print("Error: \(error)")
            // Print the full error details for debugging
            print("  Type: \(type(of: error))")
            if let localizedError = error as? LocalizedError {
                if let reason = localizedError.failureReason {
                    print("  Reason: \(reason)")
                }
                if let suggestion = localizedError.recoverySuggestion {
                    print("  Suggestion: \(suggestion)")
                }
            }
            exit(1)
        }
    }

    private static func ensureAuthorized() async throws {
        let currentStatus = MusicAuthorization.currentStatus
        logger.info("MusicKit authorization status: \(String(describing: currentStatus), privacy: .public)")
        CLIHelpers.printErr("MusicKit authorization status: \(currentStatus)")

        if currentStatus != .authorized {
            let status = await MusicAuthorization.request()
            logger.info("MusicKit authorization result: \(String(describing: status), privacy: .public)")
            CLIHelpers.printErr("MusicKit authorization result: \(status)")
            guard status == .authorized else {
                logger.error("MusicKit authorization denied")
                CLIHelpers.printErr("Error: MusicKit authorization denied")
                exit(1)
            }
        }
    }
}
