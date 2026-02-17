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

- **`run_fm.sh`** takes a version tag (e.g. `v15`) and derives the instruction file path automatically: `ml/prompts/fm_instruction_v15.json`
- **`rank_output.py`** must be run in a separate terminal (it calls `claude -p`).
- Runner uses `FMPromptRunner` (Swift CLI in `app/FMPromptRunner/`).

## Context

The app (`app/`) uses Apple's on-device `FoundationModels` framework to generate commentary. The system prompt and personality are defined in `app/MusicModel/Sources/MusicModel/Models/Personality.swift`. The prompt is enriched with music metadata by `app/FicinoCore/Sources/FicinoCore/PromptBuilder.swift`.

This workspace exists to iterate on prompts, evaluate output quality, and fine-tune the model outside of the app's runtime.
