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

            case .contextExtract(let csvPath, let skip):
                try await runContextExtract(csvPath: csvPath, skip: skip)

            case .musicKitCharts(let limit, let storefronts):
                try await runCharts(limit: limit, storefronts: storefronts)
            }

            switch parsed.arguments {
            case .musicKitPlaylist, .contextExtract, .musicKitCharts:
                CLIHelpers.printErr("Done.")
            default:
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

    private static func retryOnTransient<T>(
        label: String,
        _ body: () async throws -> T
    ) async throws -> T {
        for attempt in 1...3 {
            do {
                return try await body()
            } catch let error as MusicContextError {
                switch error {
                case .rateLimited(let retryAfter):
                    let delay = retryAfter ?? 5
                    CLIHelpers.printErr("  \(label): rate limited, waiting \(delay)s (attempt \(attempt)/3)")
                    try await Task.sleep(for: .seconds(delay))
                case .networkError:
                    let delay = attempt * 2  // 2s, 4s
                    CLIHelpers.printErr("  \(label): network error, retrying in \(delay)s (attempt \(attempt)/3)")
                    try await Task.sleep(for: .seconds(delay))
                default:
                    throw error  // permanent failure — no retry
                }
            }
        }
        return try await body()  // final attempt, let it throw
    }

    private static func formatDuration(_ d: Duration) -> String {
        let totalSeconds = Int(d.components.seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%dh%02dm", h, m)
        } else if m > 0 {
            return String(format: "%dm%02ds", m, s)
        } else {
            return "\(s)s"
        }
    }

    private static func runContextExtract(csvPath: String, skip: Int) async throws {
        logger.info("Context extract: reading CSV from \(csvPath, privacy: .public)")
        let allTracks = try CLIHelpers.parseCSV(from: csvPath)
        guard !allTracks.isEmpty else {
            CLIHelpers.printErr("No tracks found in CSV.")
            return
        }

        let tracks = skip > 0 ? Array(allTracks.dropFirst(skip)) : allTracks
        if skip > 0 {
            CLIHelpers.printErr("Loaded \(allTracks.count) tracks, skipping first \(skip), processing \(tracks.count).")
        } else {
            CLIHelpers.printErr("Loaded \(allTracks.count) tracks from CSV.")
        }

        // Authorize MusicKit once
        try await ensureAuthorized()
        let mkProvider = MusicKitProvider()

        // Check Genius token once
        let geniusToken = Bundle.main.infoDictionary?["GeniusAccessToken"] as? String
        let hasGenius = geniusToken != nil && !geniusToken!.isEmpty && geniusToken! != "your_genius_access_token_here"
        if !hasGenius {
            CLIHelpers.printErr("Warning: GeniusAccessToken not configured — Genius data will be skipped.")
        }
        let geniusProvider = hasGenius ? GeniusProvider(accessToken: geniusToken!) : nil

        // Stats
        var mkResolved = 0
        var mkFailed = 0
        var geniusResolved = 0
        var geniusFailed = 0

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let startTime = ContinuousClock.now

        for (index, row) in tracks.enumerated() {
            let trackNum = skip + index + 1
            var mkStatus = ""
            var geniusStatus = ""

            // Fetch MusicKit data
            var mkJSON: MusicKitJSON? = nil
            do {
                let song = try await retryOnTransient(label: "MusicKit search") {
                    try await mkProvider.searchSong(artist: row.artist, track: row.track, album: row.album)
                }
                let songJSON = MusicKitSongJSON.from(song)

                var albumJSON: MusicKitAlbumJSON? = nil
                if let albumID = song.albums?.first?.id {
                    do {
                        let album = try await retryOnTransient(label: "MusicKit album") {
                            try await mkProvider.fetchAlbum(id: albumID)
                        }
                        albumJSON = MusicKitAlbumJSON.from(album)
                    } catch {
                        CLIHelpers.printErr("  MusicKit album error: \(error)")
                    }
                }

                var artistJSON: MusicKitArtistJSON? = nil
                if let artistID = song.artists?.first?.id {
                    do {
                        let artist = try await retryOnTransient(label: "MusicKit artist") {
                            try await mkProvider.fetchArtist(id: artistID)
                        }
                        artistJSON = MusicKitArtistJSON.from(artist)
                    } catch {
                        CLIHelpers.printErr("  MusicKit artist error: \(error)")
                    }
                }

                mkJSON = MusicKitJSON(song: songJSON, album: albumJSON, artist: artistJSON)
                mkResolved += 1
                mkStatus = "✓ mk"
            } catch {
                mkFailed += 1
                mkStatus = "✗ mk"
                CLIHelpers.printErr("  MusicKit error: \(error)")
            }

            // Fetch Genius data
            var geniusData: MusicContextData? = nil
            if let gProvider = geniusProvider {
                do {
                    geniusData = try await retryOnTransient(label: "Genius") {
                        try await gProvider.fetchContext(
                            artist: row.artist, track: row.track, album: row.album
                        )
                    }
                    geniusResolved += 1
                    geniusStatus = "✓ genius"
                } catch let error as MusicContextError {
                    geniusFailed += 1
                    geniusStatus = "✗ genius (\(error))"
                    CLIHelpers.printErr("  Genius error: \(error)")
                } catch {
                    geniusFailed += 1
                    geniusStatus = "✗ genius"
                    CLIHelpers.printErr("  Genius error: \(error)")
                }
            }

            // Time estimate
            let elapsed = startTime.duration(to: .now)
            let done = index + 1
            let avgPerTrack = elapsed / done
            let remaining = avgPerTrack * (tracks.count - done)
            let eta = formatDuration(remaining)
            let elapsedStr = formatDuration(elapsed)

            CLIHelpers.printErr("[\(trackNum)/\(allTracks.count)] \(row.track) — \(row.artist) \(mkStatus) \(geniusStatus) (\(elapsedStr) elapsed, ~\(eta) remaining)")

            let entry = ContextExtractEntry(
                artist: row.artist,
                track: row.track,
                album: row.album,
                musickit: mkJSON,
                genius: geniusData
            )

            // Stream as JSONL — one compact JSON object per line
            do {
                let jsonData = try encoder.encode(entry)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    print(jsonString)
                } else {
                    CLIHelpers.printErr("  Warning: could not encode JSONL as UTF-8, skipping")
                }
            } catch {
                CLIHelpers.printErr("  Warning: JSONL encoding failed: \(error), skipping")
            }
        }

        // Summary
        let total = tracks.count
        let mkPct = total > 0 ? mkResolved * 100 / total : 0
        let geniusPct = total > 0 ? geniusResolved * 100 / total : 0
        let totalElapsed = formatDuration(startTime.duration(to: .now))
        CLIHelpers.printErr("Summary: \(total) processed in \(totalElapsed), \(mkResolved) MusicKit resolved (\(mkPct)%), \(geniusResolved) Genius resolved (\(geniusPct)%)")
    }

    private static func runCharts(limit: Int?, storefronts: [String]?) async throws {
        let perChartLimit = limit ?? 200

        try await ensureAuthorized()
        let provider = MusicKitProvider()

        // Use (lowercased artist + lowercased title) as dedup key
        var seen = Set<String>()
        var csvLines = ["artist,track,album"]

        func addSong(artist: String, title: String, album: String) {
            let key = "\(artist.lowercased())\t\(title.lowercased())"
            if seen.insert(key).inserted {
                csvLines.append("\(CLIHelpers.csvEscape(artist)),\(CLIHelpers.csvEscape(title)),\(CLIHelpers.csvEscape(album))")
            }
        }

        if let storefronts {
            // Multi-storefront mode via raw MusicDataRequest
            for sf in storefronts {
                CLIHelpers.printErr("[\(sf)] Fetching genres...")
                let genres: [(id: String, name: String)]
                do {
                    genres = try await provider.fetchGenreIDs(storefront: sf)
                } catch {
                    CLIHelpers.printErr("[\(sf)] genre fetch error: \(error)")
                    continue
                }
                CLIHelpers.printErr("[\(sf)] Found \(genres.count) genres.")

                // Global chart (no genre filter)
                do {
                    let songs = try await provider.fetchChartSongs(storefront: sf, genreID: nil, limit: perChartLimit)
                    let before = seen.count
                    for song in songs {
                        addSong(artist: song.attributes.artistName, title: song.attributes.name, album: song.attributes.albumName ?? "")
                    }
                    CLIHelpers.printErr("[\(sf)/global] \(songs.count) songs, \(seen.count - before) new (\(seen.count) unique total)")
                } catch {
                    CLIHelpers.printErr("[\(sf)/global] error: \(error)")
                }

                for genre in genres {
                    do {
                        let songs = try await provider.fetchChartSongs(storefront: sf, genreID: genre.id, limit: perChartLimit)
                        let before = seen.count
                        for song in songs {
                            addSong(artist: song.attributes.artistName, title: song.attributes.name, album: song.attributes.albumName ?? "")
                        }
                        CLIHelpers.printErr("[\(sf)/\(genre.name)] \(songs.count) songs, \(seen.count - before) new (\(seen.count) unique total)")
                    } catch {
                        CLIHelpers.printErr("[\(sf)/\(genre.name)] error: \(error)")
                    }
                }
            }
        } else {
            // Single storefront mode via MusicCatalogChartsRequest (user's home)
            CLIHelpers.printErr("Fetching all genres...")
            let genres = try await provider.fetchAllGenres()
            let topLevel = genres.filter { $0.parent == nil }.count
            CLIHelpers.printErr("Found \(genres.count) genres (\(topLevel) top-level, \(genres.count - topLevel) subgenres).")

            func collectCharts(label: String, genre: Genre?) async {
                do {
                    let charts = try await provider.fetchChartSongs(genre: genre, limit: perChartLimit)
                    for chart in charts {
                        let before = seen.count
                        for song in chart.songs {
                            addSong(artist: song.artistName, title: song.title, album: song.albumTitle ?? "")
                        }
                        CLIHelpers.printErr("[\(label) — \(chart.title)] \(chart.songs.count) songs, \(seen.count - before) new (\(seen.count) unique total)")
                    }
                } catch {
                    CLIHelpers.printErr("[\(label)] error: \(error)")
                }
            }

            await collectCharts(label: "global", genre: nil)
            for genre in genres {
                await collectCharts(label: genre.name, genre: genre)
            }
        }

        CLIHelpers.printErr("Total unique tracks: \(seen.count)")
        print(csvLines.joined(separator: "\n") + "\n", terminator: "")
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
