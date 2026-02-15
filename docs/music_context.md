

import Foundation
import FoundationModels

// ============================================================================
// MARK: - MusicContext Fase 2
// ============================================================================
//
// Pipeline: Fetch → Normalize → Score → Select → Compact → Prompt
//
// Design principles:
//   - The on-device Foundation Model (~3B) has NO world knowledge.
//     It cannot fill in gaps. All facts must come from the API data.
//   - The model's only job: rephrase curated facts into natural language.
//   - All intelligence (selection, scoring, prioritization) lives in Swift.
//   - Hard limit: 4,096 tokens total (input + output) per session.
//   - Token budget: ~200 tokens for instructions/framing, ~150 tokens for
//     output struct overhead, ~600 tokens for 3 generated facts ≈ 950 tokens
//     reserved → ~3,100 tokens available for curated facts (~10,000 chars).
//   - In practice, target ≤ 2,000 chars of fact payload for safety margin.
//
// API sources (4):
//   1. MusicBrainz  — structured metadata (no key, 1 req/sec)
//   2. Wikipedia     — narrative bios/summaries (no key)
//   3. Wikidata      — structured trivia: awards, charts, credits (no key)
//   4. Last.fm       — bio fallback, similar artists, listener stats (free key)
//
// ============================================================================


// MARK: - Pipeline Output: @Generable struct for Foundation Models

/// The structured output the model produces. Using @Generable ensures
/// constrained decoding — the model fills each field sequentially.
/// Property order matters: the model generates top-to-bottom.
@Generable
struct MusicInsights {
    @Guide(description: "A fun or surprising fact about this specific track")
    var trackFact: String

    @Guide(description: "An interesting historical or biographical fact about the artist")
    var artistFact: String

    @Guide(description: "A notable fact or curiosity about the album")
    var albumFact: String
}


// MARK: - Scored Fact (internal pipeline type)

/// A single atomic fact extracted from API data, scored for interestingness.
/// The pipeline scores all available facts, sorts by score, and picks the top N
/// that fit within the token budget.
struct ScoredFact: Comparable {
    let text: String            // The compact, pre-formatted fact string
    let score: Int              // Higher = more interesting (0-100)
    let category: FactCategory  // Which domain it belongs to
    let charCount: Int          // Pre-computed for budget tracking

    static func < (lhs: ScoredFact, rhs: ScoredFact) -> Bool {
        lhs.score < rhs.score
    }

    enum FactCategory: String {
        case track
        case artist
        case album
        case trivia
    }
}


// MARK: - Unified Data Model (Fetch + Normalize layers)

/// Raw aggregated data from all 4 API sources. Every optional field that is nil
/// means the data was not available from any source.
struct MusicContext: Codable, Sendable {
    var track: TrackContext
    var artist: ArtistContext
    var album: AlbumContext
    var trivia: TriviaContext

    // ========================================================================
    // MARK: Score Layer — extract and score all atomic facts
    // ========================================================================

    /// Extracts every available fact from the aggregated data and assigns
    /// an interestingness score. Pure deterministic heuristics, no LLM needed.
    func scoreFacts() -> [ScoredFact] {
        var facts: [ScoredFact] = []

        // --- Track facts ---

        if !trivia.samples.isEmpty {
            let s = "This track samples: \(trivia.samples.joined(separator: ", "))"
            facts.append(ScoredFact(text: s, score: 90, category: .trivia, charCount: s.count))
        }

        if !trivia.sampledBy.isEmpty {
            let s = "This track has been sampled by: \(trivia.sampledBy.joined(separator: ", "))"
            facts.append(ScoredFact(text: s, score: 90, category: .trivia, charCount: s.count))
        }

        if !trivia.songwriters.isEmpty {
            let performerIsWriter = trivia.songwriters.count == 1
                && trivia.songwriters.first?.lowercased() == artist.name.lowercased()
            if !performerIsWriter {
                let s = "Written by: \(trivia.songwriters.joined(separator: ", "))"
                // Higher score if written by someone else (more surprising)
                facts.append(ScoredFact(text: s, score: 75, category: .track, charCount: s.count))
            }
        }

        if !trivia.producers.isEmpty {
            let s = "Produced by: \(trivia.producers.joined(separator: ", "))"
            facts.append(ScoredFact(text: s, score: 60, category: .track, charCount: s.count))
        }

        if let wiki = track.wikiSummary, !wiki.isEmpty {
            let truncated = String(wiki.prefix(400))
            let s = "About this track: \(truncated)"
            facts.append(ScoredFact(text: s, score: 65, category: .track, charCount: s.count))
        }

        if !track.genres.isEmpty {
            let s = "Genre: \(track.genres.prefix(4).joined(separator: ", "))"
            facts.append(ScoredFact(text: s, score: 30, category: .track, charCount: s.count))
        }

        // --- Artist facts ---

        if !trivia.awards.isEmpty {
            let top = Array(trivia.awards.prefix(5))
            let s = "Awards: \(top.joined(separator: "; "))"
            // Major awards are very high value
            let hasGrammy = trivia.awards.contains { $0.lowercased().contains("grammy") }
            let hasOscar = trivia.awards.contains { $0.lowercased().contains("oscar") || $0.lowercased().contains("academy") }
            let bonus = (hasGrammy ? 10 : 0) + (hasOscar ? 10 : 0)
            facts.append(ScoredFact(text: s, score: 85 + bonus, category: .artist, charCount: s.count))
        }

        if let bio = artist.bio, !bio.isEmpty {
            let truncated = String(bio.prefix(500))
            let s = "Artist bio: \(truncated)"
            facts.append(ScoredFact(text: s, score: 55, category: .artist, charCount: s.count))
        }

        if let since = artist.activeSince {
            let yearsActive = activeYears(from: since)
            let s: String
            if let until = artist.activeUntil {
                s = "\(artist.name) was active from \(since) to \(until)"
            } else {
                s = "\(artist.name) has been active since \(since)"
            }
            // Longevity bonus: 30+ years is interesting
            let bonus = yearsActive > 30 ? 20 : (yearsActive > 20 ? 10 : 0)
            facts.append(ScoredFact(text: s, score: 40 + bonus, category: .artist, charCount: s.count))
        }

        if let country = artist.country {
            let s = "Origin: \(country)"
            facts.append(ScoredFact(text: s, score: 20, category: .artist, charCount: s.count))
        }

        if let type = artist.type {
            let s = "\(artist.name) is a \(type.lowercased())"
            facts.append(ScoredFact(text: s, score: 15, category: .artist, charCount: s.count))
        }

        if !artist.members.isEmpty {
            let s = "Members: \(artist.members.joined(separator: ", "))"
            facts.append(ScoredFact(text: s, score: 50, category: .artist, charCount: s.count))
        }

        if !trivia.influences.isEmpty {
            let s = "Influenced by: \(trivia.influences.prefix(5).joined(separator: ", "))"
            facts.append(ScoredFact(text: s, score: 70, category: .artist, charCount: s.count))
        }

        if !artist.similarArtists.isEmpty {
            let s = "Similar artists: \(artist.similarArtists.prefix(5).joined(separator: ", "))"
            facts.append(ScoredFact(text: s, score: 25, category: .artist, charCount: s.count))
        }

        if let listeners = artist.listeners {
            let formatted = formatNumber(listeners)
            let s = "\(formatted) listeners on Last.fm"
            facts.append(ScoredFact(text: s, score: 35, category: .artist, charCount: s.count))
        }

        // --- Album facts ---

        if !trivia.chartPositions.isEmpty {
            let top = trivia.chartPositions
                .sorted { $0.position < $1.position }
                .prefix(3)
            let charts = top.map { entry -> String in
                var s = "\(entry.chart): #\(entry.position)"
                if let y = entry.year { s += " (\(y))" }
                return s
            }
            let s = "Chart positions: \(charts.joined(separator: "; "))"
            // #1 positions are extra interesting
            let hasNumber1 = trivia.chartPositions.contains { $0.position == 1 }
            let bonus = hasNumber1 ? 15 : 0
            facts.append(ScoredFact(text: s, score: 80 + bonus, category: .album, charCount: s.count))
        }

        if let wiki = album.wikiSummary, !wiki.isEmpty {
            let truncated = String(wiki.prefix(400))
            let s = "About this album: \(truncated)"
            facts.append(ScoredFact(text: s, score: 55, category: .album, charCount: s.count))
        }

        if let date = album.releaseDate, let label = album.label {
            let s = "Released \(date) on \(label)"
            facts.append(ScoredFact(text: s, score: 35, category: .album, charCount: s.count))
        } else if let date = album.releaseDate {
            let s = "Released \(date)"
            facts.append(ScoredFact(text: s, score: 25, category: .album, charCount: s.count))
        }

        if let count = album.trackCount, count > 0 {
            let s = "Album has \(count) tracks"
            facts.append(ScoredFact(text: s, score: 15, category: .album, charCount: s.count))
        }

        return facts
    }

    // ========================================================================
    // MARK: Select Layer — pick top facts within token budget
    // ========================================================================

    /// Selects the highest-scoring facts that fit within the character budget.
    /// Ensures at least one fact per category when available, to give the model
    /// material for each field in MusicInsights.
    func selectFacts(maxChars: Int = 2000) -> [ScoredFact] {
        let allFacts = scoreFacts()
        guard !allFacts.isEmpty else { return [] }

        var selected: [ScoredFact] = []
        var usedChars = 0
        var coveredCategories: Set<ScoredFact.FactCategory> = []

        // Pass 1: pick the highest-scoring fact per category to ensure coverage
        let categories: [ScoredFact.FactCategory] = [.track, .artist, .album, .trivia]
        for cat in categories {
            if let best = allFacts
                .filter({ $0.category == cat })
                .sorted(by: >)
                .first,
               usedChars + best.charCount <= maxChars {
                selected.append(best)
                usedChars += best.charCount
                coveredCategories.insert(cat)
            }
        }

        // Pass 2: fill remaining budget with highest-scoring unused facts
        let usedTexts = Set(selected.map(\.text))
        let remaining = allFacts
            .filter { !usedTexts.contains($0.text) }
            .sorted(by: >)

        for fact in remaining {
            if usedChars + fact.charCount > maxChars { continue }
            selected.append(fact)
            usedChars += fact.charCount
        }

        return selected.sorted(by: >)
    }

    // ========================================================================
    // MARK: Compact + Prompt Layer — build the final prompt string
    // ========================================================================

    /// Builds the complete prompt for Foundation Models.
    /// The prompt is designed for a model with no world knowledge:
    ///   - Explicit instruction to use ONLY provided data
    ///   - Pre-curated facts (already scored and selected)
    ///   - Tight, declarative format the model just needs to rephrase
    func buildPrompt() -> String {
        let selected = selectFacts()
        guard !selected.isEmpty else {
            return """
            Track: "\(track.title)" by \(artist.name) on album "\(album.title)".
            No additional information is available.
            Write 3 short observations based only on the track, artist, and album names.
            """
        }

        let header = """
        Now playing: "\(track.title)" by \(artist.name) from the album "\(album.title)".
        """

        let factsBlock = selected
            .map { "- \($0.text)" }
            .joined(separator: "\n")

        return """
        \(header)

        Known facts:
        \(factsBlock)

        Using ONLY the facts listed above, write 3 short fun facts a music fan would enjoy. Do not make up any information not provided above.
        """
    }

    // ========================================================================
    // MARK: Generate — run the full pipeline and call Foundation Models
    // ========================================================================

    /// Runs the complete pipeline: score → select → compact → prompt → generate.
    /// Returns structured MusicInsights via guided generation.
    func generateInsights() async throws -> MusicInsights {
        let session = LanguageModelSession(
            model: .default,
            instructions: """
            You are a music trivia writer. You rephrase provided facts into \
            short, engaging sentences. You NEVER add information that is not \
            in the provided facts. Keep each fact to 1-2 sentences.
            """
        )

        let prompt = buildPrompt()
        let response = try await session.respond(to: prompt, generating: MusicInsights.self)
        return response
    }

    // ========================================================================
    // MARK: Private helpers
    // ========================================================================

    private func activeYears(from dateString: String) -> Int {
        // dateString can be "1962", "1962-01", or "1962-01-01"
        guard let yearStr = dateString.split(separator: "-").first,
              let year = Int(yearStr) else { return 0 }
        return Calendar.current.component(.year, from: Date()) - year
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        } else if n >= 1_000 {
            return String(format: "%.0fK", Double(n) / 1_000)
        }
        return "\(n)"
    }
}


// MARK: - Track

struct TrackContext: Codable, Sendable {
    var title: String
    var durationMs: Int?                    // MusicBrainz: length
    var genres: [String] = []               // MusicBrainz: genres[] + tags[]
    var tags: [String] = []                 // MusicBrainz: tags[], Last.fm: toptags
    var isrc: String?                       // MusicBrainz: isrcs[0]
    var communityRating: Double?            // MusicBrainz: rating.value (0-5)
    var wikiSummary: String?                // Last.fm: track.getInfo → wiki.summary
    var musicBrainzId: String?              // MBID for cross-referencing

    var durationFormatted: String? {
        guard let ms = durationMs else { return nil }
        let totalSeconds = ms / 1000
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }
}


// MARK: - Artist

struct ArtistContext: Codable, Sendable {
    var name: String
    var type: String?                       // MusicBrainz: "Group" | "Person"
    var country: String?                    // MusicBrainz: country (ISO code)
    var activeSince: String?                // MusicBrainz: life-span.begin
    var activeUntil: String?                // MusicBrainz: life-span.end (nil = still active)
    var disambiguation: String?             // MusicBrainz: disambiguation
    var bio: String?                        // Wikipedia: extract OR Last.fm: bio.summary
    var description: String?                // Wikipedia: description (one-liner)
    var listeners: Int?                     // Last.fm: stats.listeners
    var playcount: Int?                     // Last.fm: stats.playcount
    var similarArtists: [String] = []       // Last.fm: similar.artist[].name
    var members: [String] = []              // Wikidata: P527 (has parts) for groups
    var musicBrainzId: String?              // MBID
    var wikidataId: String?                 // QID for Wikidata lookups
}


// MARK: - Album

struct AlbumContext: Codable, Sendable {
    var title: String
    var releaseDate: String?                // MusicBrainz: date
    var country: String?                    // MusicBrainz: country
    var label: String?                      // MusicBrainz: label-info[0].label.name
    var trackCount: Int?                    // MusicBrainz: media[0].track-count
    var status: String?                     // MusicBrainz: status ("Official", etc.)
    var albumType: String?                  // MusicBrainz: release-group.primary-type
    var wikiSummary: String?                // Wikipedia: extract for album
    var musicBrainzId: String?              // MBID
}


// MARK: - Trivia (Wikidata structured facts)

struct TriviaContext: Codable, Sendable {
    var awards: [String] = []               // Wikidata P166: award received
    var chartPositions: [ChartPosition] = []// Wikidata P2291 + P1352
    var songwriters: [String] = []          // Wikidata P676: lyrics by + P86: composer
    var producers: [String] = []            // Wikidata P162: producer
    var samples: [String] = []              // Wikidata P6883: samples from
    var sampledBy: [String] = []            // Wikidata P6884: sampled by
    var influences: [String] = []           // Wikidata P737: influenced by (artist)
    var recordLabel: String?                // Wikidata P264: record label
}

struct ChartPosition: Codable, Sendable {
    var chart: String                       // e.g. "Billboard Hot 100", "UK Singles"
    var position: Int
    var year: Int?
}


// MARK: - Source tracking (for progressive loading)

struct SourceStatus: Sendable {
    var musicBrainz: LoadState = .pending
    var wikipedia: LoadState = .pending
    var wikidata: LoadState = .pending
    var lastFm: LoadState = .pending

    var allCompleted: Bool {
        [musicBrainz, wikipedia, wikidata, lastFm]
            .allSatisfy { $0 != .pending && $0 != .loading }
    }

    enum LoadState: Sendable {
        case pending
        case loading
        case loaded
        case failed(String)
    }
}


// MARK: - Scoring Heuristics Reference
/*
 ┌──────────────────────────────────────────────────────────────────┐
 │ FACT SCORING TABLE                                              │
 ├──────────────────────────────────────┬───────────┬──────────────┤
 │ Fact type                            │ Base score│ Bonuses      │
 ├──────────────────────────────────────┼───────────┼──────────────┤
 │ Track samples another track          │ 90        │              │
 │ Track sampled by other artists       │ 90        │              │
 │ Chart positions                      │ 80        │ +15 if #1    │
 │ Awards (Grammy, Oscar, etc.)         │ 85        │ +10 per major│
 │ Written by someone other than artist │ 75        │              │
 │ Influenced by / influences           │ 70        │              │
 │ Track wiki summary                   │ 65        │              │
 │ Producers                            │ 60        │              │
 │ Artist bio (Wikipedia)               │ 55        │              │
 │ Album wiki summary                   │ 55        │              │
 │ Band members                         │ 50        │              │
 │ Active since (longevity)             │ 40        │ +20 if 30yr+ │
 │ Listener count                       │ 35        │              │
 │ Release date + label                 │ 35        │              │
 │ Genre tags                           │ 30        │              │
 │ Similar artists                      │ 25        │              │
 │ Release date only                    │ 25        │              │
 │ Country of origin                    │ 20        │              │
 │ Track count on album                 │ 15        │              │
 │ Artist type (group/person)           │ 15        │              │
 └──────────────────────────────────────┴───────────┴──────────────┘

 SELECTION STRATEGY:
 1. Guarantee coverage: pick top fact per category (track/artist/album/trivia)
 2. Fill remaining budget with highest-scoring unused facts
 3. Hard cap: ≤ 2,000 chars of fact payload (leaves ~2,000 tokens for
    instructions, framing, output struct overhead, and generated text)

 TOKEN BUDGET BREAKDOWN (4,096 total):
 ┌─────────────────────────────┬──────────────┐
 │ Component                   │ Est. tokens  │
 ├─────────────────────────────┼──────────────┤
 │ Session instructions        │ ~80          │
 │ Prompt framing + header     │ ~60          │
 │ Curated facts payload       │ ~500-600     │
 │ @Generable schema overhead  │ ~150         │
 │ Generated output (3 facts)  │ ~400-600     │
 │ Safety margin               │ ~200         │
 ├─────────────────────────────┼──────────────┤
 │ TOTAL                       │ ~1,500-1,700 │
 │ Remaining headroom          │ ~2,400       │
 └─────────────────────────────┴──────────────┘
*/


// MARK: - API Source → Field Mapping (unchanged from fase1)
/*
 ┌──────────────────────────────────────────────────────────────────┐
 │ SOURCE → FIELD MAPPING                                          │
 ├──────────────┬───────────────────────────────────────────────────┤
 │ MusicBrainz  │ recording search → TrackContext                  │
 │              │   .title           → track.title                 │
 │              │   .length          → track.durationMs            │
 │              │   .isrcs[0]        → track.isrc                  │
 │              │   .tags[].name     → track.tags                  │
 │              │   .genres[].name   → track.genres                │
 │              │   .rating.value    → track.communityRating       │
 │              │   .id              → track.musicBrainzId         │
 │              │                                                  │
 │              │   .artist-credit[0].artist →                     │
 │              │     .name          → artist.name                 │
 │              │     .type          → artist.type                 │
 │              │     .country       → artist.country              │
 │              │     .life-span     → artist.activeSince/Until    │
 │              │     .disambiguation→ artist.disambiguation       │
 │              │     .id            → artist.musicBrainzId        │
 │              │                                                  │
 │              │   .releases[0] →                                 │
 │              │     .title         → album.title                 │
 │              │     .date          → album.releaseDate           │
 │              │     .country       → album.country               │
 │              │     .status        → album.status                │
 │              │     .id            → album.musicBrainzId         │
 │              │                                                  │
 │              │ release lookup (inc=labels+recordings) →         │
 │              │   .label-info[0].label.name → album.label        │
 │              │   .media[0].track-count     → album.trackCount   │
 │              │   .release-group.primary-type → album.albumType  │
 ├──────────────┼───────────────────────────────────────────────────┤
 │ Wikipedia    │ /page/summary/{artist_name}                      │
 │ (REST API)   │   .extract         → artist.bio                  │
 │              │   .description      → artist.description          │
 │              │                                                  │
 │              │ /page/summary/{album_name}_(album)               │
 │              │   .extract         → album.wikiSummary           │
 ├──────────────┼───────────────────────────────────────────────────┤
 │ Wikidata     │ /w/api.php?action=wbgetentities                  │
 │              │   claims.P166     → awards                       │
 │              │   claims.P2291 + P1352  → chartPositions         │
 │              │   claims.P676    → songwriters (lyrics by)       │
 │              │   claims.P86     → songwriters (composer)        │
 │              │   claims.P162    → producers                     │
 │              │   claims.P6883   → samples                       │
 │              │   claims.P6884   → sampledBy                     │
 │              │   claims.P737    → influences (artist)           │
 │              │   claims.P264    → recordLabel                   │
 │              │   claims.P527    → artist.members                │
 │              │                                                  │
 │              │ Resolve QIDs → labels via wbgetentities           │
 │              │ or use the sitelinks.enwiki to get Wikipedia URL │
 ├──────────────┼───────────────────────────────────────────────────┤
 │ Last.fm      │ artist.getInfo (api_key required)                │
 │ (free key)   │   .artist.bio.summary    → artist.bio (fallback)│
 │              │   .artist.similar.artist[].name → similarArtists │
 │              │   .artist.stats.listeners → artist.listeners     │
 │              │   .artist.stats.playcount → artist.playcount     │
 │              │                                                  │
 │              │ track.getInfo                                    │
 │              │   .track.wiki.summary    → track.wikiSummary     │
 │              │   .track.toptags.tag[].name → track.tags (merge) │
 └──────────────┴───────────────────────────────────────────────────┘

 PRIORITY / CONFLICT RESOLUTION:
 - artist.bio: Wikipedia extract preferred, Last.fm bio.summary as fallback
 - track.tags: merge MusicBrainz tags + Last.fm toptags, deduplicate
 - track.genres: MusicBrainz genres only (more structured)
 - album.label: MusicBrainz preferred, Wikidata P264 as fallback
 - All Wikidata QIDs must be resolved to human-readable labels

 LOADING ORDER:
 1. MusicBrainz search    → immediate: basic track/artist/album + MBIDs
 2. Wikipedia summary     → parallel: artist bio, album summary
 3. Last.fm getInfo       → parallel: similar artists, listener stats, track wiki
 4. Wikidata entity       → last: structured trivia (awards, charts, credits)
    (needs artist.wikidataId from MusicBrainz relations or Wikipedia sitelink)
*/
