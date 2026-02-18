import Testing
@testable import MusicModel

@Suite struct TrackInputTests {
    @Test func initSetsAllFields() {
        let input = TrackInput(name: "Song", artist: "Artist", album: "Album", genre: "Rock", durationString: "3:45")
        #expect(input.name == "Song")
        #expect(input.artist == "Artist")
        #expect(input.album == "Album")
        #expect(input.genre == "Rock")
        #expect(input.durationString == "3:45")
    }

    @Test func emptyGenreIsValid() {
        let input = TrackInput(name: "Song", artist: "Artist", album: "Album", genre: "", durationString: "0:00")
        #expect(input.genre.isEmpty)
    }
}

@Suite struct AppleIntelligenceErrorTests {
    @Test func errorDescription() {
        let error = AppleIntelligenceError.unavailable("test message")
        #expect(error.errorDescription == "test message")
    }
}
