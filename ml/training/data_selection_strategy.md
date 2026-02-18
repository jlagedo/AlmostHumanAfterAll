# Training Data Selection Strategy

## Pipeline

```
context_17k.jsonl (17,355 tracks)
  → prompt filter (need Genius bio or trivia)
  → ~13,000 usable tracks
  → batch API (Haiku, 2 batches: 10k + 3k)
  → ~13,000 commentary outputs
  → quality + diversity filter
  → 5,000 training samples + ~8,000 eval/test
```

## Target Split

- **5,000 training** (90/10 internal split → 4,500 train / 500 val)
- **~8,000 held-out test** — tracks the model never saw during training

## Quality Filters (automated, no human review)

Apply to Haiku batch outputs:

1. **Length** — drop too short (< 80 chars) or too long (> 800 chars)
2. **Artist/track check** — output should reference the actual artist or track name
3. **Format violations** — reject if contains markdown headers, bullet lists, numbered lists
4. **Haiku-isms** — reject if contains "I'd be happy to", "Great question", "Certainly"
5. **Hallucination spot check** — Claude-assisted review on a random sample

## Diversity Sampling

After quality filter, select 5,000 from the remaining pool:

1. **Bucket by primary genre** (from MusicKit song.genres[0])
2. **Sample proportionally** from each genre bucket, with a floor so small genres get representation
3. **Cap per artist** — max 15-20 tracks per artist to prevent overrepresentation
4. **Mix metadata richness** — ~80% context-rich, ~20% thin-context (missing bio or trivia) so the model learns to handle sparse metadata gracefully

## Rationale

- 5,000 samples is well above Apple's "complex task" threshold (5,000+)
- More data has diminishing returns for LoRA on a 3B model — quality and diversity matter more
- Thin-context samples prevent the model from being dependent on rich metadata
- Genre bucketing ensures the model generalizes across musical styles, not just chart-dominant genres
- Large held-out test set (~8k) enables robust evaluation of generalization

## Training Plan

- **Epochs**: start with 5, save checkpoint every epoch
- **GPU**: cloud H100 (estimated ~2-3 hours for 5 epochs on 5k samples)
- **Eval**: compare checkpoints on held-out test set, pick best one
- **Export**: best checkpoint → .fmadapter (~160 MB)
