import SwiftUI
import os

let logger = Logger(subsystem: "com.ficino.MusicContextGenerator", category: "CLI")

@main
struct MusicContextGeneratorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    init() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty {
            print(usageMessage)
            exit(0)
        }
        Task {
            await CLIRunner.run(args)
            exit(0)
        }
    }
}
