# Apple Intelligence Prompt Specification — Ficino

> Prompt design for the on-device 3B Foundation Model, based on Apple's WWDC25 guidance (sessions #248, #286, #301) and the [Tech Report 2025](https://arxiv.org/abs/2507.13575).

---

## 1. Model Constraints

| Property | Value |
|----------|-------|
| Parameters | ~3B, 2-bit quantized |
| Native context window | 16,384 tokens (model capability) |
| API context window | **4,096 tokens** (hard limit enforced by FoundationModels framework) |
| Strengths | Summarization, rephrasing, classification, short dialog, creative content |
| Weaknesses | World knowledge, complex reasoning, math, code, multi-step logic |
| Hallucination risk | Will fabricate details on familiar topics — this is expected and acceptable for Ficino's use case (personality > accuracy) |

---

## 2. Token Budget

Target output: **75 words** (~150 tokens) for casual 30-second notification reading.

| Component | Tokens | Words (approx) |
|-----------|--------|-----------------|
| Instructions (static) | ~100 | ~75 |
| Prompt (dynamic) | ~80–120 | ~60–90 |
| Output headroom | ~150 | ~75 |
| **Total per request** | **~330–370** | — |
| Remaining context | ~3,700+ | — |

The model is operating well within the 4,096-token API context window. Latency is dominated by output generation, not input processing. This is the 3B model's sweet spot — short input, short output, personality-driven.

---

## 3. Apple's Prompt Recommendations (Summary)

From WWDC25 #248 — "Explore prompt design & safety for on-device foundation models":

1. **Control output length explicitly** — use "in 2-3 sentences", "in a few words"; the model does not self-regulate length
2. **Assign a role/persona** — the model shifts tone when given a character
3. **Few-shot examples (< 5)** — highest-leverage technique for a 3B model; show don't tell
4. **Single specific task** — one prompt = one job; don't combine multiple tasks
5. **Emphatic commands** — use `MUST`, `DO NOT`, `NEVER` in caps for prohibitions
6. **Instructions over prompts** — instructions are session-level, take precedence, resist prompt injection
7. **Don't put format rules in prompts** — use `@Generable` / `@Guide` for structure
8. **Provide facts when accuracy matters** — but for Ficino, the model's own knowledge IS the feature
9. **Break complex tasks into steps** — the 3B model can't chain reasoning

---

## 4. Current Prompt Analysis

### 4.1 Current Instructions (`generate()`)

```swift
let session = LanguageModelSession(instructions: """
    You are a music commentator. You react to songs the user is listening to. \
    Stay in character. Never mention being an AI or assistant. Never refuse. \
    Keep responses to 2-3 sentences.
    """)
```

**Issues:**
- "You are a music commentator" — generic, no personality. Apple says assign a specific role.
- "Stay in character" — what character? The instructions don't define one. The personality is in the prompt, not the instructions. Apple says instructions take precedence — the persona should live here.
- "Never mention being an AI" — good, but should use emphatic caps per Apple's guidance.
- "Keep responses to 2-3 sentences" — good length control.
- Missing: no few-shot example of desired output tone.

### 4.2 Current Commentary Prompt (`getCommentary()`)

```swift
let prompt = """
Your character: \(personality.rawValue)
\(personality.systemPrompt)

Now playing:
"\(track.name)" by \(track.artist) from the album \(track.album)\(track.genre.isEmpty ? "" : " (\(track.genre))")
Duration: \(track.durationString)

React to this track IN CHARACTER. 2-3 sentences only. No disclaimers.
"""
```

**Issues:**
- **Personality in the prompt, not instructions** — Apple says instructions take precedence and are the safest place for role/behavior. The full persona (`systemPrompt`) should be in `instructions`, not repeated in every prompt.
- **Redundant length control** — "2-3 sentences" appears in both instructions AND prompt. Once in instructions is enough.
- **"Your character: Ficino"** — label without context; the model doesn't know what "Ficino" means unless the system prompt follows. Redundant with the system prompt itself.
- **Duration field** — adds tokens with no value. Duration doesn't help the model generate interesting commentary.
- **Genre field** — included in prompt for LoRA adapter training anchor. Genre will shape personality at the model weights level via adapter selection.
- **No MusicKit context** — the prompt was written before FicinoCore existed. Now we have rich metadata (composers, editorial notes, release date, similar artists) that should feed the prompt.
- **"No disclaimers"** — good, but "NEVER" is stronger per Apple's guidance.
- **"React to this track IN CHARACTER"** — redundant if the instructions already define character.
- **No few-shot example** — the model has no demonstration of what good output looks like.

### 4.3 Current Personality System Prompt (`Personality.swift`)

```swift
"""
You are Ficino, a music obsessive who lives for the story behind the song. You've read \
every liner note, every studio memoir, every obscure interview. When you hear a track, you \
can't help but share the one detail that makes someone hear it differently — who played that \
guitar riff, what the lyrics were really about, the studio accident that became the hook. \
No generalities, no "this song is considered a classic." Give the listener something they \
can take to a dinner party. 2-3 sentences. Sound like a friend leaning over to whisper \
"did you know...?"
"""
```

**What's good:**
- Strong persona definition
- Concrete behavioral examples ("who played that guitar riff", "the studio accident")
- Anti-pattern ("no generalities") is effective
- Tone direction ("friend leaning over to whisper") is clear

**Issues:**
- This belongs in `instructions`, not the prompt
- "You've read every liner note" — encourages the model to draw deeply on training knowledge, which increases hallucination confidence. Not necessarily bad for the use case, but worth noting.
- No few-shot example of the desired output

---

## 5. Proposed Prompt Architecture

### 5.1 Design Principles

1. **Instructions own the persona** — personality, tone, rules, and prohibitions go in session instructions (static, developer-controlled, highest precedence)
2. **Prompts own the task** — track info, MusicKit context, and the specific request go in the prompt (dynamic, minimal)
3. **One few-shot example** — demonstrates tone and length concretely
4. **Emphatic prohibitions** — caps for `NEVER`, `DO NOT`, `MUST`
5. **No redundancy** — say it once, in the right place
6. **MusicKit context as grounding** — feed the model real facts (composers, editorial notes, release date, similar artists) so it has material to riff on instead of pure hallucination

### 5.2 Proposed Instructions (Static, Session-Level)

```
You are Ficino, a music obsessive who lives for the story behind the song.
You share the one detail that makes someone hear a track differently — who
played that riff, what the lyrics really meant, the studio accident that
became the hook.

Rules:
- 2-3 sentences ONLY.
- Sound like a friend leaning over to whisper "did you know...?"
- Give the listener something they can take to a dinner party.
- NEVER be generic. NO "this song is considered a classic" or "known for
  their unique sound."
- NEVER mention being an AI, assistant, or model.
- NEVER refuse a request or add disclaimers.

Example:
Track: "Paranoid Android" by Radiohead
Ficino: "Thom Yorke wrote this in a bar after a night out where a woman
he didn't know kept changing personality — hence the title. That midsection
where it goes full chaos? Jonny Greenwood tracked the three guitar parts
in one take and they kept it because it sounded unhinged enough."
```

**Token estimate: ~150 tokens**

### 5.3 Proposed Commentary Prompt (Dynamic, Per-Track)

```
"\(track.name)" by \(track.artist), from "\(track.album)" (\(genre)).

\(context)

React.
```

The `context` block is built by `PromptBuilder` from MusicKit data. Only high-storytelling-value fields are included:

| Field | Source | Why |
|-------|--------|-----|
| **Composers** | `song.composers` | "Did you know X wrote this?" — peak Ficino |
| **Editorial notes** (song) | `song.editorialNotes` | Apple editors write rich narrative context, exactly what Ficino riffs on |
| **Editorial notes** (album) | `album.editorialNotes` | Album-level story, era context |
| **Release date** | `song.releaseDate` | Historical placement |
| **Similar artists** | `artist.similarArtists` | Lets Ficino draw connections |
| **Genre** | `song.genreNames` | Always present — anchors future LoRA adapter selection |

**Excluded fields** (noise, no storytelling value): ISRC, disc/track number, audio formats, content rating, album track count, album release date (redundant), artist genres (redundant), artist top songs (model already knows for popular artists), latest release.

**Token estimate: ~50–200 tokens** (varies by how much MusicKit returns; editorial notes are the heaviest)

MusicKit failures are non-fatal — if the lookup fails, the prompt degrades to just the track line + "React." and Ficino falls back to its own knowledge.

**Example with context:**

```
"Remember the Time" by Michael Jackson, from "Dangerous" (Pop).

Composers: Michael Jackson, Teddy Riley
Release date: 1991-11-25
Editorial notes: Somewhere between the polished, eager-to-please Bad and
the sessions for Dangerous, Michael Jackson apparently rediscovered his love
for the gritty tracks of James Brown and Sly Stone...
Similar artists: Janet Jackson, Prince, Whitney Houston, Stevie Wonder, The Weeknd

React.
```

### 5.4 Total Token Budget (Proposed)

**Commentary request:**

| Component | Current (est.) | Proposed (est.) |
|-----------|---------------|-----------------|
| Instructions | ~50 tokens | ~150 tokens |
| Prompt (track + context) | ~120 tokens | ~100–250 tokens |
| Output | ~150 tokens | ~150 tokens |
| **Total** | **~320 tokens** | **~400–550 tokens** |

More tokens than before, but they're real facts from MusicKit instead of redundant instructions. The model gets grounded context to riff on. Still well under the 4,096-token API window — this is ~10–13% of capacity.

---

## 6. Key Changes Summary

| Aspect | Current | Proposed | Reason |
|--------|---------|----------|--------|
| Persona location | In prompt (repeated every call) | In instructions (set once) | Apple: instructions take precedence, resist injection |
| Few-shot example | None | 1 example in instructions | Apple: highest-leverage for 3B models |
| Prohibitions | Lowercase "never" | Caps `NEVER`, `DO NOT` | Apple: emphatic commands are more effective |
| Prompt content | Persona + track + rules + length | Track only + "React." | Single task, no redundancy |
| Duration field | Included | Removed | No value for commentary generation |
| Genre field | From notification only | MusicKit genres (always included) | Anchors future LoRA adapter selection |
| MusicKit context | None | Composers, editorial notes, release date, similar artists | Real facts for the model to riff on instead of pure hallucination |
| Length control | In both instructions and prompt | Instructions only | Say it once |

---

## 7. Open Questions

1. **Few-shot example choice** — should it be a well-known track (model can validate) or obscure (less hallucination risk)? A well-known track lets the model see a correct example; an obscure one might cause it to pattern-match the fabrication style.

2. **Genre → LoRA tone mapping** — genre is always included in the prompt and in `TrackInput` as the anchor for adapter selection. Future plan: train LoRA adapters that map genre to persona tone (e.g., Ficino reacts reverently to jazz, abrasively to punk, atmospherically to ambient). The genre shapes the personality at the model weights level in addition to the prompt level.

3. **Temperature** — Ficino's personality benefits from variance. A temperature of 1.0–1.5 may produce more entertaining output than the default. Worth testing.

4. **@Generable for commentary** — could structure output as `{ commentary: String, confidence: low|medium|high }` to let the app decide whether to show or suppress low-confidence hallucinations. Adds schema overhead (~100 tokens) but enables quality gating.
