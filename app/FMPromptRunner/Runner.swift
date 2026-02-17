import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

struct PromptEntry: Codable {
    let prompt: String
}

struct OutputEntry: Codable {
    let prompt: String
    let response: String
    var facts: String?
}

struct InstructionsFile: Codable {
    let instructions: String
    var extraction: String?
    var examples: [String: String]?
}

func run(_ args: [String], limit: Int? = nil) async {
    let promptsPath = args[0]
    let instructionsPath = args[1]
    let outputPath = args[2]

    // Read instructions file — JSON with {instructions, extraction?} or plain text fallback
    guard let instructionsData = FileManager.default.contents(atPath: instructionsPath),
          let rawContent = String(data: instructionsData, encoding: .utf8) else {
        logger.error("Failed to read instructions file: \(instructionsPath, privacy: .public)")
        print("Error: cannot read \(instructionsPath)")
        exit(1)
    }

    let trimmedInstructions: String
    var extractionInstructions: String? = nil
    var genreExamples: [String: String] = [:]

    if let jsonData = rawContent.data(using: .utf8),
       let parsed = try? JSONDecoder().decode(InstructionsFile.self, from: jsonData) {
        trimmedInstructions = parsed.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        extractionInstructions = parsed.extraction?.trimmingCharacters(in: .whitespacesAndNewlines)
        genreExamples = parsed.examples ?? [:]
        logger.info("Loaded JSON instructions (\(trimmedInstructions.count) chars, extraction: \(extractionInstructions != nil), examples: \(genreExamples.count))")
    } else {
        // Plain text fallback
        trimmedInstructions = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("Loaded plain text instructions (\(trimmedInstructions.count) chars)")
    }

    if extractionInstructions == nil {
        print("Warning: no \"extraction\" field in instructions — extraction step will use default prompt")
        extractionInstructions = "List the factual details stated in the context as a short numbered list. If no facts are found, output only 'NA'. Do not hallucinate. Do not make up factual information."
    }

    // Read prompts JSONL
    guard let promptsData = FileManager.default.contents(atPath: promptsPath),
          let promptsContent = String(data: promptsData, encoding: .utf8) else {
        logger.error("Failed to read prompts file: \(promptsPath, privacy: .public)")
        print("Error: cannot read \(promptsPath)")
        exit(1)
    }

    let decoder = JSONDecoder()
    let lines = promptsContent.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    var entries: [PromptEntry] = []
    for (i, line) in lines.enumerated() {
        guard let data = line.data(using: .utf8) else { continue }
        do {
            let entry = try decoder.decode(PromptEntry.self, from: data)
            entries.append(entry)
        } catch {
            logger.error("Failed to parse line \(i + 1): \(error.localizedDescription, privacy: .public)")
            print("Warning: skipping line \(i + 1): \(error.localizedDescription)")
        }
    }
    if let limit {
        entries = Array(entries.prefix(limit))
        print("Loaded \(entries.count) prompts (limited to \(limit))")
    } else {
        print("Loaded \(entries.count) prompts")
    }

    #if canImport(FoundationModels)
    guard #available(macOS 26, *) else {
        print("Error: requires macOS 26+")
        exit(1)
    }

    // Check model availability
    let model = SystemLanguageModel.default
    switch model.availability {
    case .available:
        break
    case .unavailable(let reason):
        print("Error: Apple Intelligence unavailable — \(reason)")
        exit(1)
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    // Open output file
    FileManager.default.createFile(atPath: outputPath, contents: nil)
    guard let fileHandle = FileHandle(forWritingAtPath: outputPath) else {
        print("Error: cannot open \(outputPath) for writing")
        exit(1)
    }
    defer { fileHandle.closeFile() }

    print("Stage 1: extract facts → Stage 2: write liner note")

    for (i, entry) in entries.enumerated() {
        let preview = entry.prompt.count > 60 ? String(entry.prompt.prefix(60)) + "…" : entry.prompt
        logger.info("[\(i + 1)/\(entries.count)] Generating: \(preview, privacy: .public)")
        print("[\(i + 1)/\(entries.count)] \(preview)...", terminator: " ")

        do {
            let response: String
            var extractedFacts: String? = nil

            // Strip the task line to get just the track header + context
            let promptLines = entry.prompt.components(separatedBy: "\n")
            let contextPrompt = promptLines
                .drop(while: { $0.hasPrefix("Write") || $0.trimmingCharacters(in: .whitespaces).isEmpty })
                .joined(separator: "\n")

            // Extract track header (everything before [Context])
            let trackHeader: String
            if let range = contextPrompt.range(of: "\n\n[Context]") {
                trackHeader = String(contextPrompt[contextPrompt.startIndex..<range.lowerBound])
            } else {
                trackHeader = contextPrompt
            }

            // Stage 1: Extract facts
            let extractSession = LanguageModelSession(instructions: extractionInstructions!)
            let extractResult = try await extractSession.respond(to: contextPrompt)
            let facts = extractResult.content
            extractedFacts = facts
            logger.info("[\(i + 1)] Facts: \(facts, privacy: .public)")

            // Skip writing if extraction found nothing notable
            if facts.trimmingCharacters(in: .whitespacesAndNewlines) == "NA" {
                response = "I don't know much about this one, sorry!"
                print("SKIP (no notable facts)")
            } else {
                // Stage 2: Write liner note from extracted facts
                // Parse genre from trackHeader — e.g. "Genre: Latin"
                var writeInstructions = trimmedInstructions
                if let genreLine = trackHeader.components(separatedBy: "\n")
                    .first(where: { $0.hasPrefix("Genre:") }) {
                    let genre = genreLine.replacingOccurrences(of: "Genre:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    let example = genreExamples[genre] ?? genreExamples["default"] ?? ""
                    if !example.isEmpty {
                        writeInstructions += "\n\nStyle example (DO NOT use content from this example):\n\(example)"
                    }
                }

                let writePrompt = """
                Write a short liner note using only the facts below.

                \(trackHeader)

                [Facts]
                \(facts)
                [End of Facts]
                """
                let writeSession = LanguageModelSession(instructions: writeInstructions)
                let writeResult = try await writeSession.respond(to: writePrompt)
                response = writeResult.content
            }

            let output = OutputEntry(
                prompt: entry.prompt,
                response: response,
                facts: extractedFacts
            )

            let jsonData = try encoder.encode(output)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                fileHandle.write((jsonString + "\n").data(using: .utf8)!)
            }

            // Truncate for display
            let responsePreview = response.count > 80 ? String(response.prefix(80)) + "..." : response
            print("OK — \(responsePreview)")
            logger.info("[\(i + 1)] Response: \(response, privacy: .public)")
        } catch {
            print("FAILED — \(error.localizedDescription)")
            logger.error("[\(i + 1)] Error: \(error.localizedDescription, privacy: .public)")
        }
    }

    print("\nDone. Wrote \(outputPath)")
    #else
    print("Error: FoundationModels not available (requires macOS 26 SDK)")
    exit(1)
    #endif
}
