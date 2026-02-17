# Foundation Models — Safety Filters

Reference doc covering Apple's on-device safety filtering system as it applies to the FoundationModels framework (and by extension, Ficino's music commentary generation).

## Architecture

The safety system is multi-layered — not a single check:

1. **Model alignment** — the 3B model itself is RLHF-trained to refuse harmful requests. This produces *soft refusals* ("I'm afraid I can't do that") that don't throw errors — you have to parse the output text to detect them.
2. **Guardrail models** — separate lightweight models that scan both input prompts and generated output. These produce *hard errors* (`guardrailViolation`).
3. **Regex deny lists** — encrypted word/phrase filters shipped with the OS. Pattern-matched against input and output.
4. **Embedding similarity matching** — semantic blocking via `safety_embedding_deny` assets. Catches rephrased or obfuscated attempts.

When layers 2–4 trigger, the framework throws a `guardrailViolation` error:

```swift
catch let error as LanguageModelSession.GenerationError {
    switch error {
    case .guardrailViolation:
        // Input or output triggered Apple's safety filters
    }
}
```

Two distinct sub-types exist at the internal level:
- `InputBlockedError` — the prompt itself was rejected
- `OutputBlockedError` — the generated text was rejected mid-stream

## Blocked Content Categories

From Apple's safety taxonomy (documented in the 2025 FM tech report and WWDC25 session 248):

| Category | Description |
|---|---|
| CSAM | Child sexual exploitation and abuse imagery |
| Hate speech / slurs | Racial, ethnic, nationality, LGBTQ+, disability slurs |
| Sexual / nudity | Adult sexual material, NSFW content |
| Violence / gore | Graphic violence descriptions |
| Self-harm | Suicide, self-injury references |
| Drugs | Drug-related content |
| Weapons | Weapons-related material |
| Terrorism / extremism | Extremist or terrorist content |
| Harassment | Bullying, mean-spirited content |
| Offensive language | General profanity |
| PII / financial data | Personally identifiable information |
| Toxic content | Generally corrosive or toxic material |

Human evaluation consensus shows a **20–30% disagreement rate** on subjective safety tasks, which partly explains the false positive rate.

## The Decrypted Filter Configs

A developer (BlueFalconHD) reverse-engineered Apple's actual safety filter configuration files from macOS and published them:

**Repository:** [github.com/BlueFalconHD/apple_generative_model_safety_decrypted](https://github.com/BlueFalconHD/apple_generative_model_safety_decrypted)

### Filter Mechanisms

The config uses four enforcement types:

| Mechanism | Behavior |
|---|---|
| `reject` | Exact phrases that block the entire request |
| `remove` | Content silently stripped from output |
| `replace` | Substitution mappings (e.g. brand capitalization fixes) |
| `regexReject` / `regexRemove` / `regexReplace` | Regex pattern-based matching |

### What the Regex Filters Target

- Racial, ethnic, and nationality-based slurs and derogatory terms
- Disability-related slurs
- LGBTQ+ slurs (both clinical and derogatory variants)
- Sexual and adult content descriptors
- References to self-harm and violence
- Religious and ideological slur labels
- Animal references used as insults
- References to specific political figures and AI systems
- Common obfuscation attempts (character spacing, substitution, repeated characters)

### Context-Dependent Configs

There are approximately **94 distinct filter configurations** covering different Apple features. Each has different strictness levels:

- **Proactive summarization** — strictest (e.g. death-related content blocked to avoid emotionless AI summaries of loss)
- **User-requested summarization** — moderately strict
- **Foundation Models framework API** — what third-party developers (us) hit
- **Writing tools** (compose, rewrite, proofread) — feature-specific
- **Mail, Messages, Photos/Memories, Code Intelligence, Visual Intelligence** — each has its own config

Regional overrides also exist (e.g. `region_CN_metadata.json` for China-specific filtering).

## Known False Positive Problems

Developers have widely reported aggressive false positives:

- News articles about death are routinely rejected
- Political news from mainstream sources gets blocked
- Articles about political figures and their influence are rejected even in permissive mode
- The soft-refusal path ("I can't do that") doesn't throw exceptions, requiring output parsing to detect

Apple has acknowledged they are "actively working to improve guardrail false-refusals."

## Impact on Ficino

Music commentary is particularly vulnerable to these filters:

| Music Content | Filter Category Triggered |
|---|---|
| Death/violence in lyrics or album themes (metal, hip-hop, goth, punk) | Violence, gore, self-harm |
| Profanity in song titles or artist names | Offensive language, regex deny lists |
| Drug references (common across many genres) | Drugs |
| Sexual content in descriptions | Sexual/nudity |
| Edgy or provocative artist personas | Harassment, toxic content |

The regex deny lists are the most dangerous for us — a song title containing a slur or profanity could trigger a hard block on the entire prompt regardless of the commentary's intent.

## Available Guardrail Modes

```swift
// Default — more restrictive
let session = LanguageModelSession(model: .default)

// Permissive — less restrictive, intended for content transformation
let session = LanguageModelSession(
    model: SystemLanguageModel(
        useCase: .contentTagging,
        guardrails: .permissiveContentTransformations
    )
)
```

**Important caveats:**
- `.permissiveContentTransformations` is less restrictive but **not unrestricted** — it still triggers on plenty of content
- Even with permissive guardrails, the model's alignment training can still produce soft refusals
- You **cannot fully disable** the default guardrail — it is always applied
- Apple's docs say this mode is intended for text-to-text transformations, not open-ended generation

## Mitigation Strategies

1. **Structured output (`@Generable`)** — constraining output to enums, predefined options, and regex-validated fields reduces guardrail triggering
2. **Restrict user input via UI** — dropdowns/selections instead of free text minimizes violations
3. **Embed user content in larger system prompts** — making potentially edgy content a small component within detailed instructions helps contextualize
4. **Sanitize music metadata before injection** — strip or rephrase known problematic terms in song titles, artist names, or lyric snippets before they enter the prompt
5. **Graceful fallback** — always handle `guardrailViolation` with a reasonable fallback message rather than crashing or showing an error
6. **File feedback** — Apple asks developers to submit false-positive triggers through Feedback Assistant

## Security Research Notes

CyCraft's independent analysis (June 2025) measured the 3B model at:
- **99.5% jailbreak resistance** — highest among comparable ~3B models
- **75.9% prompt extraction resistance** — also best in class

However, they found that reframing requests using "research," "simulation," or "red-team" language bypassed protections in ~26% of cases.

## Sources

- [Apple FM Tech Report 2025](https://machinelearning.apple.com/research/apple-foundation-models-tech-report-2025)
- [WWDC25 #248: Explore prompt design & safety for on-device foundation models](https://developer.apple.com/videos/play/wwdc2025/248/)
- [Apple Acceptable Use Requirements](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/)
- [BlueFalconHD: Decrypted Safety Filters](https://github.com/BlueFalconHD/apple_generative_model_safety_decrypted)
- [CyCraft: LLM Safety Analysis of Apple's On-Device FM](https://www.cycraft.com/en/post/apple-on-device-foundation-model-en-20250630)
- [Apple Developer Forums: Model Guardrails Too Restrictive?](https://developer.apple.com/forums/thread/787736)
- [Apple Developer Forums: Foundation Models Detected Content](https://developer.apple.com/forums/thread/802921)
