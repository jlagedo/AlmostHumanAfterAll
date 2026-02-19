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
}

struct InstructionsFile: Codable {
    let instructions: String
}

func run(_ args: [String], limit: Int? = nil, temperature: Double = 0.5) async {
    let promptsPath = args[0]
    let instructionsPath = args[1]
    let outputPath = args[2]

    // Read instructions file
    guard let instructionsData = FileManager.default.contents(atPath: instructionsPath),
          let rawContent = String(data: instructionsData, encoding: .utf8) else {
        logger.error("Failed to read instructions file: \(instructionsPath, privacy: .public)")
        print("Error: cannot read \(instructionsPath)")
        exit(1)
    }

    let instructions: String
    if let jsonData = rawContent.data(using: .utf8),
       let parsed = try? JSONDecoder().decode(InstructionsFile.self, from: jsonData) {
        instructions = parsed.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("Loaded JSON instructions (\(instructions.count) chars)")
    } else {
        instructions = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("Loaded plain text instructions (\(instructions.count) chars)")
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

    let model = SystemLanguageModel.default
    switch model.availability {
    case .available:
        break
    case .unavailable(let reason):
        print("Error: Apple Intelligence unavailable — \(reason)")
        exit(1)
    }

    // Load LoRA adapter from bundle
    var adapter: SystemLanguageModel.Adapter?
    if let url = Bundle.main.url(forResource: "ficino_music", withExtension: "fmadapter") {
        do {
            adapter = try SystemLanguageModel.Adapter(fileURL: url)
            print("Loaded adapter: ficino_music.fmadapter")
        } catch {
            print("Warning: failed to load adapter — \(error.localizedDescription)")
        }
    } else {
        print("No adapter found in bundle, using base model")
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    FileManager.default.createFile(atPath: outputPath, contents: nil)
    guard let fileHandle = FileHandle(forWritingAtPath: outputPath) else {
        print("Error: cannot open \(outputPath) for writing")
        exit(1)
    }
    defer { fileHandle.closeFile() }

    for (i, entry) in entries.enumerated() {
        let preview = entry.prompt.count > 60 ? String(entry.prompt.prefix(60)) + "…" : entry.prompt
        logger.info("[\(i + 1)/\(entries.count)] Generating: \(preview, privacy: .public)")
        print("[\(i + 1)/\(entries.count)] \(preview)...", terminator: " ")

        do {
            let session: LanguageModelSession
            if let adapter {
                session = LanguageModelSession(model: SystemLanguageModel(adapter: adapter), instructions: instructions)
            } else {
                session = LanguageModelSession(instructions: instructions)
            }
            let result = try await session.respond(to: entry.prompt, options: GenerationOptions(temperature: temperature))
            let response = result.content

            let output = OutputEntry(prompt: entry.prompt, response: response)
            let jsonData = try encoder.encode(output)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                fileHandle.write((jsonString + "\n").data(using: .utf8)!)
            }

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
