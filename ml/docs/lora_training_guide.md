# LoRA Training Guide

## Toolkit

- **Location**: `~/Developer/adapter_training_toolkit_v26_0_0/`
- **Version**: 26.0.0 (first non-beta)
- **Base model signature**: `9799725ff8e851184037110b422d891ad3b92ec1` (macOS 26.0 only)
- **Entitlement**: granted, adapter name must be `\w+` only (no hyphens)

## Token Budget (measured with Apple's tokenizer)

| Component | Tokens |
|-----------|--------|
| System prompt | 71 (constant) |
| User prompt (metadata) | median 805, p75 1099, max 3108 |
| Assistant response | median 144, max 200 |
| **Total per sample** | **median 1012, avg 1140** |
| Over 4096 limit | 0 out of 81 tested |

## Training Data Format

Each JSONL line is a JSON array:
```jsonl
[{"role": "system", "content": "A conversation between a user and a helpful assistant. <Ficino instruction>"}, {"role": "user", "content": "<structured metadata + task prompt>"}, {"role": "assistant", "content": "<Haiku commentary>"}]
```

**Important**: prepend Apple's default instruction `"A conversation between a user and a helpful assistant."` to the Ficino system prompt — the model was optimized for it.

## Recommended Training Config

```bash
python -m examples.train_adapter \
  --train-data train.jsonl \
  --eval-data eval.jsonl \
  --epochs 5 \
  --learning-rate 1e-3 \
  --batch-size 4 \
  --pack-sequences \
  --max-sequence-length 4095 \
  --precision bf16-mixed \
  --checkpoint-dir ./checkpoints/ \
  --checkpoint-frequency 1
```

### Key flags
- `--pack-sequences` + `--max-sequence-length 4095`: packs ~3.6 samples per slot → **3.5x speedup**
- `--precision bf16-mixed`: f32 model weights, bf16 compute (default, safe choice)
- `--checkpoint-frequency 1`: save every epoch
- Toolkit auto-keeps top 2 best checkpoints by eval loss + `adapter-final.pt`

### What NOT to use
- `--precision bf16`: reported to produce degenerate output ("Vac Vac Vac...")
- `--compile-model`: CUDA only, not for MPS
- Don't modify anything in `export/`

## Time & Cost Estimates (H100)

| Epochs | Steps (bs=4, packed) | Time | Cost (~$2.50/hr) |
|--------|---------------------|------|-------------------|
| 5 | ~1,785 | ~1.5-2 hrs | ~$4-5 |
| 10 | ~3,570 | ~3-4 hrs | ~$8-10 |

## Packing Math

- Avg sample: 1,140 tokens
- Context window: 4,095 tokens
- Samples per slot: ~3.6
- Effective batch size (bs=4 × 3.6): ~14 samples/step
- Without packing: 4 samples/step

## Training on Cloud GPU

1. Rent H100 instance (RunPod, Lambda Labs, Vast.ai)
2. `scp` toolkit (2.13 GB) + training JSONL to instance
3. `conda create -n adapter-training python=3.11 && conda activate adapter-training`
4. `pip install -r requirements.txt`
5. Run training
6. `scp` all checkpoints back (~160 MB each)
7. Kill instance

## Eval Locally

Test checkpoints on your Mac using `generate.py` (no GPU needed for inference):
```bash
cd ~/Developer/adapter_training_toolkit_v26_0_0
python -m examples.generate \
  --prompt eval_prompts.jsonl \
  --checkpoint ./checkpoints/adapter-epoch3.pt \
  --max-new-tokens 256 \
  --temperature 0.7
```

## Export to .fmadapter

```bash
python -m export.export_fmadapter \
  --adapter-name ficino_music \
  --checkpoint ./checkpoints/adapter-best.pt \
  --draft-checkpoint ./checkpoints/draft-model-final.pt \
  --output-dir ./exports/
```

Output: `ficino_music.fmadapter` (~160 MB package)

## Draft Model (optional, for speculative decoding)

After adapter training, optionally train the draft model for 2-4x inference speedup:
```bash
python -m examples.train_draft_model \
  --checkpoint ./checkpoints/adapter-final.pt \
  --train-data train.jsonl \
  --eval-data eval.jsonl \
  --epochs 5 \
  --learning-rate 1e-3 \
  --batch-size 4 \
  --checkpoint-dir ./checkpoints/
```

## Epoch Guidelines

- Apple default: 2 epochs (often too few)
- Apple recommended: 3-5 epochs
- Small datasets (<500): may need 50-100 epochs
- Your dataset (5,000 samples): 5 epochs is a good start, check eval loss curve
- Diminishing returns after ~3 epochs for instruction-style tasks
- Save every epoch, compare eval loss, pick best checkpoint

## Gotchas

- Each adapter locked to ONE OS model version — retrain when Apple updates
- Adapter name: letters/numbers/underscores only, hyphens cause silent load failures
- 16 GB Mac will OOM on training — need 32 GB+ or cloud GPU
- Model biased toward short responses — keep training data responses short too
- The tokenizer at `assets/tokenizer.model` works standalone for token counting
