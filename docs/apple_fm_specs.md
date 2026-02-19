# Apple Intelligence Foundation Models — Technical Specification

> Based on the [Apple Intelligence Foundation Language Models Tech Report 2025](https://arxiv.org/abs/2507.13575), WWDC25 sessions, and Apple developer documentation. Last updated: February 2026.

---

## Table of Contents

1. [Model Architecture](#1-model-architecture)
2. [Quantization & Optimization](#2-quantization--optimization)
3. [Tokenizer](#3-tokenizer)
4. [Training](#4-training)
5. [Multimodal Vision-Language](#5-multimodal-vision-language)
6. [Benchmarks](#6-benchmarks)
7. [FoundationModels Framework API](#7-foundationmodels-framework-api)
8. [Structured Output — @Generable & @Guide](#8-structured-output--generable--guide)
9. [Tool Calling](#9-tool-calling)
10. [Streaming](#10-streaming)
11. [Session Management & Multi-Turn](#11-session-management--multi-turn)
12. [Generation Options](#12-generation-options)
13. [Safety & Guardrails](#13-safety--guardrails)
14. [Platform Availability & Hardware](#14-platform-availability--hardware)
15. [Adapter Training (LoRA)](#15-adapter-training-lora)
16. [Known Limitations](#16-known-limitations)
17. [References](#17-references)

---

## 1. Model Architecture

### 1.1 On-Device Model (~3B Parameters)

The on-device model is a dense transformer optimized for Apple silicon with two key architectural innovations:

| Property | Value |
|----------|-------|
| Parameters | ~3 billion |
| Architecture | Two-block transformer with KV-cache sharing |
| Block split | 5:3 depth ratio (Block 1: 62.5%, Block 2: 37.5%) |
| KV-cache sharing | Block 2 has KV projections removed; reuses Block 1 caches |
| KV-cache memory reduction | 37.5% vs standard architecture |
| Native context window | 16,384 tokens |
| **API context window** | **4,096 tokens** (hard limit enforced by FoundationModels framework) |
| Vocabulary size | 153,600 tokens |
| Quantization | 2-bit quantization-aware training |
| Time-to-first-token improvement | ~37.5% via block bypass |

**KV-Cache Sharing Mechanism:** The model is divided into two sequential blocks. Block 2 does not compute its own key-value projections — instead it reads the KV cache produced by Block 1. This eliminates 37.5% of KV cache storage and significantly reduces time-to-first-token latency.

### 1.2 Server Model (PT-MoE)

The server model uses a novel Parallel-Track Mixture-of-Experts architecture:

| Property | Value |
|----------|-------|
| Architecture | Parallel-Track Mixture-of-Experts (PT-MoE) |
| Expert count | 64 experts |
| MoE interleaving | Every 2 layers |
| Attention pattern | Alternating local (4096-token window) and global attention |
| Training context | 8,192 tokens |
| Extended context | **65,536 tokens** (via context lengthening stage) |
| Vocabulary size | 150,000 tokens |
| Quantization | 3.56 bits-per-weight (ASTC compression) |
| Synchronization overhead reduction | 87.5% (from 2L to L/D with D=4) |

**PT-MoE Architecture:** Multiple independent transformer tracks process tokens in parallel, combining track parallelism with sparse MoE computation. This reduces synchronization overhead from O(2L) with tensor parallelism to O(L/D) with track parallelism.

---

## 2. Quantization & Optimization

### 2.1 On-Device Quantization

| Component | Bits per Weight | Method |
|-----------|----------------|--------|
| Model weights | 2 bits | Quantization-Aware Training (QAT) |
| KV cache | 8 bits | Post-training quantization |
| Embedding table | 4 bits | Post-training quantization |

**2-Bit QAT Details:**
- Balanced quantization set: **{-1.5, -0.5, 0.5, 1.5}**
- Learnable scaling factors (weight clipping)
- Trained end-to-end — the model learns to compensate for quantization loss during training
- Quality cost: MMLU drops from 67.8 (16-bit) to 64.4 (2-bit), a ~3.4 point reduction

### 2.2 Server Quantization

| Component | Bits per Weight | Method |
|-----------|----------------|--------|
| Model weights | 3.56 bits | Adaptive Scalable Texture Compression (ASTC) |
| Embedding table | 4 bits | Post-training quantization |
| Quality recovery | — | Rank-32 LoRA adapters |

**ASTC Compression:** Operates on 6x6 blocks (36 weights per block) compressed into 128-bit ASTC values. Quality loss is recovered via LoRA adapter fine-tuning post-compression.

- Quality cost: MMLU drops from 80.0 (16-bit) to 79.2 (3.6-bit), a ~0.8 point reduction

---

## 3. Tokenizer

| Property | Value |
|----------|-------|
| Original vocabulary | 100,000 tokens |
| Expanded vocabulary | **153,600 tokens** |
| Expansion reason | Multilingual support (15-16 languages) |
| Type | Not publicly specified (likely BPE-based) |

The vocabulary expansion from 100k to 153,600 tokens was specifically designed for multilingual coverage, improving tokenization efficiency for non-English languages.

---

## 4. Training

### 4.1 Data

| Dataset | Scale |
|---------|-------|
| On-device dense baseline | 14T tokens |
| Server model | 13.4T tokens |
| Image-text pairs (web) | >10 billion |
| Synthetic caption pairs | >5 billion |
| On-device MoE upcycling | 1T additional tokens |

**Data Sources:** Responsible web crawling, licensed corpora, and high-quality synthetic data.

### 4.2 Training Pipeline

1. **Pre-training** — Large-scale multilingual/multimodal pre-training
2. **Continued pre-training** — Text-only domain adaptation
3. **Multimodal adaptation** — Vision-language joint training
4. **Supervised fine-tuning (SFT)** — Task-specific instruction tuning
5. **RLHF** — Reinforcement learning from human feedback

### 4.3 RLHF Infrastructure

| Property | Value |
|----------|-------|
| Algorithm | REINFORCE Leave-One-Out (RLOO) |
| Architecture | Distributed asynchronous (trajectory generators + policy updater) |
| Efficiency | 37.5% fewer devices, 75% less compute vs synchronous training |
| Reward signals | Reward models, ground truth verification, code execution, LLM-as-judge |

### 4.4 Server Training Infrastructure

| Property | Value |
|----------|-------|
| Hardware | 8,192 v5p Cloud TPU accelerators |
| Configuration | 4 x 2,048 chip slices |
| Framework | AXLearn |
| Fault tolerance | 93% good output (resilient to hardware failures) |

---

## 5. Multimodal Vision-Language

### 5.1 Vision Encoders

| | On-Device | Server |
|---|-----------|--------|
| Architecture | ViTDet-L | ViT-g |
| Parameters | 300M | 1B |
| Training resolution | 672 x 672 px | 448 x 448 px |
| SFT resolution | 1344 x 1344 px (2x2 tiling) | — |
| Output tokens | 144 | 144 |

### 5.2 Vision-Language Adapter

Pipeline: Vision encoder → Transformer layer → Linear projection → 3x3 convolution → Average pooling → Token embeddings injected into LLM.

### 5.3 Register-Window Mechanism

A novel mechanism in ViTDet that captures both local detail and global context simultaneously, improving fine-grained image understanding.

### 5.4 On-Device Vision Processing Modes

| Mode | Resolution | Tokens | Use Case |
|------|-----------|--------|----------|
| High-resolution | 1344 x 1344 | 144 | Detailed analysis |
| Balanced | 672 x 672 | 144 | Default |
| Rapid | 224 x 224 | 9 | Quick classification |

---

## 6. Benchmarks

### 6.1 Text Benchmarks

| Model | MMLU | MMMLU | MGSM |
|-------|------|-------|------|
| **AFM On-Device (3B, 2-bit)** | **64.4** | — | — |
| AFM On-Device (3B, 16-bit) | 67.85 | 60.60 | 74.91 |
| Qwen-2.5-3B | 66.37 | 56.53 | 64.80 |
| **AFM Server (3.6-bit)** | **79.2** | — | — |
| AFM Server (16-bit) | 80.20 | 74.60 | 87.09 |

### 6.2 Post-RLHF Improvements

- **Arena Hard:** +4%
- **AlpacaEval win rate vs GPT-4 Turbo:** +7%
- **Multilingual RLHF:** 16:9 win/loss rate in human evaluations
- **Overall satisfaction:** +1.3–2.0% across locales

### 6.3 Comparative Positioning

- On-device model **matches or surpasses Qwen-2.5-3B** across all evaluated languages
- Server model **competitive with Llama-4-Scout** but below GPT-4o
- Both models **match or surpass comparably sized open baselines** on public benchmarks and human evaluations

---

## 7. FoundationModels Framework API

### 7.1 Overview

The `FoundationModels` framework is a Swift-centric API exposing the on-device Apple Intelligence model to third-party developers. Key properties:

- **On-device only** — all inference runs locally, data never leaves the device
- **Offline capable** — no network required
- **Zero app size impact** — model is part of the OS
- **Async/await native** — full Swift concurrency integration

### 7.2 Core Types

#### SystemLanguageModel

```swift
// Access the default model
let model = SystemLanguageModel.default

// Check availability
switch SystemLanguageModel.default.availability {
case .available:
    // Ready
case .unavailable(let reason):
    // .deviceNotSupported, .appleIntelligenceNotEnabled, .regionNotSupported
}

// Specialized use cases
let model = SystemLanguageModel(useCase: .contentTagging)
```

#### LanguageModelSession

The primary interface. Stateful — maintains a transcript of all interactions.

```swift
// Minimal
let session = LanguageModelSession()

// Full configuration
let session = LanguageModelSession(
    model: SystemLanguageModel(useCase: .contentTagging),
    tools: [MyTool()],
    instructions: "You are a helpful assistant."
)

// From existing transcript (for context recovery)
let session = LanguageModelSession(transcript: previousTranscript)
```

**Core Methods:**

| Method | Return Type | Description |
|--------|------------|-------------|
| `respond(to:)` | `String` response | Plain text generation |
| `respond(to:generating:)` | Typed response | Structured output via @Generable |
| `respond(generating:)` | Typed response | Structured output without user prompt |
| `streamResponse(to:generating:)` | `AsyncSequence` | Streaming structured output |
| `transcript` | `Transcript` | Full conversation history |

### 7.3 Instructions vs Prompts

| | Instructions | Prompts |
|---|-------------|---------|
| Source | Developer | User/app |
| Scope | Session-wide | Per-request |
| Priority | **Higher** (resists prompt injection) | Lower |
| Purpose | Role, style, constraints | Task-specific input |

```swift
let session = LanguageModelSession(
    instructions: "You are a music critic. Keep responses under 3 sentences."
)
let response = try await session.respond(to: "React to 'Bohemian Rhapsody' by Queen")
```

### 7.4 Error Handling

```swift
do {
    let response = try await session.respond(to: prompt)
} catch LanguageModelSession.GenerationError.exceededContextWindowSize {
    // Context limit hit — create new session with condensed history
} catch LanguageModelSession.GenerationError.unsupportedLanguageOrLocale {
    // Language not supported
} catch {
    // Guardrail violation or other error
}
```

### 7.5 Language Support

```swift
let supportedLanguages = SystemLanguageModel.default.supportedLanguages
guard supportedLanguages.contains(Locale.current.language) else {
    // Show fallback or disclaimer
    return
}
```

Supports 15-16 languages with locale-specific safety evaluation.

---

## 8. Structured Output — @Generable & @Guide

### 8.1 @Generable Macro

Marks a type for constrained model generation. The model is **guaranteed** to produce a valid instance — no parsing failures, no hallucinated fields.

**Mechanism:** At compile time, `@Generable` generates a schema. At inference time, the model's vocabulary is masked token-by-token so only valid tokens per the schema are produced (constrained decoding).

```swift
@Generable
struct MusicInsights {
    var trackFact: String
    var artistFact: String
    var albumFact: String
}

let response = try await session.respond(
    to: "Tell me about 'Kind of Blue' by Miles Davis",
    generating: MusicInsights.self
)
// response.content is a fully populated MusicInsights instance
```

**Supported Types:**

| Type | Example |
|------|---------|
| `String` | Names, descriptions, free text |
| `Int`, `Double`, `Float`, `Decimal` | Counts, scores, ratings |
| `Bool` | Flags, binary decisions |
| `Array<T>` where T: Generable | Lists of structured items |
| Nested `@Generable` structs | Composition |
| `@Generable` enums | Categorical choices |
| Recursive types | Self-referential structures |
| `Optional<T>` | Optional fields |

**Enum Generation:**

```swift
@Generable
enum Mood {
    case energetic
    case melancholic
    case contemplative
    case joyful
}

@Generable
struct TrackAnalysis {
    var mood: Mood
    var summary: String
}
```

**Enums with Associated Values:**

```swift
@Generable
enum Recommendation {
    case listenNext(trackName: String)
    case skipAhead(reason: String)
    case repeatTrack
}
```

### 8.2 @Guide Macro

Provides constraints and natural language descriptions to guide generation quality.

| Constraint | Syntax | Applies To |
|-----------|--------|------------|
| Description | `@Guide(description: "...")` | All types |
| Exact count | `@Guide(.count(N))` | Arrays |
| Maximum count | `@Guide(.maximumCount(N))` | Arrays |
| Value range | `@Guide(.range(1...10))` | Numeric types |
| Allowed values | `@Guide(.anyOf(["a", "b"]))` | Strings |
| Regex pattern | `@Guide(Regex { ... })` | Strings |

```swift
@Generable
struct MusicReview {
    @Guide(description: "A 1-2 sentence reaction to the track")
    var commentary: String

    @Guide(description: "Rating from 1-10", .range(1...10))
    var rating: Int

    @Guide(description: "Up to 3 genre tags", .maximumCount(3))
    var tags: [String]

    @Guide(.anyOf(["skip", "keep", "favorite"]))
    var verdict: String
}
```

**Regex Constraint Example:**

```swift
@Guide(Regex {
    Capture {
        ChoiceOf {
            "Track"
            "Album"
            "Artist"
        }
    }
    ": "
    OneOrMore(.any)
})
var factLabel: String
// Produces: "Track: Recorded in a single session" etc.
```

### 8.3 PartiallyGenerated Type

`@Generable` automatically synthesizes a `PartiallyGenerated<T>` companion type where all properties are optional. This is used for streaming — properties populate incrementally as the model generates.

```swift
@Generable
struct Review {
    var title: String
    var body: String
}

// During streaming:
// partial.title = "Kind of Blue"  (available)
// partial.body = nil              (not yet generated)
```

### 8.4 Property Declaration Order

Properties are generated in **declaration order**. Earlier properties influence later ones. Place foundational properties first:

```swift
@Generable
struct Commentary {
    var mood: Mood           // Generated first — sets tone
    var factoid: String      // Generated second — influenced by mood
    var commentary: String   // Generated last — synthesizes both
}
```

### 8.5 Dynamic Schemas (Runtime)

For cases where the schema isn't known at compile time:

```swift
var builder = LevelObjectCreator(name: "Insight")
builder.addStringProperty(name: "fact")
builder.addStringProperty(name: "source")
builder.addBoolProperty(name: "verified")

let schema = try GenerationSchema(root: builder.root, dependencies: [])
let response = try await session.respond(to: prompt, schema: schema)
let fact = try response.content.value(String.self, forProperty: "fact")
```

---

## 9. Tool Calling

### 9.1 Tool Protocol

```swift
struct MyTool: Tool {
    let name = "toolName"               // Short, readable English
    let description = "One sentence."   // ~1 sentence, concise

    @Generable
    struct Arguments {
        @Guide(description: "What this argument is for")
        var paramName: String
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        // Execute logic
        return ToolOutput("result string")
        // or structured:
        // return ToolOutput(GeneratedContent(properties: ["key": value]))
    }
}
```

### 9.2 Tool Registration

```swift
let session = LanguageModelSession(
    tools: [ToolA(), ToolB(), ToolC()],
    instructions: "Use tools when needed."
)
```

### 9.3 Execution Flow

1. Model receives transcript + tool schemas + instructions
2. Model decides which tool(s) to call (constrained decoding guarantees valid arguments)
3. Framework automatically invokes `call(arguments:)` on the tool instance
4. Tool output is inserted into the transcript
5. Model generates final response incorporating tool outputs
6. **Multiple tools can be called in parallel** within a single request

### 9.4 Stateful Tools

Use `class` instead of `struct` for tools that track state across calls:

```swift
class PlayHistoryTool: Tool {
    let name = "getPlayHistory"
    let description = "Returns recent play history."

    private var queriedTracks = Set<String>()

    func call(arguments: Arguments) async throws -> ToolOutput {
        // Track what's been queried, avoid duplicates, etc.
        queriedTracks.insert(arguments.trackId)
        return ToolOutput(...)
    }
}
```

### 9.5 Token Budget Consideration

Tool names, descriptions, and argument schemas are serialized verbatim into the prompt. Every token adds latency:

- Keep tool names short but readable
- Keep descriptions to ~1 sentence
- Minimize argument count and description length
- Profile with Instruments to measure impact

---

## 10. Streaming

### 10.1 API

```swift
let stream = session.streamResponse(
    to: "React to this track",
    generating: Commentary.self
)

for try await partial in stream {
    // partial is PartiallyGenerated<Commentary>
    // Properties fill in declaration order
    if let mood = partial.mood {
        updateMoodUI(mood)
    }
    if let text = partial.commentary {
        updateTextUI(text)
    }
}
```

### 10.2 SwiftUI Integration

```swift
struct CommentaryView: View {
    @State private var partial: Commentary.PartiallyGenerated?

    var body: some View {
        VStack {
            if let mood = partial?.mood {
                MoodBadge(mood)
                    .transition(.scale)
            }
            if let text = partial?.commentary {
                Text(text)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: partial?.mood)
    }

    func generate() {
        Task {
            let stream = session.streamResponse(to: prompt, generating: Commentary.self)
            for try await p in stream {
                self.partial = p
            }
        }
    }
}
```

### 10.3 Best Practices

- Use SwiftUI animations/transitions to mask latency
- Consider stable identity for array elements during streaming
- Property declaration order = streaming order — put "header" fields first

---

## 11. Session Management & Multi-Turn

### 11.1 Transcript Persistence

```swift
let session = LanguageModelSession(instructions: "You are a music critic.")

// Turn 1
let r1 = try await session.respond(to: "What do you think of jazz fusion?")

// Turn 2 — model remembers Turn 1
let r2 = try await session.respond(to: "Give me an album recommendation based on that.")

// Full history
print(session.transcript) // Contains all turns
```

### 11.2 Context Window Recovery

When the context fills up, create a new session with condensed history:

```swift
func recoverSession(from previous: LanguageModelSession) -> LanguageModelSession {
    let entries = previous.transcript.entries
    var condensed = [Transcript.Entry]()

    // Keep first entry (instructions/setup)
    if let first = entries.first {
        condensed.append(first)
    }
    // Keep last exchange (most recent context)
    if entries.count > 1, let last = entries.last {
        condensed.append(last)
    }

    return LanguageModelSession(transcript: Transcript(entries: condensed))
}
```

---

## 12. Generation Options

### 12.1 Sampling Configuration

```swift
// Deterministic — same input → same output
let response = try await session.respond(
    to: prompt,
    options: GenerationOptions(sampling: .greedy)
)

// Low variance — more consistent
let response = try await session.respond(
    to: prompt,
    options: GenerationOptions(temperature: 0.5)
)

// High variance — more creative
let response = try await session.respond(
    to: prompt,
    options: GenerationOptions(temperature: 2.0)
)
```

| Strategy | Behavior |
|----------|----------|
| Default | Random sampling within probability range |
| Greedy | Deterministic (highest probability token always) |
| Low temperature (0.1–0.5) | Focused, consistent output |
| High temperature (1.5–2.0) | Diverse, creative, less predictable |

**Note:** Even with greedy sampling, OS updates that change the model can alter output for identical inputs.

---

## 13. Safety & Guardrails

### 13.1 Safety Taxonomy

- **6 top-level categories** with **58 subcategories**
- Content filtering applied at both input and output
- Locale-specific evaluation for cultural sensitivity
- Human evaluation consensus shows 20-30% disagreement rate on subjective safety tasks

### 13.2 Instruction Priority

The model prioritizes **instructions** (developer-set) over **prompts** (user-set). This provides a layer of defense against prompt injection — the model is trained to follow developer instructions even when user prompts attempt to override them.

### 13.3 Error Behavior

When a guardrail triggers, the framework throws an error rather than returning filtered/modified content. The app must handle this gracefully:

```swift
do {
    let response = try await session.respond(to: userInput)
} catch {
    // Guardrail triggered — show graceful fallback
    showFallbackUI()
}
```

### 13.4 Privacy Model

- All on-device inference — data never leaves the device
- Safe to process contacts, calendar, health data, etc.
- Standard system permission flows still required (CNContactStore, EventKit, etc.)
- Private Cloud Compute for server-side inference (Apple-managed, stateless, verifiable)

---

## 14. Platform Availability & Hardware

### 14.1 Supported Platforms

| Platform | Minimum Version |
|----------|----------------|
| macOS | 26 |
| iOS | 26 |
| iPadOS | 26 |
| visionOS | 26 (assumed) |

### 14.2 Requirements

- Apple Intelligence must be **enabled** by the user
- Device must be Apple Intelligence-compatible (Apple silicon)
- Region must support Apple Intelligence
- Model is **built into the OS** — no download required, no app size impact

### 14.3 Availability Checking

```swift
switch SystemLanguageModel.default.availability {
case .available:
    // Proceed
case .unavailable(.deviceNotSupported):
    // Hardware too old
case .unavailable(.appleIntelligenceNotEnabled):
    // User hasn't enabled Apple Intelligence
case .unavailable(.regionNotSupported):
    // Region restriction
}
```

---

## 15. Adapter Training (LoRA)

### 15.1 Overview

Apple provides an **Adapter Training Toolkit** for ML practitioners to fine-tune the foundation model with custom datasets using LoRA (Low-Rank Adaptation).

| Property | Value |
|----------|-------|
| Adapter type | LoRA |
| Rank | 32 |
| Use case | Task-specific specialization |
| Distribution | Bundled with app or downloaded |

### 15.2 Capabilities

- Train custom adapters on proprietary datasets
- Rank-32 adapters are ~160 MB each; distributed via Background Assets framework, not bundled in app binary
- Multiple adapters can be swapped at runtime for different tasks
- Quality recovery after quantization (used by Apple internally for server model)

---

## 16. Known Limitations

### 16.1 Model Capabilities

| Strength | Limitation |
|----------|-----------|
| Summarization | Not designed for world knowledge |
| Entity extraction | Not designed for advanced reasoning |
| Text understanding | Limited by 3B parameter count |
| Short dialog | No internet access / retrieval |
| Creative content | Cannot process audio or video |
| Classification | Multilingual quality varies by language |

### 16.2 Framework Constraints

- **On-device only** — cannot call the server model via FoundationModels framework
- **No fine-grained token counting** — no public API to count tokens before submission
- **Context window is hard** — exceeding 4,096 tokens throws `exceededContextWindowSize`, no automatic truncation
- **Model updates are opaque** — Apple may update the model via OS updates; output can change
- **No response metadata** — no token usage, finish reason, or logprobs exposed
- **Limited model selection** — only `.default` and use-case variants, no model size choice

### 16.3 Token Budget Guidelines

For the 4,096-token API context window, approximate budget allocation:

| Component | Approximate Tokens |
|-----------|--------------------|
| Instructions (system prompt) | 200–400 |
| Tool schemas (if used) | 100–300 per tool |
| @Generable schema overhead | 100–200 |
| User prompt + context | Variable |
| Output generation | 400–800 |
| Safety margin | ~200 |
| **Available for content** | **~2,000–2,900** |

---

## 17. References

1. [Apple Intelligence Foundation Language Models Tech Report 2025](https://arxiv.org/abs/2507.13575) — Full technical paper with architecture, training, and evaluation details.
2. [Updates to Apple's On-Device and Server Foundation Language Models](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates) — Summary of 2025 model updates.
3. [Meet the Foundation Models Framework (WWDC25 #286)](https://developer.apple.com/videos/play/wwdc2025/286/) — Introduction to the framework API.
4. [Deep Dive into the Foundation Models Framework (WWDC25 #301)](https://developer.apple.com/videos/play/wwdc2025/301/) — Advanced features: guided generation, tools, dynamic schemas.
5. [FoundationModels Documentation](https://developer.apple.com/documentation/FoundationModels) — Apple developer API reference.
6. [Apple Newsroom — Foundation Models Framework](https://www.apple.com/newsroom/2025/09/apples-foundation-models-framework-unlocks-new-intelligent-app-experiences/) — Press release with developer ecosystem context.
