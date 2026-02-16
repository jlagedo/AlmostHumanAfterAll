import MusicContext

enum GeniusFormatter {
    static func printContext(_ context: MusicContextData) {
        print("── Track (Genius) ─────────────────────────")
        print("  Title:       \(context.track.title)")
        if let summary = context.track.wikiSummary {
            let text = summary.count > 500 ? String(summary.prefix(500)) + "..." : summary
            print("  Description: \(text)")
        }
        print()

        print("── Artist ─────────────────────────────────")
        print("  Name:        \(context.artist.name)")
        if let bio = context.artist.bio {
            let text = bio.count > 500 ? String(bio.prefix(500)) + "..." : bio
            print("  Bio:         \(text)")
        }
        print()

        print("── Album ──────────────────────────────────")
        print("  Title:       \(context.album.title)")
        print()

        print("── Trivia ─────────────────────────────────")
        if !context.trivia.songwriters.isEmpty {
            print("  Songwriters: \(context.trivia.songwriters.joined(separator: ", "))")
        }
        if !context.trivia.producers.isEmpty {
            print("  Producers:   \(context.trivia.producers.joined(separator: ", "))")
        }
        if !context.trivia.samples.isEmpty {
            print("  Samples:")
            for sample in context.trivia.samples {
                print("    - \(sample)")
            }
        }
        if !context.trivia.sampledBy.isEmpty {
            print("  Sampled By:")
            for sample in context.trivia.sampledBy {
                print("    - \(sample)")
            }
        }
        if !context.trivia.influences.isEmpty {
            print("  Influences:")
            for influence in context.trivia.influences {
                print("    - \(influence)")
            }
        }
        if context.trivia.songwriters.isEmpty && context.trivia.producers.isEmpty &&
           context.trivia.samples.isEmpty && context.trivia.sampledBy.isEmpty &&
           context.trivia.influences.isEmpty {
            print("  (no trivia data found)")
        }
        print()
    }
}
