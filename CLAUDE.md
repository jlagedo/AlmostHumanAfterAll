# CLAUDE.md

macOS menu bar app that delivers Apple Intelligence commentary on the music you're listening to. Uses Apple's on-device 3B Foundation Model, fine-tuned with a LoRA adapter trained on music metadata.

## Repository Structure

```
app/          Swift/Xcode — macOS menu bar app (Apple Intelligence, on-device)
ml/           Python — prompt engineering, evaluation, LoRA training for the 3B model
docs/         Shared reference material (Apple FM specs, prompt guides, training notes)
.claude/      Skills and local settings
```

`app/` and `ml/` are fully independent workspaces — each has its own `CLAUDE.md` with detailed guidance. They connect through the model: `ml/` iterates on prompts and fine-tuning, `app/` ships the results on-device via `FoundationModels` framework.

## Build (from repo root)

```sh
xcodebuild -project app/Ficino.xcodeproj -scheme Ficino -derivedDataPath ./build build
```

## Key Constraints

- **macOS 26+ only.** Verify API availability on macOS — do not assume iOS availability.
- **Never modify `.pbxproj`** — Xcode 16+ synchronized folders auto-detect file changes on disk.
- **Swift 6.2** with strict concurrency. All services use actor isolation.
- **App sandbox enabled** with `com.apple.security.network.client` for MusicKit catalog access.

## Reference Docs (`docs/`)

### Project
- `ficino.md` — Product overview, architecture, competitive landscape, cost structure
- `ficino_prompt_design.md` — Prompt architecture for Ficino's on-device commentary generation
- `lora_training_plan.md` — LoRA adapter training plan (data strategy, evaluation, deployment)
- `music_context_pipeline.md` — Music data pipeline design (Fetch → Score → Select → Prompt) with Swift code
- `preprocessing_strategies.md` — MusicKit + Genius API schemas, extraction and compression strategies

### Apple FM Reference
- `apple_fm_specs.md` — Apple Intelligence Foundation Models technical specification
- `3b_all.md` — Complete technical guide to the on-device 3B model
- `3b_prompt_guide.md` — Prompt engineering guide for the 3B model
- `3b_lora_training.md` — LoRA adapter training system (architecture, toolkit, Swift integration)
- `3b_safety_filters.md` — Safety guardrail architecture, filter configs, false positives, Ficino impact
- `apple_adapter_toolkit.md` — Adapter Training Toolkit v26.0.0 deep reference

### Working Notes
- `musickit_api_samples.md` — Raw MusicKit API output samples (Billie Jean, Bohemian Rhapsody)
- `runpod_ssh_setup.md` — RunPod SSH and file transfer setup
- `scratch.md` — Scratchpad (model output samples)
- `testing_flow.md` — Testing commands

## Skills

- **`iterate-prompt`** — Workflow for tuning FM instruction prompts and evaluating results. Invoke with `/iterate-prompt`.
