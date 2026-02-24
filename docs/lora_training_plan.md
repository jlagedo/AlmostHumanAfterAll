<!-- HISTORICAL: This was the original LoRA training plan. The actual training used
3,000 samples (not 750) via Claude Haiku Batch API, MusicKit+Genius metadata (not
MusicBrainz/Wikipedia/Wikidata/Last.fm), plain text responses (not @Generable JSON),
and the training pipeline in ml/training/. Kept for reference on the design rationale. -->

# Fase 3 — LoRA Adapter Training for Music Insights

## The Thesis

The on-device Foundation Model (~3B params) has zero world knowledge. Fase 2 solved the data problem with a Fetch→Normalize→Score→Select→Compact→Prompt pipeline that feeds curated facts into a 4,096-token window. The model's only job is rephrasing.

But rephrasing is a skill. The base model treats all facts equally, writes generically, and has no concept of what makes music writing compelling. LoRA doesn't teach the model *what* Steely Dan is — it teaches the model *how to talk about music* when given facts.

LoRA excels at: style, tone, task structure, domain vocabulary, output consistency.
LoRA cannot do: inject factual knowledge, expand context window, bypass guardrails.

Nobody trains music-domain adapters for Apple's on-device model because the intersection of "music nerd" and "ML practitioner with Apple entitlements" is vanishingly small. That's the gap.

---

## What the Adapter Teaches

### 1. Music Storytelling Voice
**Before adapter (base model):**
> "This song was sampled by another artist. It reached number 3 on the charts."

**After adapter (trained):**
> "That bass line you're hearing? It got lifted wholesale into a 2004 hip-hop hit. The track peaked at #3 — not bad for a seven-minute jazz odyssey."

### 2. Fact Hierarchy Intuition
The model internalizes from training data that:
- Sampling chains > chart positions (more surprising)
- "Written by someone unexpected" > generic credits
- Grammy wins need context ("...in a category dominated by pop acts")
- Sparse data requires graceful handling, not padding

### 3. Domain Register
Natural use of: hook, bridge, B-side, pressing, remaster, session musician, chart entry, deep cut, liner notes, production credit, interpolation vs sample.

### 4. Structured Output Reliability
The base model already excels at JSON/structured extraction. Training with `@Generable`-shaped outputs reinforces the pattern for `MusicInsights` specifically.

### 5. Edge Case Handling
Trained examples with sparse inputs (unknown artist, no Wikipedia, just MusicBrainz basics) teach the model to work with what it has rather than hallucinate or repeat itself.

---

## Step 0 — Resolve Schema Format (Blocker)

Before generating any training data, the exact prompt/response format that the Foundation Models framework uses at inference time must be known. If `@Generable` injects its own schema or framing into the prompt, every training example must match that framing exactly.

**Action:** Once the toolkit is available, inspect what `session.respond(to:, generating: MusicInsights.self)` actually sends to the model. Log the raw prompt. Then build training data that matches.

**Pilot test:** Train two small adapters (50 examples each):
- Variant A: Response is raw JSON matching `MusicInsights` schema
- Variant B: Response is natural language, rely on `@Generable` constrained decoding at inference
- Compare output quality

**Do not proceed to full data generation until this is resolved.** Generating 750 examples against the wrong format means regenerating them all.

---

## Training Data Strategy

### Format
Apple's toolkit expects JSONL. Each line is a conversation turn:

```jsonl
[{"role": "user", "content": "PROMPT"}, {"role": "assistant", "content": "RESPONSE"}]
```

The `Schema.md` inside the toolkit covers guided generation fields and safety metadata. The response for `@Generable` output likely needs to match the JSON schema the framework injects at inference time — this is resolved in Step 0.

### Prompt Shape (must match Fase 2 `buildPrompt()` output exactly)

```
Now playing: "Aja" by Steely Dan from "Aja".

Known facts:
- Chart: Billboard #3 in 1977
- Awards: Grammy for Best Engineered Recording 1978
- Producers: Gary Katz
- Session musicians: Wayne Shorter (sax), Steve Gadd (drums)
- Genre: Jazz rock
- Written by: Donald Fagen, Walter Becker

Using ONLY the facts listed above, write 3 short fun facts.
```

### Response Shape (must match `@Generable MusicInsights`)

```json
{
  "trackFact": "That sax solo? Wayne Shorter of Weather Report fame, in what Fagen called a single perfect take.",
  "artistFact": "Steely Dan were studio perfectionists — Aja used 40+ session musicians handpicked from jazz and rock royalty.",
  "albumFact": "Hit #3 on Billboard and won the Grammy for Best Engineered Recording — recognized not for the songs, but for how impossibly good they sounded."
}
```

**Critical:** The exact JSON key names and structure must align with whatever schema the Foundation Models framework injects for `MusicInsights`. This is confirmed in Step 0.

### Volume Target

Apple's guidance: 100–1,000 samples for basic tasks, 5,000+ for complex tasks. Apple explicitly recommends quality over quantity: "A smaller dataset of clear, consistent, and well-structured samples may be more effective than a larger dataset of noisy, low-quality samples."

This task is **basic in operation** (single-turn, single output schema, narrow skill) but **multi-register** — 7 genre clusters each with distinct vocabulary. The 3B model has less pre-trained music knowledge to surface than larger models, and empirical testing on Apple's 3.2B model shows it needs more data/epochs than expected to steer (one experiment required 100 epochs with ~400 examples). LoRA literature shows style convergence in 200–300 examples for *single-register* tasks, but this is effectively 7 registers + sparse/rich handling.

Target: **560 train / 115 eval / 75 test = 750 total examples**

This sits at the top of Apple's "basic task" range (100–1,000) and provides enough volume per genre cluster for the model to learn register-specific vocabulary while generalizing the shared style.

### Diversity Matrix

The matrix uses a **tiered design**: primary axes define the grid cells, secondary axes are distributed across cells, and edge cases get a dedicated allocation.

#### Tier 1 — Primary Grid (genre cluster × data density)

These two axes most directly affect model behavior. Data density changes the task difficulty (sparse requires graceful degradation, rich requires prioritization). Genre cluster affects vocabulary, cultural context, and fact types.

**7 genre clusters:**

| Cluster | Genres | Shared register |
|---------|--------|----------------|
| **Rock / Metal** | Classic rock, punk, grunge, thrash, prog, doom | Riff, shred, distortion, headliner, guitar solo, double kick |
| **Pop / Electronic / Dance** | Synth-pop, house, techno, EDM, ambient | Hook, drop, remix, synth, BPM, crossover |
| **Hip-Hop / R&B** | Rap, trap, neo-soul, funk | Sample, beat, feature, flow, interpolation, producer credit |
| **Jazz / Blues / Soul** | Bebop, fusion, Delta blues, Motown | Session musician, standard, improvisation, groove, arrangement |
| **Country / Folk / Americana** | Bluegrass, singer-songwriter, alt-country | Nashville, storytelling, acoustic, roots, pedal steel, honky-tonk |
| **Classical** | Orchestral, opera, chamber, contemporary | Opus, movement, conductor, symphony, premiere, libretto |
| **Latin** | Reggaeton, salsa, cumbia, bossa nova, corrido, bachata, urbano | Ritmo, verso, featuring, pista, mezcla, colaboración |

**Grid (7 clusters × 3 densities = 21 cells):**

| | Sparse (2–3 facts) | Medium (4–6 facts) | Rich (7+ facts) |
|---|---|---|---|
| Rock / Metal | 30 | 30 | 30 |
| Pop / Electronic / Dance | 30 | 30 | 30 |
| Hip-Hop / R&B | 30 | 30 | 30 |
| Jazz / Blues / Soul | 22 | 22 | 22 |
| Country / Folk / Americana | 18 | 18 | 18 |
| Classical | 12 | 12 | 12 |
| Latin | 24 | 24 | 24 |

**= 546 examples across 21 cells**

Allocations reflect expected user base distribution: Rock/Pop/Hip-Hop are the bulk of listening, Latin is a first-class cluster given the strong Spanish-speaking US population and Latin American market, Classical is niche but needs its own register.

#### Tier 2 — Secondary Distribution (sampled across the grid)

Within each cell, distribute examples across these axes. Track coverage but don't require minimums per combination:

| Axis | Variants | Target |
|------|----------|--------|
| **Era** | Pre-1970, 70s–80s, 90s–2000s, 2010s+ | Each era appears in ≥90 total examples |
| **Fame** | Iconic, well-known, niche/obscure | Roughly 30/40/30% split |
| **Dominant fact type** | Samples/covers, awards/charts, credits/production, history/context | Each type appears in ≥120 total examples |

These don't create new cells — they constrain how you fill the primary grid. When selecting 30 Rock/Metal Sparse examples, ensure they span multiple eras and fame levels rather than being all Metallica tracks.

#### Tier 3 — Edge Case Allocation (dedicated block)

**104 examples** for scenarios that break default assumptions:

| Edge case | Count | Why it matters |
|-----------|-------|---------------|
| Non-Western music (Afrobeat, K-pop, etc.) | 20 | Honest minimal coverage — the model has seen these but isn't specialized |
| Instrumental tracks (no lyrics, no vocalist) | 18 | "artistFact" can't reference a singer |
| Compilations / soundtracks | 15 | Album context is unusual |
| Featuring / collaboration (3+ credited artists) | 15 | Who is "the artist"? |
| Non-English titles (beyond Latin, which is covered) | 18 | Tokenization edge cases, cultural context |
| Debut / first release (minimal history) | 18 | Similar to sparse, but the *reason* for sparsity matters |

Non-Western music (African, K-pop, Asian styles) is handled as edge cases rather than a full cluster. Better to have 20 honest examples than 50 mediocre ones for genres you can't quality-check.

#### Tier 4 — Adversarial Test Set

**100 examples** reserved for stress testing (part of the test split):

- 20 tracks with potentially edgy names/content (guardrail sensitivity)
- 20 tracks where Wikipedia and MusicBrainz data conflict
- 20 tracks with maximum fact density (10+ facts — tests prioritization)
- 20 tracks with only MusicBrainz data (no Wikipedia, no Last.fm)
- 20 tracks from the last 12 months (tests recency handling)

#### Final Allocation

| Split | Count | Composition |
|-------|-------|-------------|
| **Train** | 560 | ~410 from primary grid + ~78 edge cases + ~72 secondary-heavy |
| **Eval** | 115 | Proportional sample across all tiers |
| **Test** | 75 | Adversarial/stress (Tier 4) + proportional holdout |
| **Total** | **750** | |

#### Coverage Tracking

Build a script that reads the JSONL and reports:

```
Primary grid coverage:   21/21 cells filled (min 12, max 30)
Era coverage:            4/4 eras (min 90 each)
Fame coverage:           iconic 31%, known 39%, niche 30%
Fact-type coverage:      4/4 types (min 120 each)
Edge cases:              104/104 allocated
Sparse examples:         166 total (22% of dataset)
```

If any cell is under its minimum after generation, you know exactly what to harvest more of.

---

## Synthetic Data Generation Pipeline

Use Claude to generate training data. This is how Apple builds their own adapter datasets — synthetic data from larger models, filtered for quality.

Note: Claude as generator creates a quality ceiling — the adapter can at best replicate Claude's style on this task. Consider including 30–50 human-written examples from actual music writing to represent the true target voice, with Claude-generated examples filling volume.

### Step 1: Harvest Real API Data
Pull data from the 4 APIs (MusicBrainz, Wikipedia, Wikidata, Last.fm) for ~450 diverse tracks. Store raw responses. Track selection should be guided by the diversity matrix — ensure coverage across genre clusters, eras, and fame levels.

### Step 2: Run Through Fase 2 Pipeline
Process each track through `scoreFacts()` and `selectFacts()` to produce the exact prompt format the on-device model will see. This ensures training data matches inference-time input shape.

### Step 3: Generate Gold Responses with Claude
For each curated prompt, send to Claude with detailed style instructions:

```
You are a music journalist writing fun facts for a listener discovery app.

Rules:
- ONLY use the facts provided. Never add external knowledge.
- Write in a conversational, enthusiastic tone — like a knowledgeable friend.
- Lead with the most surprising fact.
- Use music terminology naturally (don't explain jargon).
- Each fact should be 1-2 sentences, punchy, no filler.
- When data is sparse, be honest and brief. Don't pad.
- Output valid JSON matching this schema: {"trackFact": "...", "artistFact": "...", "albumFact": "..."}

Input:
{fase2_prompt_output}
```

### Step 4: Quality Filter (Rejection Sampling)
Generate 2 variants per track. Score each on:

- **Faithfulness** (automated): For each claim in the response, extract it and verify it traces to a specific input fact. Use a separate LLM-as-judge pass with a strict verification prompt. Discard if any claim cannot be traced to input facts.
- **Voice** (automated + calibrated): Score against a rubric — uses ≥1 music domain term, ≤2 sentences per fact, no hedging phrases ("interestingly," "it's worth noting," "fun fact:"), no generic filler. Discard if score < threshold.
- **Density**: Is every sentence earning its tokens? Discard if padded.
- **Structure**: Valid JSON matching schema? Discard if malformed.

Keep the best variant. Target ~70% keep rate. At 450 tracks × 2 variants = 900 candidates, 70% keep = ~630 usable examples. Harvest additional tracks to fill gaps identified by coverage tracking.

### Step 5: Human Review Pass
Review **150 samples (20% of dataset)** manually. Check for:
- Subtle hallucinations (facts that sound plausible but aren't in the input)
- Tone drift (too academic, too casual, inconsistent)
- Repetitive patterns across examples
- Faithfulness failures the automated check missed

### Step 6: Format as JSONL
```python
import json

def format_example(prompt: str, response: dict) -> str:
    return json.dumps([
        {"role": "user", "content": prompt},
        {"role": "assistant", "content": json.dumps(response)}
    ])
```

Split: 75% train, 15% eval, 10% test.

---

## Evaluation Metrics

Define these before training. Without quantitative metrics, you can't determine if the adapter is worth deploying.

| Metric | Method | Automated? |
|--------|--------|-----------|
| **Faithfulness** | For each claim in output, verify it maps to an input fact | Yes (LLM-as-judge) |
| **Style score** | Rate conversational tone, music vocabulary usage, punchiness against rubric | Semi (LLM + human calibration) |
| **Structure validity** | Does output parse as valid `MusicInsights` JSON? | Yes |
| **Preference rate** | Blind A/B: adapter vs base model, which output do humans prefer? | No (human eval) |
| **Sparse handling** | Quality score on the ≤3-fact subset specifically | Yes (composite of above) |

**A/B test design:** Run 50 test prompts through both base model (Fase 2 prompt-only) and adapter. Blind human evaluation of preference. The adapter ships if it wins ≥65% of comparisons.

---

## Training Procedure

### Prerequisites
- Apple Developer Program membership
- Foundation Models Framework Adapter Entitlement (request from Account Holder)
- Download adapter training toolkit from Apple (entitlement-gated)
- Mac with Apple Silicon, 32GB+ RAM — or Linux with GPU
- Python 3.11 (recommended by Apple)

### Environment Setup
```bash
conda create -n adapter-training python=3.11
conda activate adapter-training
cd /path/to/toolkit
pip install -r requirements.txt
```

### Verify Base Model
```bash
python -m examples.generate --prompt "Test prompt here"
```

Note: Toolkit model weights are optimized for training, not inference. Behavior may differ from on-device Foundation Models framework.

### Train
```bash
python -m examples.train_adapter \
  --train-data /path/to/train.jsonl \
  --eval-data /path/to/valid.jsonl \
  --epochs 5 \
  --learning-rate 1e-3 \
  --batch-size 4 \
  --checkpoint-dir /path/to/checkpoints/
```

Apple's defaults are a starting point. Hyperparameter tuning:

| Parameter | Start | Notes |
|-----------|-------|-------|
| `epochs` | 5 | Watch for overfitting on eval loss after epoch 3 |
| `learning-rate` | 1e-3 | Apple's default. Try 1e-4 if loss is unstable |
| `batch-size` | 4 | Reduce to 2 if OOM on 32GB machine |

### Train Draft Model (Recommended for Production)
The draft model (~48M params) enables speculative decoding for faster inference. On a 3B on-device model, latency is a real UX concern — speculative decoding is how Apple expects production apps to hit acceptable speeds. Train the draft adapter alongside the main adapter.

### Export
```bash
python -m export.export_fmadapter \
  --output-dir ./output \
  --adapter-name MusicInsights \
  --checkpoint adapter-final.pt \
  --author "YourName"
```

**Do not modify export code.** The export logic must match exactly for compatibility with the system model.

Output: `MusicInsights.fmadapter` (~160MB)

---

## Deployment

### Architecture: Adapter as Enhancement, Prompt-Only as Fallback

The app must always work without the adapter. Fase 2 prompt-only mode is the baseline. The adapter is an enhancement layer that improves quality when available.

```swift
func generateInsights(prompt: String) async throws -> MusicInsights {
    if let adapter = try? SystemLanguageModel.Adapter(named: "MusicInsights") {
        // Adapter available — use it
        let model = SystemLanguageModel(adapter: adapter)
        let session = LanguageModelSession(model: model)
        return try await session.respond(to: prompt, generating: MusicInsights.self)
    } else {
        // Fallback to base model (Fase 2 prompt-only)
        let session = LanguageModelSession()
        return try await session.respond(to: prompt, generating: MusicInsights.self)
    }
}
```

This fallback-first architecture handles:
- Adapter not yet downloaded (first launch)
- OS update that shipped a new base model before the retrained adapter is ready
- Download failures
- Storage-constrained devices

### Distribution via Background Assets
The adapter is NOT bundled in the app binary. It's downloaded separately via the Background Assets framework, which ensures only the adapter matching the user's OS model version is fetched.

Options:
- Host on your own server
- Use Apple's App Store Connect asset packs

Each user downloads one adapter (~160MB), matched to their device's base model version.

Considerations:
- Handle download failures with retry logic
- Show Fase 2 prompt-only output while adapter downloads (not a loading screen)
- Version negotiation: app version × OS version × adapter version
- Storage-constrained devices: adapter is optional, app degrades gracefully

### Version Management
Every OS update that ships a new base model requires:
1. Download new toolkit version
2. Retrain adapter with same dataset (data pipeline unchanged)
3. Export new `.fmadapter`
4. Deploy via Background Assets

The training data and pipeline are reusable. Only the training step reruns (~2-4 hours).

---

## Open Questions (Requires Experimentation)

### 1. Guardrail Sensitivity
Content filtering has been reported as aggressive. Song titles, artist names, or lyric references might trigger blocks.

**Test plan:** Build a test set of 50 tracks with potentially edgy names/content. Run through the adapter to identify false positive rates. If problematic, the Fase 2 `buildPrompt()` may need a sanitization step.

### 2. Sparse Data Graceful Degradation
When only 2-3 facts are available, does the adapter produce better output than the base model with good prompting?

**Test plan:** Create a sparse-only eval set (20 examples with ≤3 facts). Compare base model + prompt vs adapter output quality using the evaluation metrics above.

### 3. Optimal Training Data Volume
Starting at 750 examples. Is this the sweet spot for a multi-register style task on a 3B model?

**Test plan:** If resources allow, train adapters at 375 and 750 examples. Measure eval loss convergence and qualitative output per genre cluster. If any cluster underperforms (especially Classical or Latin with fewer examples), consider targeted augmentation for that cluster rather than scaling the full dataset.

---

## Cost/Benefit Analysis

### Costs
- Entitlement approval process (unknown timeline)
- ~60-80 hours to build synthetic training pipeline + curate 750 examples (includes API integration, pipeline debugging, rejection sampling tooling, human review)
- ~2-4 hours training per adapter (on 32GB Mac)
- Retrain on every OS model update (same data, ~2-4 hours each time)
- ~160MB per adapter download per user
- Background Assets integration code

### Benefits
- Distinctive voice that prompt engineering alone can't reliably achieve on a 3B model
- Better structured output quality for `@Generable MusicInsights`
- Graceful handling of sparse/edge-case data
- Competitive moat: the full pipeline (Fase 2 data fetching + scoring + selection + curated training dataset + adapter + deployment infrastructure) is hard to replicate — the adapter alone is reproducible, but the integrated system is not
- Deep learning about LoRA, adapter training, synthetic data generation

### Decision
Ship Fase 2 (prompt-only) as v1. Build the synthetic data pipeline in parallel. Train adapter when entitlement is approved. A/B test adapter vs prompt-only on real output quality using defined evaluation metrics. Deploy adapter if it wins ≥65% of blind preference comparisons.

---

## Appendix: Example Training Pairs

### Rich Data (8 facts)
```jsonl
[{"role": "user", "content": "Now playing: \"Smells Like Teen Spirit\" by Nirvana from \"Nevermind\".\n\nKnown facts:\n- Sampled by: Destiny's Child \"Bootylicious\" (interpolation)\n- Chart: Billboard #6, UK #7\n- Producers: Butch Vig\n- Written by: Kurt Cobain, Krist Novoselic, Dave Grohl\n- Genre: Grunge, alternative rock\n- Release: 1991, DGC Records\n- Awards: MTV VMA for Best New Artist 1992\n- Influence: Widely credited with bringing alternative rock to mainstream\n\nUsing ONLY the facts listed above, write 3 short fun facts."}, {"role": "assistant", "content": "{\"trackFact\": \"Destiny's Child interpolated this track for 'Bootylicious' — grunge and R&B colliding in ways Cobain probably never imagined.\", \"artistFact\": \"All three band members share the writing credit — Cobain, Novoselic, and Grohl built that riff together before anyone knew their names.\", \"albumFact\": \"Nevermind on DGC Records didn't just chart at #6 — it's widely credited with dragging alternative rock out of the underground and into the mainstream overnight.\"}"}]
```

### Sparse Data (2 facts)
```jsonl
[{"role": "user", "content": "Now playing: \"Ouro\" by Mabe Fratti from \"Sentir Que No Sabes\".\n\nKnown facts:\n- Genre: Experimental, art pop\n- Active since: 2017\n\nUsing ONLY the facts listed above, write 3 short fun facts."}, {"role": "assistant", "content": "{\"trackFact\": \"This one sits at the intersection of experimental and art pop — genre labels that barely contain what's actually happening in the music.\", \"artistFact\": \"Mabe Fratti has been active since 2017, building a catalog that resists easy categorization.\", \"albumFact\": \"With only two genre tags and a start date to go on, the music speaks for itself — no Wikipedia page required.\"}"}]
```

### Chart-Heavy Data
```jsonl
[{"role": "user", "content": "Now playing: \"Blinding Lights\" by The Weeknd from \"After Hours\".\n\nKnown facts:\n- Chart: Billboard #1 for 4 weeks, Billboard Hot 100 Year-End #1 2020\n- Chart: UK #1, topped charts in 30+ countries\n- Producers: Max Martin, Oscar Holter, The Weeknd\n- Genre: Synthwave, electropop\n- Grammy snub: Zero nominations despite record-breaking chart run\n\nUsing ONLY the facts listed above, write 3 short fun facts."}, {"role": "assistant", "content": "{\"trackFact\": \"Year-end #1 on Billboard for 2020 and topped charts in over 30 countries — then got zero Grammy nominations. The snub that changed how the Grammys work.\", \"artistFact\": \"The Weeknd co-produced this himself alongside Max Martin — the same hitmaker behind half the pop canon.\", \"albumFact\": \"After Hours leaned hard into synthwave and electropop, a sharp left turn that became the most commercially dominant sound of 2020.\"}"}]
```

### Latin Data (5 facts)
```jsonl
[{"role": "user", "content": "Now playing: \"Gasolina\" by Daddy Yankee from \"Barrio Fino\".\n\nKnown facts:\n- Genre: Reggaeton\n- Chart: Billboard Hot 100 #17, first reggaeton track to chart mainstream\n- Producers: Luny Tunes\n- Release: 2004, El Cartel Records\n- Impact: Credited with introducing reggaeton to global mainstream audiences\n\nUsing ONLY the facts listed above, write 3 short fun facts."}, {"role": "assistant", "content": "{\"trackFact\": \"First reggaeton track to crack the Billboard Hot 100 mainstream — peaking at #17 and opening a door that never closed.\", \"artistFact\": \"Produced by Luny Tunes, the duo behind half the reggaeton canon of the 2000s, with Daddy Yankee on El Cartel Records.\", \"albumFact\": \"Barrio Fino didn't just chart — it's credited with introducing reggaeton to global mainstream audiences, turning a Caribbean genre into a worldwide force.\"}"}]
```
