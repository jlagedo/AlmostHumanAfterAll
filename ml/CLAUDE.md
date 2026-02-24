# ML — CLAUDE.md

Python workspace for prompt engineering, evaluation, and LoRA fine-tuning of the on-device 3B model that powers Ficino's music commentary.

## Setup

Uses **uv** for package management (Python 3.14+). Always run scripts with `uv run`:

```sh
cd ml
uv run python script.py
```

Dependencies: `anthropic`, `rich`, `sentencepiece`.

## Layout

```
prompts/       Versioned instruction files (fm_instruction_v8.json through v18.json)
eval/          Evaluation pipeline
  run_eval.py    End-to-end: build prompts → run on-device model → LLM judge
  build_prompts.py  Mirrors PromptBuilder.swift, builds JSONL from raw metadata
  judge_output.py   LLM-as-judge scoring (Claude Sonnet, 5 dimensions, max 15 pts)
  run_model.sh      Invokes FMPromptRunner (Swift CLI in app/FMPromptRunner/)
  scrape_clean.py   Scrapes and cleans metadata for eval tracks
training/      LoRA fine-tuning via Anthropic Batch API
  batch_submit.py   Submit prompts to Anthropic Batch API
  batch_retrieve.py Retrieve completed batch results
  prep_splits.py    Prepare train/eval splits
  quality_check.py  Validate training data quality
  join_batches.py   Combine multiple batch outputs
  shuffle.py        Shuffle training data
  prompt/           Instruction files for training data generation
docs/          ML-specific guides
  eval_pipeline.md          How the eval pipeline works
  training_pipeline.md      Batch API workflow for training data
  lora_training_guide.md    LoRA adapter training process
  data_selection_strategy.md  Track selection for evaluation
data/          All artifacts, not tracked in git:
  eval/          Eval intermediates and output (CSVs, context, prompts, scores)
  synth/         Synthetic training data from batch API
  training/      Final train/eval splits for LoRA
  raw/           Source data (charts, batch metadata)
```

**Exception:** `data/eval/version_rank.md` and `data/eval/vrank/` are tracked — they contain the version comparison table and per-version scoring breakdowns.

## Eval Pipeline

Run the full pipeline end-to-end:

```sh
cd ml && uv run python eval/run_eval.py v18 -l 10
```

Options: `--limit`, `--passes`, `--temperature`, `--context`, `--prompts` (skip build), `--output` (skip build+model, just judge).

Individual steps:
1. **Build prompts:** `uv run python eval/build_prompts.py` — generates JSONL from raw metadata context
2. **Run model:** `eval/run_model.sh vN -limit 10` — invokes `FMPromptRunner` (Swift CLI in `app/FMPromptRunner/`), derives instruction file from version tag: `ml/prompts/fm_instruction_vN.json`
3. **Judge output:** `uv run python eval/judge_output.py <output.jsonl>` — scores responses using Claude Sonnet as LLM judge

**Do NOT run `judge_output.py` from within Claude Code** — it calls `claude -p` and cannot be nested. Remind the user to run it in a separate terminal.

## Training Pipeline

Generate synthetic training data via Anthropic Batch API:
1. `batch_submit.py` — submit JSONL prompts (uses Claude Haiku)
2. `batch_retrieve.py` — retrieve completed results
3. `join_batches.py` — combine multiple batch outputs
4. `quality_check.py` — validate data quality
5. `prep_splits.py` — prepare train/eval splits for LoRA

See `docs/training_pipeline.md` and `docs/lora_training_guide.md` for the full workflow.

## Reference Docs

These live in `docs/` at the repo root:
- `docs/3b_all.md` — Complete technical guide to the on-device 3B model
- `docs/3b_prompt_guide.md` — Prompt engineering guide for the 3B model
- `docs/3b_lora_training.md` — LoRA adapter training system (architecture, toolkit, Swift integration)
- `docs/3b_safety_filters.md` — Safety guardrail architecture, filter configs, Ficino impact
- `docs/apple_fm_specs.md` — Apple Intelligence Foundation Models technical specification
- `docs/apple_adapter_toolkit.md` — Adapter Training Toolkit v26.0.0 deep reference
- `docs/ficino_prompt_design.md` — Prompt architecture for Ficino's commentary generation
- `docs/lora_training_plan.md` — LoRA adapter training plan (data strategy, evaluation, deployment)

## Context

The app (`app/`) uses Apple's on-device `FoundationModels` framework to generate commentary. The system prompt is defined in instruction files (`ml/prompts/fm_instruction_v*.json`) and shipped via a LoRA adapter (`app/ficino_music.fmadapter/`). The prompt is enriched with music metadata by `app/MusicContext/Sources/MusicContext/PromptBuilder.swift`.

This workspace exists to iterate on prompts, evaluate output quality, and fine-tune the model outside of the app's runtime.

## Do NOT

- Modify any Swift files — this workflow is ml-only.
- Delete previous instruction versions — keep them for comparison.
- Run `judge_output.py` inside Claude Code — it calls `claude -p` and cannot be nested.
- Use few-shot examples in instruction files — the 3B model copies them verbatim as fact.
