# CLAUDE.md

Monorepo with two independent workspaces and shared docs.

```
app/          Swift/Xcode — macOS menu bar app (Apple Intelligence commentary on music)
ml/           Python — prompt engineering, evaluation, LoRA training for the on-device 3B model
docs/         Shared reference material (Apple FM specs, prompt guides, training notes)
```

`app/` and `ml/` are fully independent — the Xcode project knows nothing about the Python workspace and vice versa. They connect through the model: `ml/` experiments with prompts and fine-tuning, `app/` ships the results on-device.

Each workspace has its own `CLAUDE.md` with detailed guidance.
