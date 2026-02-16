# Apple Intelligence Prompt Specification — Ficino

> Prompt design for the on-device 3B Foundation Model, based on Apple's WWDC25 guidance (sessions #248, #286, #301) and the [Tech Report 2025](https://arxiv.org/abs/2507.13575).

---

## 1. Model Constraints

| Property | Value |
|----------|-------|
| Parameters | ~3B, 2-bit quantized |
| Context window | 16,384 tokens |
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
| Remaining context unused | ~15,900+ | — |

The model is operating well within its context window. Latency is dominated by output generation, not input processing. This is the 3B model's sweet spot — short input, short output, personality-driven.

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
- **Genre field** — low value for commentary now, but will be important during LoRA adapter training. Keep in `TrackInput`, exclude from prompt for now.
- **"No disclaimers"** — good, but "NEVER" is stronger per Apple's guidance.
- **"React to this track IN CHARACTER"** — redundant if the instructions already define character.
- **No few-shot example** — the model has no demonstration of what good output looks like.

### 4.3 Current Review Prompt (`getReview()`)

```swift
let prompt = """
Your character: \(personality.rawValue)
\(personality.systemPrompt)

Review the last 5 songs you just commented on. Talk about the vibe of this listening session, \
any standouts, and how the tracks flow together. 3-5 sentences, stay fully in character. No disclaimers.
"""
```

**Issues:**
- **"the last 5 songs you just commented on"** — the model has no memory of previous songs. This is a fresh session each time. The model will hallucinate a listening session.
- Same personality-in-prompt problem as commentary.
- Same redundancy issues.

### 4.4 Current Personality System Prompt (`Personality.swift`)

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
2. **Prompts own the task** — track info and the specific request go in the prompt (dynamic, minimal)
3. **One few-shot example** — demonstrates tone and length concretely
4. **Emphatic prohibitions** — caps for `NEVER`, `DO NOT`, `MUST`
5. **No redundancy** — say it once, in the right place

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
"\(track.name)" by \(track.artist), from "\(track.album)".
React.
```

**Token estimate: ~20–30 tokens**

That's it. The instructions already define who Ficino is, what tone to use, what length, what to avoid. The prompt just provides the track and says go.

### 5.4 Proposed Review Prompt (Dynamic, Per-Session)

The review needs the actual track list — the model has no memory across sessions.

```
Listening session:
1. "\(track1.name)" by \(track1.artist)
2. "\(track2.name)" by \(track2.artist)
3. "\(track3.name)" by \(track3.artist)
4. "\(track4.name)" by \(track4.artist)
5. "\(track5.name)" by \(track5.artist)

Review this listening session. How do these tracks flow together? Any standouts? 3-5 sentences.
```

**Token estimate: ~80–100 tokens**

### 5.5 Total Token Budget (Proposed)

**Commentary request:**

| Component | Current (est.) | Proposed (est.) |
|-----------|---------------|-----------------|
| Instructions | ~50 tokens | ~150 tokens |
| Prompt | ~120 tokens | ~25 tokens |
| Output | ~150 tokens | ~150 tokens |
| **Total** | **~320 tokens** | **~325 tokens** |

Similar total, but the weight shifts from prompt to instructions. The instructions are richer (persona + example), the prompt is leaner (just the track).

**Review request:**

| Component | Current (est.) | Proposed (est.) |
|-----------|---------------|-----------------|
| Instructions | ~50 tokens | ~150 tokens |
| Prompt | ~100 tokens | ~90 tokens |
| Output | ~250 tokens | ~250 tokens |
| **Total** | **~400 tokens** | **~490 tokens** |

Slightly more due to the explicit track list, but this fixes the critical bug of the model hallucinating a listening session it never had.

---

## 6. Key Changes Summary

| Aspect | Current | Proposed | Reason |
|--------|---------|----------|--------|
| Persona location | In prompt (repeated every call) | In instructions (set once) | Apple: instructions take precedence, resist injection |
| Few-shot example | None | 1 example in instructions | Apple: highest-leverage for 3B models |
| Prohibitions | Lowercase "never" | Caps `NEVER`, `DO NOT` | Apple: emphatic commands are more effective |
| Prompt content | Persona + track + rules + length | Track only + "React." | Single task, no redundancy |
| Duration field | Included | Removed | No value for commentary generation |
| Genre field | Included | Excluded from prompt (kept in `TrackInput` for future LoRA training) | Low value for prompting now; important for adapter training later |
| Review track list | Not provided (model hallucinates) | Explicit list of 5 tracks | Model has no memory across sessions |
| Length control | In both instructions and prompt | Instructions only | Say it once |

---

## 7. Open Questions

1. **Few-shot example choice** — should it be a well-known track (model can validate) or obscure (less hallucination risk)? A well-known track lets the model see a correct example; an obscure one might cause it to pattern-match the fabrication style.

2. **Genre → LoRA tone mapping** — genre is excluded from the prompt but kept in `TrackInput` as the key for adapter selection. Future plan: train LoRA adapters that map genre to persona tone (e.g., Ficino reacts reverently to jazz, abrasively to punk, atmospherically to ambient). The genre shapes the personality at the model weights level, not the prompt level.

3. **Review session memory** — the review prompt needs actual track names. `AppState` must pass the last 5 tracks to the review method, not rely on model memory.

4. **Temperature** — Ficino's personality benefits from variance. A temperature of 1.0–1.5 may produce more entertaining output than the default. Worth testing.

5. **@Generable for commentary** — could structure output as `{ commentary: String, confidence: low|medium|high }` to let the app decide whether to show or suppress low-confidence hallucinations. Adds schema overhead (~100 tokens) but enables quality gating.
