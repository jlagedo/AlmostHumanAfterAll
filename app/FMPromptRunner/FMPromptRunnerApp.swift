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
        // Skip CLI logic when launched by Xcode for #Playground execution
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == nil else {
            return
        }

        var args = Array(CommandLine.arguments.dropFirst())

        // Parse -l (limit) flag
        var limit: Int?
        if let idx = args.firstIndex(of: "-l"), idx + 1 < args.count {
            if let n = Int(args[idx + 1]), n > 0 {
                limit = n
            } else {
                print("Error: -l requires a positive integer")
                exit(1)
            }
            args.removeSubrange(idx...idx + 1)
        }

        // Parse -t (temperature) flag
        var temperature: Double = 0.5
        if let idx = args.firstIndex(of: "-t"), idx + 1 < args.count {
            if let t = Double(args[idx + 1]), t >= 0 {
                temperature = t
            } else {
                print("Error: -t requires a non-negative number")
                exit(1)
            }
            args.removeSubrange(idx...idx + 1)
        }

        guard args.count >= 3 else {
            print("""
            Usage: FMPromptRunner <prompts.jsonl> <instructions.json> <output.jsonl> [-l N] [-t TEMP]

            Reads prompts JSONL, generates commentary via Apple Intelligence, writes output JSONL.
            """)
            exit(1)
        }
        Task {
            await run(args, limit: limit, temperature: temperature)
            exit(0)
        }
    }
}
