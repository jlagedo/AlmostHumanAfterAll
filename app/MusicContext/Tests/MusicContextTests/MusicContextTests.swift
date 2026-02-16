import Foundation
import Testing
@testable import MusicContext

// MARK: - Domain Model Tests

@Test func trackContextDefaults() {
    let track = TrackContext(title: "Test Track")
    #expect(track.title == "Test Track")
    #expect(track.genres.isEmpty)
    #expect(track.tags.isEmpty)
    #expect(track.durationMs == nil)
    #expect(track.isrc == nil)
    #expect(track.communityRating == nil)
    #expect(track.musicBrainzId == nil)
}

@Test func artistContextDefaults() {
    let artist = ArtistContext(name: "Test Artist")
    #expect(artist.name == "Test Artist")
    #expect(artist.type == nil)
    #expect(artist.country == nil)
    #expect(artist.activeSince == nil)
    #expect(artist.similarArtists.isEmpty)
    #expect(artist.members.isEmpty)
}

@Test func albumContextDefaults() {
    let album = AlbumContext(title: "Test Album")
    #expect(album.title == "Test Album")
    #expect(album.label == nil)
    #expect(album.trackCount == nil)
    #expect(album.albumType == nil)
}

@Test func musicContextDataComposition() {
    let ctx = MusicContextData(
        track: TrackContext(title: "Song", genres: ["rock"]),
        artist: ArtistContext(name: "Band", country: "US"),
        album: AlbumContext(title: "Album", trackCount: 12)
    )
    #expect(ctx.track.genres == ["rock"])
    #expect(ctx.artist.country == "US")
    #expect(ctx.album.trackCount == 12)
    #expect(ctx.trivia.awards.isEmpty)
}

// MARK: - API Model Decoding Tests

@Test func decodeRecordingSearchResponse() throws {
    let json = """
    {
        "created": "2024-01-01T00:00:00Z",
        "count": 1,
        "offset": 0,
        "recordings": [{
            "id": "abc-123",
            "score": 100,
            "title": "Aja",
            "length": 475000,
            "first-release-date": "1977",
            "artist-credit": [{
                "name": "Steely Dan",
                "artist": {
                    "id": "def-456",
                    "name": "Steely Dan",
                    "sort-name": "Steely Dan"
                }
            }],
            "releases": [{
                "id": "rel-789",
                "title": "Aja",
                "status": "Official",
                "date": "1977-09-23",
                "country": "US",
                "track-count": 7,
                "release-group": {
                    "id": "rg-111",
                    "title": "Aja",
                    "primary-type": "Album"
                }
            }]
        }]
    }
    """
    let data = json.data(using: .utf8)!
    let result = try JSONDecoder().decode(MBRecordingSearchResponse.self, from: data)
    #expect(result.count == 1)
    #expect(result.recordings.count == 1)
    let rec = result.recordings[0]
    #expect(rec.id == "abc-123")
    #expect(rec.score == 100)
    #expect(rec.title == "Aja")
    #expect(rec.length == 475000)
    #expect(rec.firstReleaseDate == "1977")
    #expect(rec.artistCredit?.first?.artist.name == "Steely Dan")
    #expect(rec.artistCredit?.first?.artist.sortName == "Steely Dan")
    #expect(rec.releases?.first?.status == "Official")
    #expect(rec.releases?.first?.trackCount == 7)
    #expect(rec.releases?.first?.releaseGroup?.primaryType == "Album")
}

@Test func decodeRecordingLookup() throws {
    let json = """
    {
        "id": "abc-123",
        "title": "Aja",
        "length": 475000,
        "video": false,
        "first-release-date": "1977",
        "tags": [
            {"name": "jazz rock", "count": 5},
            {"name": "fusion", "count": 3}
        ],
        "genres": [
            {"id": "g1", "name": "jazz-rock", "count": 5, "disambiguation": ""}
        ],
        "rating": {"value": 4.5, "votes-count": 10},
        "isrcs": ["USAB12345678"],
        "artist-credit": [{
            "name": "Steely Dan",
            "artist": {
                "id": "def-456",
                "name": "Steely Dan",
                "sort-name": "Steely Dan"
            }
        }]
    }
    """
    let data = json.data(using: .utf8)!
    let result = try JSONDecoder().decode(MBRecordingLookup.self, from: data)
    #expect(result.tags?.count == 2)
    #expect(result.tags?.first?.name == "jazz rock")
    #expect(result.genres?.first?.name == "jazz-rock")
    #expect(result.rating?.value == 4.5)
    #expect(result.rating?.votesCount == 10)
    #expect(result.isrcs?.first == "USAB12345678")
}

@Test func decodeArtistFull() throws {
    let json = """
    {
        "id": "def-456",
        "name": "Steely Dan",
        "sort-name": "Steely Dan",
        "type": "Group",
        "country": "US",
        "life-span": {
            "begin": "1972",
            "end": "2017",
            "ended": true
        },
        "area": {
            "id": "area-1",
            "name": "United States",
            "sort-name": "United States",
            "iso-3166-1-codes": ["US"]
        }
    }
    """
    let data = json.data(using: .utf8)!
    let result = try JSONDecoder().decode(MBArtistFull.self, from: data)
    #expect(result.type == "Group")
    #expect(result.country == "US")
    #expect(result.lifeSpan?.begin == "1972")
    #expect(result.lifeSpan?.end == "2017")
    #expect(result.lifeSpan?.ended == true)
    #expect(result.area?.iso31661Codes == ["US"])
}

@Test func decodeReleaseLookup() throws {
    let json = """
    {
        "id": "rel-789",
        "title": "Aja",
        "status": "Official",
        "date": "1977-09-23",
        "country": "US",
        "label-info": [{
            "catalog-number": "AA-1006",
            "label": {
                "id": "lbl-1",
                "name": "ABC Records",
                "sort-name": "ABC Records"
            }
        }],
        "media": [{
            "position": 1,
            "format": "12\\" Vinyl",
            "track-count": 7
        }],
        "release-group": {
            "id": "rg-111",
            "title": "Aja",
            "primary-type": "Album",
            "secondary-types": [],
            "first-release-date": "1977-09-23"
        }
    }
    """
    let data = json.data(using: .utf8)!
    let result = try JSONDecoder().decode(MBReleaseLookup.self, from: data)
    #expect(result.title == "Aja")
    #expect(result.status == "Official")
    #expect(result.labelInfo?.first?.label?.name == "ABC Records")
    #expect(result.labelInfo?.first?.catalogNumber == "AA-1006")
    #expect(result.media?.first?.trackCount == 7)
    #expect(result.releaseGroup?.primaryType == "Album")
    #expect(result.releaseGroup?.firstReleaseDate == "1977-09-23")
}
