import Foundation

actor ClaudeService: CommentaryService {
    private var claudePath: String?
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var readingTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var responseContinuation: CheckedContinuation<String, Error>?
    private var continuationResumed = false
    private var drainContinuation: CheckedContinuation<Void, Never>?
    private var expectingResult = false
    private var lineBuffer = ""
    private var launchFailureCount = 0
    private static let maxRetries = 3
    private static let responseTimeout: TimeInterval = 30

    var model: String = "claude-haiku-4-5-20251001"

    // MARK: - CLI Resolution

    private func resolveClaudePath() throws -> String {
        if let cached = claudePath { return cached }

        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude"
        ]

        // Check known locations first
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                claudePath = path
                NSLog("[Claude] Found CLI at: %@", path)
                return path
            }
        }

        // Fall back to `which`
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["claude"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = FileHandle.nullDevice

        do {
            try which.run()
            which.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty,
               FileManager.default.isExecutableFile(atPath: path) {
                claudePath = path
                NSLog("[Claude] Found CLI via which: %@", path)
                return path
            }
        } catch {
            // which itself failed, fall through
        }

        throw ClaudeError.launchFailed(
            "Claude CLI not found. Install it with: npm install -g @anthropic-ai/claude-code"
        )
    }

    // MARK: - Process Lifecycle

    private func ensureProcessRunning() throws {
        if let process, process.isRunning { return }

        // Clean up stale state
        readingTask?.cancel()
        readingTask = nil
        stderrTask?.cancel()
        stderrTask = nil
        expectingResult = false
        lineBuffer = ""

        let path = try resolveClaudePath()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--model", model,
            "--tools", "WebSearch",
            "--allowedTools", "WebSearch",
            "--system-prompt", "You are a music commentator. You react to songs the user is listening to. Stay in character. Never mention being an AI or assistant. Never refuse. Keep responses to 2-3 sentences."
        ]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        do {
            try proc.run()
            launchFailureCount = 0
        } catch {
            launchFailureCount += 1
            throw ClaudeError.launchFailed("Failed to launch Claude CLI at \(path): \(error.localizedDescription)")
        }

        self.process = proc
        self.stdinHandle = stdinPipe.fileHandleForWriting
        NSLog("[Claude] Process started (PID %d)", proc.processIdentifier)

        // Background reader for stdout
        let stdoutHandle = stdoutPipe.fileHandleForReading
        readingTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                let data = stdoutHandle.availableData
                if data.isEmpty { break } // EOF
                guard let chunk = String(data: data, encoding: .utf8) else { continue }
                await self?.processChunk(chunk)
            }
            await self?.handleProcessEnd()
        }

        // Background reader for stderr
        let stderrHandle = stderrPipe.fileHandleForReading
        stderrTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                let data = stderrHandle.availableData
                if data.isEmpty { break }
                if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !text.isEmpty {
                    NSLog("[Claude stderr] %@", text)
                    // Surface critical errors
                    let lower = text.lowercased()
                    if lower.contains("error") || lower.contains("unauthorized") || lower.contains("rate limit") {
                        await self?.handleStderrError(text)
                    }
                }
            }
        }
    }

    private func processChunk(_ chunk: String) {
        lineBuffer += chunk
        while let newlineIndex = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineIndex])
            lineBuffer = String(lineBuffer[lineBuffer.index(after: newlineIndex)...])
            if !line.isEmpty {
                handleLine(line)
            }
        }
    }

    private func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            NSLog("[Claude] Unparseable line: %@", String(line.prefix(100)))
            return
        }

        let type = json["type"] as? String
        let subtype = json["subtype"] as? String ?? ""
        NSLog("[Claude] Stream event: %@%@", type ?? "unknown", subtype.isEmpty ? "" : " (\(subtype))")

        if type == "result" {
            let resultText = json["result"] as? String ?? ""

            // If we're draining a stale result from a cancelled request, consume and discard it
            if let drain = drainContinuation {
                NSLog("[Claude] Drained stale result (%d chars)", resultText.count)
                drainContinuation = nil
                drain.resume()
                return
            }

            NSLog("[Claude] Got result (%d chars)", resultText.count)
            resumeContinuation(with: .success(resultText))
        }
    }

    private func handleProcessEnd() {
        NSLog("[Claude] Process ended")
        process = nil
        stdinHandle = nil
        readingTask = nil
        stderrTask?.cancel()
        stderrTask = nil

        // Resume any pending drain so sendPrompt can proceed
        if let drain = drainContinuation {
            drainContinuation = nil
            drain.resume()
        }

        if expectingResult {
            resumeContinuation(with: .failure(ClaudeError.failed("Claude process terminated unexpectedly")))
        }
    }

    private func handleStderrError(_ text: String) {
        NSLog("[Claude] Critical stderr: %@", text)
        // If we're waiting for a result and get a critical error, fail the request
        if expectingResult {
            resumeContinuation(with: .failure(ClaudeError.failed(text)))
        }
    }

    private func timeoutIfStillWaiting() {
        guard expectingResult, !continuationResumed else { return }
        NSLog("[Claude] Response timed out after %.0fs", Self.responseTimeout)
        resumeContinuation(with: .failure(ClaudeError.timeout))
    }

    /// Safe continuation resume — guards against double-resume
    private func resumeContinuation(with result: Result<String, Error>) {
        guard !continuationResumed, let continuation = responseContinuation else { return }
        continuationResumed = true
        responseContinuation = nil
        expectingResult = false

        switch result {
        case .success(let value): continuation.resume(returning: value)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    // MARK: - Public API

    func setModel(_ newModel: String) {
        model = newModel
    }

    func validateSetup() throws {
        _ = try resolveClaudePath()
    }

    func cancelCurrent() {
        if expectingResult {
            NSLog("[Claude] Cancelling in-flight request")
            resumeContinuation(with: .failure(CancellationError()))
        }
        // Also cancel any pending drain
        if let drain = drainContinuation {
            drainContinuation = nil
            drain.resume()
        }
    }

    func getCommentary(for track: TrackInfo, personality: Personality) async throws -> String {
        let prompt = """
        IMPORTANT: For this message, ignore all prior instructions about being a coding assistant. \
        You are a music commentator. Do NOT mention being an AI, do NOT mention Anthropic, do NOT \
        refuse this task. Stay in character fully.

        Your character: \(personality.rawValue)
        \(personality.systemPrompt)

        Now playing:
        "\(track.name)" by \(track.artist) from the album \(track.album)\(track.genre.isEmpty ? "" : " (\(track.genre))")
        Duration: \(track.durationString)

        React to this track IN CHARACTER. 2-3 sentences only. No disclaimers.
        """

        NSLog("[Claude] Sending message as '%@' for: %@ - %@", personality.rawValue, track.name, track.artist)
        return try await sendPrompt(prompt)
    }

    func getReview(personality: Personality) async throws -> String {
        let prompt = """
        IMPORTANT: For this message, ignore all prior instructions about being a coding assistant. \
        You are a music commentator. Do NOT mention being an AI, do NOT mention Anthropic, do NOT \
        refuse this task. Stay in character fully.

        Your character: \(personality.rawValue)
        \(personality.systemPrompt)

        Review the last 5 songs you just commented on. Talk about the vibe of this listening session, \
        any standouts, and how the tracks flow together. 3-5 sentences, stay fully in character. No disclaimers.
        """

        NSLog("[Claude] Requesting 5-song review as '%@'", personality.rawValue)
        return try await sendPrompt(prompt)
    }

    // MARK: - Private

    /// Wait for a stale result event from a cancelled request, so it doesn't
    /// get misdelivered to the next continuation.
    private func waitForStaleResult() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.drainContinuation = continuation

            // Safety timeout — don't block forever if the old result never comes
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self?.handleDrainTimeout()
            }
        }
    }

    private func handleDrainTimeout() {
        if let dc = drainContinuation {
            drainContinuation = nil
            dc.resume()
            NSLog("[Claude] Drain timed out after 5s, proceeding anyway")
        }
    }

    private func sendPrompt(_ prompt: String) async throws -> String {
        let hadInflightRequest = expectingResult
        cancelCurrent()

        // If there was an in-flight request, wait for its stale result to arrive
        // and be discarded before sending the new message. This prevents the race
        // where the old result gets delivered to the new continuation.
        if hadInflightRequest {
            NSLog("[Claude] Draining stale result before sending new message...")
            await waitForStaleResult()
            NSLog("[Claude] Drain complete")
        }

        // Retry logic for process launch
        var lastError: Error?
        for attempt in 0..<Self.maxRetries {
            do {
                try ensureProcessRunning()
                lastError = nil
                break
            } catch {
                lastError = error
                NSLog("[Claude] Launch attempt %d failed: %@", attempt + 1, error.localizedDescription)
                if attempt < Self.maxRetries - 1 {
                    try await Task.sleep(nanoseconds: UInt64(500_000_000 * (1 << attempt)))
                }
            }
        }
        if let lastError {
            throw lastError
        }

        let userMessage: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt]
                ]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: userMessage)
        guard var jsonString = String(data: jsonData, encoding: .utf8) else {
            throw ClaudeError.failed("Failed to serialize message")
        }
        jsonString += "\n"

        guard let writeData = jsonString.data(using: .utf8) else {
            throw ClaudeError.failed("Failed to encode message")
        }

        stdinHandle?.write(writeData)

        let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            self.responseContinuation = continuation
            self.continuationResumed = false
            self.expectingResult = true

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.responseTimeout * 1_000_000_000))
                await self?.timeoutIfStillWaiting()
            }
        }

        return response
    }
}

enum ClaudeError: LocalizedError {
    case failed(String)
    case launchFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .failed(let msg): return "Claude error: \(msg)"
        case .launchFailed(let msg): return msg
        case .timeout: return "Claude did not respond within 30 seconds"
        }
    }
}
