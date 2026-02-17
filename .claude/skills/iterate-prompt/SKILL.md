---
name: iterate-prompt
description: Iterate on Ficino's FM instruction prompt and evaluate results. Use when tuning the on-device model's personality and output quality.
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion
argument-hint: [direction or "auto"]
---

# Prompt Iteration Workflow

You are iterating on Ficino's on-device 3B model prompt — the instruction file (system prompt) and the prompt template (per-turn format). The goal is to improve commentary quality: grounded in context, warm liner-note tone, 2-3 sentences, no hallucination.

## Files

- **Instruction files**: `ml/prompts/fm_instruction_v*.json` — system prompt versions
- **Prompt template**: `ml/eval/gen_fm_prompt.py` — builds per-track prompts from context JSONL
- **Runner script**: `ml/eval/run_fm.sh` — runs FMPromptRunner with current instruction file
- **Ranking script**: `ml/eval/rank_output.py` — LLM-as-judge scoring (run manually by user)
- **Ranking results**: `ml/eval/version_rank.md` — summary table across versions
- **Ranking details**: `ml/eval/vrank/{version}_details.md` — per-response breakdown
- **Reference**: `docs/3b_prompt_guide.md` — Apple's prompt engineering guide for the 3B model
- **App personality** (read-only, for reference): `app/MusicModel/Sources/MusicModel/Models/Personality.swift`

## Steps

### 1. Assess current state

- Read the latest instruction file (check which version `run_fm.sh` points to)
- Read the latest ranking results in `ml/eval/version_rank.md` and `ml/eval/vrank/` for per-response details
- Identify failure modes from the ranking: check flags (P=preamble, H=hallucination, D=date-parrot, E=echo, C=CTA-parrot, M=misattribution), bottom 5, and per-dimension scores
- Do NOT read raw output JSONL files or try to score responses yourself — that's what rank_output.py is for

### 2. Propose changes (STOP and ask)

**Before writing anything**, present your analysis and proposed changes to the user. Use `AskUserQuestion` or just explain what you want to change and why, then wait for approval. Do NOT write files or run commands until the user says to proceed.

Include:
- Summary of failure modes from the ranking data
- What you'd change in the instruction file and why
- Whether the prompt template (`gen_fm_prompt.py`) also needs changes

### 3. Write the next version

Once the user approves (or adjusts) the plan:

- Create `ml/prompts/fm_instruction_vN.json` (increment version number)
- Optionally edit `ml/eval/gen_fm_prompt.py` if the prompt template needs changes
- Update `ml/eval/run_fm.sh` to point at the new instruction file

Key principles from the prompt guide:
- Numbered rules work better than bullet points for the 3B model
- "DO NOT" in caps for hard constraints
- Few-shot examples are the strongest signal — add examples for edge cases
- Delimiter wrapping (`[Context]...[End of Context]`) prevents echo
- Keep instructions concise — they count against the 4,096-token context window
- Too many DON'Ts make the model clinical and flat — balance constraints with voice

### 4. Regenerate and run

```bash
cd ml && uv run python eval/gen_fm_prompt.py
cd ml/eval && ./run_fm.sh vN -limit 10
```

Use a 5-minute timeout for the runner — it's calling the on-device model.

### 5. Remind user to rank

After the runner completes, remind the user to run the ranking script **from a separate terminal** (it calls `claude -p` and cannot run inside Claude Code):

```
Run this in a separate terminal to score the output:

cd ml/eval && python rank_output.py ../data/eval_output/output_vN_YYYYMMDD_HHMMSS.jsonl
```

Use the actual filename from the runner output. Do NOT attempt to run rank_output.py yourself.

### 6. Analyze results and recommend next steps

Once the user has run the ranking and the results are in `version_rank.md`:

- Read the updated `version_rank.md` to compare the new version against previous ones
- Read `vrank/{version}_details.md` for per-response breakdown
- A real improvement needs a total delta of at least ~1.5 to clear run-to-run noise
- Flag counts (especially H and M) are the most stable signal
- Suggest another iteration with specific changes, or declare the version ready for a full run

## Do NOT

- Modify any Swift files — this workflow is ml-only. Changes go to the app later.
- Delete previous instruction versions — keep them for comparison.
- Run without `-limit` unless the user explicitly asks for a full run.
- Run `rank_output.py` — it calls `claude -p` and cannot be nested inside Claude Code.
- Score or evaluate raw output JSONL yourself — always use the ranking results.
