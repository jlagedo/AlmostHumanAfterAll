# ML — CLAUDE.md

Python workspace for prompt engineering, evaluation, and LoRA fine-tuning of the on-device 3B model that powers Ficino's music commentary.

## Setup

Uses **uv** for package management. Always run scripts with `uv run`:

```sh
cd ml
uv run python script.py
```

## Layout

```
prompts/       Prompt templates and variations for the Ficino personality
eval/          Evaluation scripts and benchmarks for commentary quality
training/      LoRA fine-tuning pipelines
data/          Datasets (not tracked in git)
```

## Reference Docs

These live in `docs/` at the repo root:
- `docs/3b_all.md` — Full 3B model documentation
- `docs/3b_prompt_guide.md` — Prompt engineering guide for the 3B model
- `docs/3b_lora_training.mb` — LoRA training notes
- `docs/apple_fm_specs.md` — Apple Intelligence Foundation Models specification

## Eval Pipeline

The eval pipeline uses `FMPromptRunner` (Swift CLI in `app/FMPromptRunner/`) to run prompts through the on-device 3B model.

- **Dual-stage pipeline** is the default: Stage 1 extracts facts from context, Stage 2 writes a liner note from those facts. This is controlled by the instruction JSON having an `extraction` field.
- **`run_fm.sh`** takes a version tag (e.g. `v15`) and derives the instruction file path automatically: `ml/prompts/fm_instruction_v15.json`
- **Genre examples** in the instruction JSON are injected into Stage 2's system prompt if present, but examples were dropped in v15 because the 3B model copies example content verbatim (see below).
- **`rank_output.py`** must be run in a separate terminal (it calls `claude -p`).

## Context

The app (`app/`) uses Apple's on-device `FoundationModels` framework to generate commentary. The system prompt and personality are defined in `app/MusicModel/Sources/MusicModel/Models/Personality.swift`. The prompt is enriched with music metadata by `app/FicinoCore/Sources/FicinoCore/PromptBuilder.swift`.

This workspace exists to iterate on prompts, evaluate output quality, and fine-tune the model outside of the app's runtime.

## 3B Model Prompt Lessons (confirmed across iterations)

- **Numbered rules** work significantly better than prose for constraints (preamble: 26→5, date-parrot: 16→0)
- **"DO NOT" in caps** is respected for hard constraints
- **Few-shot examples contaminate output** — the 3B model copies example phrasing verbatim as if it were fact, even with "DO NOT use content from this example" fencing. Dropped in v15.
- **Extraction step reduces hallucination** — cleaning facts before writing prevents the model from confabulating from messy context
- **The model cannot romanize non-Latin names** — Japanese names get fabricated (e.g. 米津玄師 → "Masashi Hamashi"). Names must pass through exactly as written.
- **Sample credits cause misattribution** — the model confuses sample source artists with the main artist. This is the current top issue to solve.
