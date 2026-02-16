# ML — CLAUDE.md

Python workspace for prompt engineering, evaluation, and LoRA fine-tuning of the on-device 3B model that powers Ficino's music commentary.

## Setup

```sh
cd ml
python -m venv .venv && source .venv/bin/activate
pip install -e .            # base
pip install -e '.[eval]'    # + eval dependencies
pip install -e '.[training]' # + training dependencies
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

## Context

The app (`app/`) uses Apple's on-device `FoundationModels` framework to generate commentary. The system prompt and personality are defined in `app/MusicModel/Sources/MusicModel/Models/Personality.swift`. The prompt is enriched with music metadata by `app/FicinoCore/Sources/FicinoCore/PromptBuilder.swift`.

This workspace exists to iterate on prompts, evaluate output quality, and fine-tune the model outside of the app's runtime.
