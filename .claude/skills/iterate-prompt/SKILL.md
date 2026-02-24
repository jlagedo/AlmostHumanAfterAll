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
- **Prompt builder**: `ml/eval/build_prompts.py` — builds per-track prompts from context JSONL
- **Runner script**: `ml/eval/run_model.sh` — runs FMPromptRunner with current instruction file
- **Judge script**: `ml/eval/judge_output.py` — LLM-as-judge scoring (run manually by user)
- **End-to-end**: `ml/eval/run_eval.py` — builds prompts → runs model → judges in one command
- **Ranking results**: `ml/data/eval/version_rank.md` — summary table across versions
- **Ranking details**: `ml/data/eval/vrank/{version}_details.md` — per-response breakdown
- **Reference**: `docs/3b_prompt_guide.md` — Apple's prompt engineering guide for the 3B model

## Steps

### 1. Assess current state

- Read the latest instruction file (check which version `run_model.sh` points to)
- Read the latest ranking results in `ml/data/eval/version_rank.md` and `ml/data/eval/vrank/` for per-response details
- Identify failure modes from the ranking: check flags (P=preamble, H=hallucination, D=date-parrot, E=echo, C=CTA-parrot, M=misattribution), bottom 5, and per-dimension scores
- Do NOT read raw output JSONL files or try to score responses yourself — that's what judge_output.py is for

### 2. Propose changes (STOP and ask)

**Before writing anything**, present your analysis and proposed changes to the user. Use `AskUserQuestion` or just explain what you want to change and why, then wait for approval. Do NOT write files or run commands until the user says to proceed.

Include:
- Summary of failure modes from the ranking data
- What you'd change in the instruction file and why
- Whether the prompt template (`build_prompts.py`) also needs changes

### 3. Write the next version

Once the user approves (or adjusts) the plan:

- Create `ml/prompts/fm_instruction_vN.json` (increment version number)
- Optionally edit `ml/eval/build_prompts.py` if the prompt template needs changes
- `run_model.sh` derives the instruction file from the version arg — no need to edit it

Key principles (confirmed across v8–v15 iterations):
- Numbered rules work significantly better than prose for the 3B model
- "DO NOT" in caps for hard constraints
- **DO NOT use few-shot examples** — the 3B model copies example content verbatim as fact, even with explicit fencing. This was confirmed in v15: examples caused hallucination to spike (8→18), removing them brought it back down (18→6).
- Delimiter wrapping (`[Context]...[End of Context]`, `[Facts]...[End of Facts]`) prevents echo
- Keep instructions concise — they count against the 4,096-token context window
- The dual-stage pipeline (extract facts → write from facts) is now the default and reduces hallucination
- The extraction prompt should strip dates — adding "DO NOT include release dates or years" to extraction eliminated date-parrot (16→0)

### 4. Regenerate and run

```bash
cd ml && uv run python eval/run_eval.py vN -l 10
```

Or run steps individually:
```bash
cd ml && uv run python eval/build_prompts.py
cd ml/eval && ./run_model.sh vN -limit 10
```

Use a 5-minute timeout for the runner — it's calling the on-device model.

### 5. Remind user to judge

After the runner completes, remind the user to run the judge script **from a separate terminal** (it calls `claude -p` and cannot run inside Claude Code):

```
Run this in a separate terminal to score the output:

cd ml && uv run python eval/judge_output.py data/eval/output_vN_YYYYMMDD_HHMMSS.jsonl
```

Use the actual filename from the runner output. Do NOT attempt to run judge_output.py yourself.

### 6. Analyze results and recommend next steps

Once the user has run the ranking and the results are in `version_rank.md`:

- Read the updated `version_rank.md` to compare the new version against previous ones
- Read `vrank/{version}_details.md` for per-response breakdown
- A real improvement needs a total delta of at least ~0.7 to clear run-to-run noise
- Flag counts (especially H and M) are the most stable signal
- Suggest another iteration with specific changes, or declare the version ready for a full run

### Known issues resolved by LoRA (v18)

The v18 LoRA adapter (3,000 training samples) eliminated all failure flags — zero preambles, zero hallucinations, zero misattributions across 81 test tracks. Issues that were present in v15-v17 (misattribution, fabricated romanizations, thin-context padding) were all resolved by fine-tuning. Future prompt iterations may reintroduce some if the instruction changes significantly.

## Do NOT

- Modify any Swift files — this workflow is ml-only. Changes go to the app later.
- Delete previous instruction versions — keep them for comparison.
- Run without `-l` (limit) unless the user explicitly asks for a full run.
- Run `judge_output.py` — it calls `claude -p` and cannot be nested inside Claude Code.
- Score or evaluate raw output JSONL yourself — always use the ranking results.
- Use few-shot examples in instruction files — the 3B model copies them verbatim as fact.
