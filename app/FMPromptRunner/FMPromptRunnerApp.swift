//
//  FMPromptRunnerApp.swift
//  FMPromptRunner
//
//  Created by João Amaro Lagedo on 16/02/26.
//

import SwiftUI
import os

let logger = Logger(subsystem: "com.ficino.FMPromptRunner", category: "main")

@main
struct FMPromptRunnerApp: App {
    var body: some Scene {
        WindowGroup {
            Text("FMPromptRunner — CLI only")
        }
    }

    init() {
        var args = Array(CommandLine.arguments.dropFirst())

        // Parse -limit flag
        var limit: Int?
        if let idx = args.firstIndex(of: "-limit"), idx + 1 < args.count {
            if let n = Int(args[idx + 1]), n > 0 {
                limit = n
            } else {
                print("Error: -limit requires a positive integer")
                exit(1)
            }
            args.removeSubrange(idx...idx + 1)
        }

        // Always runs dual-stage pipeline (extract facts → write liner note)

        guard args.count >= 3 else {
            print("""
            Usage: FMPromptRunner <prompts.jsonl> <instructions.json> <output.jsonl> [-limit N]

            Reads prompts JSONL, generates commentary via Apple Intelligence, writes output JSONL.
            Always runs dual-stage pipeline: extract facts → write liner note.
            """)
            exit(1)
        }
        Task {
            await run(args, limit: limit)
            exit(0)
        }
    }
}
