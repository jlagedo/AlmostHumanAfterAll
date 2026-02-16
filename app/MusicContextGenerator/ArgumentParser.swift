import Foundation

/// Supported music metadata provider types
enum ProviderType: String {
    case musicBrainz = "mb"
    case musicKit = "mk"
    case genius = "g"
}

/// Provider-specific arguments after parsing
enum ProviderArguments {
    case musicBrainz(artist: String, album: String, track: String, durationMs: Int?)
    case musicKit(artist: String, album: String, track: String)
    case musicKitID(catalogID: String)
    case musicKitPlaylist(name: String)
    case genius(artist: String, album: String, track: String)
}

/// Result of parsing command-line arguments
struct ParsedArguments {
    let providerType: ProviderType
    let arguments: ProviderArguments
}

/// Parses command-line arguments with provider flag
func parseArguments(_ args: [String]) throws -> ParsedArguments {
    guard args.count >= 2 else {
        throw ArgumentError.missingProviderFlag
    }

    guard args[0] == "-p" else {
        throw ArgumentError.missingProviderFlag
    }

    guard let providerType = ProviderType(rawValue: args[1]) else {
        throw ArgumentError.invalidProvider(args[1])
    }

    let remainingArgs = Array(args.dropFirst(2))

    switch providerType {
    case .musicBrainz:
        return try parseMusicBrainzArgs(remainingArgs, providerType: providerType)
    case .musicKit:
        return try parseMusicKitArgs(remainingArgs, providerType: providerType)
    case .genius:
        return try parseGeniusArgs(remainingArgs, providerType: providerType)
    }
}

private func parseMusicBrainzArgs(_ args: [String], providerType: ProviderType) throws -> ParsedArguments {
    guard args.count >= 3 else {
        throw ArgumentError.insufficientMusicBrainzArgs(provided: args.count)
    }

    let artist = args[0]
    let album = args[1]
    let track = args[2]
    let durationMs: Int? = args.count >= 4 ? Int(args[3]) : nil

    guard !artist.isEmpty, !album.isEmpty, !track.isEmpty else {
        throw ArgumentError.emptyArgument
    }

    return ParsedArguments(
        providerType: providerType,
        arguments: .musicBrainz(artist: artist, album: album, track: track, durationMs: durationMs)
    )
}

private func parseMusicKitArgs(_ args: [String], providerType: ProviderType) throws -> ParsedArguments {
    guard !args.isEmpty else {
        throw ArgumentError.insufficientMusicKitArgs
    }

    if args[0] == "--id" {
        guard args.count >= 2, !args[1].isEmpty else {
            throw ArgumentError.insufficientMusicKitArgs
        }
        return ParsedArguments(
            providerType: providerType,
            arguments: .musicKitID(catalogID: args[1])
        )
    }

    if args[0] == "--playlist" {
        guard args.count >= 2, !args[1].isEmpty else {
            throw ArgumentError.insufficientMusicKitArgs
        }
        return ParsedArguments(
            providerType: providerType,
            arguments: .musicKitPlaylist(name: args[1])
        )
    }

    guard args.count >= 3 else {
        throw ArgumentError.insufficientMusicKitArgs
    }

    let artist = args[0]
    let album = args[1]
    let track = args[2]

    guard !artist.isEmpty, !album.isEmpty, !track.isEmpty else {
        throw ArgumentError.emptyArgument
    }

    return ParsedArguments(
        providerType: providerType,
        arguments: .musicKit(artist: artist, album: album, track: track)
    )
}

private func parseGeniusArgs(_ args: [String], providerType: ProviderType) throws -> ParsedArguments {
    guard args.count >= 3 else {
        throw ArgumentError.insufficientGeniusArgs(provided: args.count)
    }

    let artist = args[0]
    let album = args[1]
    let track = args[2]

    guard !artist.isEmpty, !album.isEmpty, !track.isEmpty else {
        throw ArgumentError.emptyArgument
    }

    return ParsedArguments(
        providerType: providerType,
        arguments: .genius(artist: artist, album: album, track: track)
    )
}

enum ArgumentError: Error, CustomStringConvertible {
    case missingProviderFlag
    case invalidProvider(String)
    case insufficientMusicBrainzArgs(provided: Int)
    case insufficientMusicKitArgs
    case insufficientGeniusArgs(provided: Int)
    case emptyArgument

    var description: String {
        switch self {
        case .missingProviderFlag:
            return "Missing -p flag. Usage:\n" + usageMessage
        case .invalidProvider(let provider):
            return "Invalid provider '\(provider)'. Valid options: mb, mk, g\n" + usageMessage
        case .insufficientMusicBrainzArgs(let provided):
            return "MusicBrainz mode requires 3-4 arguments (Artist, Album, Track, [DurationMs]), got \(provided)\n" + usageMessage
        case .insufficientMusicKitArgs:
            return "MusicKit mode requires 3 arguments (Artist, Album, Track), --id <CatalogID>, or --playlist <Name>\n" + usageMessage
        case .insufficientGeniusArgs(let provided):
            return "Genius mode requires 3 arguments (Artist, Album, Track), got \(provided)\n" + usageMessage
        case .emptyArgument:
            return "Arguments cannot be empty strings"
        }
    }
}

let usageMessage = """
Usage:
  MusicContextGenerator -p mb <Artist> <Album> <Track> [DurationMs]
  MusicContextGenerator -p mk <Artist> <Album> <Track>
  MusicContextGenerator -p mk --id <CatalogID>
  MusicContextGenerator -p mk --playlist <Name>
  MusicContextGenerator -p g  <Artist> <Album> <Track>

Providers:
  mb (MusicBrainz)  - Search by artist/album/track metadata
  mk (MusicKit)     - Search Apple Music catalog
  g  (Genius)       - Search Genius for songwriting credits, samples, trivia

Examples:
  MusicContextGenerator -p mb "Radiohead" "OK Computer" "Let Down" 299000
  MusicContextGenerator -p mk "Radiohead" "OK Computer" "Let Down"
  MusicContextGenerator -p mk --id 1440933460
  MusicContextGenerator -p mk --playlist "Top 100: Global"
  MusicContextGenerator -p mk --playlist "Top 100: Global" > top100.csv
  MusicContextGenerator -p g  "Radiohead" "OK Computer" "Let Down"
"""
