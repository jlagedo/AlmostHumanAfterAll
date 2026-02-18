# Apple Foundation Models Adapter Training Toolkit v26.0.0

Deep reference for `~/Developer/adapter_training_toolkit_v26_0_0/`. First non-beta release, ships with macOS 26.0.

## Directory Structure

```
adapter_training_toolkit_v26_0_0/
├── assets/
│   ├── base-model.pt              12.0 GB   Frozen 3B base model weights
│   ├── draft-model.pt            186.0 MB   Draft model weights (for speculative decoding)
│   ├── draft.mil                   7.7 MB   CoreML MIL template for draft model export
│   ├── tokenizer.model             2.6 MB   SentencePiece tokenizer (standalone, works without torch)
│   ├── weights_spec.json                     Layer names + shapes for adapter extraction
│   └── weights_template.bin       24.0 MB    Binary template for .fmadapter export
├── examples/
│   ├── train_adapter.py                      Main LoRA training script
│   ├── train_draft_model.py                  Draft model distillation script
│   ├── generate.py                           Local inference / eval script
│   ├── data.py                               Dataset loading, preprocessing, packing
│   ├── messages.py                           Message types and chat template
│   ├── utils.py                              Model loading, checkpoint saving, precision config
│   └── toy_dataset/
│       ├── playwriting_train.jsonl            Example training data (kids' play scripts)
│       └── playwriting_valid.jsonl            Example validation data
├── export/
│   ├── export_fmadapter.py                   Converts checkpoint → .fmadapter package
│   ├── export_utils.py                       Weight conversion, CoreML quantization
│   └── constants.py                          BASE_SIGNATURE, asset paths
├── requirements.txt
└── LICENSE.md
```

Total size: ~14.4 GB (dominated by base-model.pt).

## Core Library: `tamm`

The toolkit depends on `tamm~=0.1.0`, Apple's internal ML library (not open source, distributed as a wheel). It provides:

- **`TransformerStack`** — the 3B model architecture
- **`TransformerStackConfig`** — model config (loaded from base-model.pt checkpoint)
- **`AFMChatTemplateV6Preprocessor`** — applies the chat template (special tokens, role formatting)
- **`PackedInstructMessagesDataset`** — sequence packing implementation
- **`SchemaAugmenter`** — guided/structured generation (JSON schema constraints)
- **`InverseKLLoss`** — distillation loss for draft model training

`tamm` handles all the model internals — the `examples/` scripts are thin wrappers around it.

## Training Pipeline

### `examples/train_adapter.py` — LoRA Training

The main training entry point. Standard PyTorch training loop with LoRA-specific details.

**Optimizer**: AdamW (PyTorch default)
- Learning rate: configurable, default 1e-3
- Weight decay: configurable
- LR schedule: cosine decay with linear warmup (10% of total steps)

**Precision modes** (`--precision`):
| Mode | Model weights | Compute | Notes |
|------|--------------|---------|-------|
| `bf16-mixed` | fp32 | bf16 | Default, safe choice |
| `bf16` | bf16 | bf16 | **Broken** — produces degenerate output ("Vac Vac Vac...") |
| `fp32` | fp32 | fp32 | Slow, no real benefit |

**Loss**: Standard cross-entropy on next-token prediction. Only the assistant turn tokens contribute to the loss (system/user tokens are masked via segment IDs from the chat template preprocessor).

**Checkpoint saving** (`AdapterCheckpointSaver`):
- Saves only adapter weights (not the full 12GB base model)
- Each checkpoint is ~160 MB
- Keeps the top N best checkpoints by eval loss (default N=2)
- Always saves `adapter-final.pt` at the end regardless of eval loss
- Checkpoint filenames: `adapter-epoch{N}.pt`

**What gets trained**: Only parameters with "adapter" in their name. The base model is loaded frozen, then `requires_grad` is enabled selectively:
```python
for name, param in model.named_parameters():
    param.requires_grad = "adapter" in name
```

This is 66.6M trainable parameters out of 3.18B total (~2.1%).

**Key flags**:
- `--pack-sequences` — enables sequence packing (3.5x throughput)
- `--max-sequence-length 4095` — context window for packing (must be ≤4096)
- `--compile-model` — torch.compile, CUDA only, not for MPS
- `--checkpoint-frequency N` — save every N epochs

### `examples/data.py` — Data Loading

Handles the full data pipeline from JSONL to training tensors.

**Input format**: Each JSONL line is a JSON array of messages:
```json
[{"role": "system", "content": "..."}, {"role": "user", "content": "..."}, {"role": "assistant", "content": "..."}]
```

**Preprocessing flow**:
1. Load JSONL → list of `InstructMessages` (list of Message dicts)
2. Validate: must have system + user + assistant roles, content must be non-empty strings
3. Apply `AFMChatTemplateV6Preprocessor` — converts messages to token IDs with special tokens and segment boundaries
4. If packing enabled: `PackedInstructMessagesDataset` bins multiple samples into one sequence up to `max_sequence_length`

**Segment IDs**: The chat template produces segment IDs alongside token IDs. These mark which tokens belong to system/user (segment 0) vs assistant (segment 1). The loss function only trains on segment 1 tokens — the model learns to generate assistant responses, not to memorize prompts.

**Validation**: Rejects samples where:
- Any message has a non-string content field
- Required roles are missing
- Messages array is empty

### `examples/generate.py` — Inference

Local inference script for evaluating checkpoints. Works on CPU/MPS (no GPU needed).

**Input modes**:
- `--prompt "text"` — single text prompt
- `--prompt file.jsonl` — JSONL file with message arrays (same format as training data, minus the assistant turn)

**Decoding**:
- Greedy (default) or sampling with temperature
- `--max-new-tokens N` — generation length limit
- `--temperature T` — sampling temperature (0 = greedy)

**Speculative decoding**: If `--draft-checkpoint` is provided, uses the draft model for speculative decoding (2-4x faster inference). The draft model proposes tokens, the main model verifies them in parallel.

### `examples/messages.py` — Types and Templates

Defines the message format:

```python
class Message(TypedDict):
    role: str      # "system", "user", or "assistant"
    content: str

InstructMessages = list[Message]
```

**Default system message**: `"A conversation between a user and a helpful assistant."` — the base model was fine-tuned expecting this prefix. Custom system prompts should be appended after it, not replace it.

**Locale support**: Has locale-aware default system messages. Notably includes `PT_BR` (Brazilian Portuguese), suggesting the model has multilingual capability.

### `examples/utils.py` — Model and Checkpoint Utilities

**`load_base_model(checkpoint_path, device)`**:
1. Loads `TransformerStackConfig` from the checkpoint
2. Instantiates `TransformerStack` with the config
3. Loads weights from checkpoint
4. Freezes all parameters
5. Enables gradients only for parameters with "adapter" in the name
6. Returns model

**`load_draft_model(checkpoint_path, device)`**:
- Separate loading path for the smaller draft model
- Same pattern but different config/architecture

**`load_tokenizer()`**:
- Returns a SentencePiece tokenizer from `assets/tokenizer.model`
- Standalone — works without loading the model

**`PrecisionConfig`**:
- Maps `--precision` flag to torch dtype settings
- Configures autocast context managers for forward/backward passes

**`AdapterCheckpointSaver`**:
- Extracts only adapter parameters from the model state dict
- Saves them as a standard PyTorch checkpoint
- Tracks eval loss per checkpoint
- Keeps top N best + final
- Each save: filters `state_dict` for keys containing "adapter", saves with `torch.save`

**`SchemaAugmenter`**:
- For guided generation — constrains output to match a JSON schema
- Not relevant for Ficino (we want free-form text)

## Draft Model Training

### `examples/train_draft_model.py` — Knowledge Distillation

Trains a small "draft" model that mimics the adapter-tuned base model. Used for speculative decoding at inference time (2-4x speedup on-device).

**Architecture**: 48.8M parameter mini-transformer (vs 3.18B for the base). Much faster to run but less accurate — the base model verifies its predictions.

**Training method**: Knowledge distillation with inverse KL divergence loss (`InverseKLLoss` from `tamm`):
- **Teacher**: Base model + trained adapter (frozen during draft training)
- **Student**: Draft model (trainable)
- The student learns to match the teacher's output distribution, not the ground truth tokens

**Key difference from adapter training**:
- LR schedule: linear warmup only, no cosine decay
- Loss: inverse KL divergence (not cross-entropy)
- Both teacher and student models loaded into memory simultaneously

**Output**: `draft-model-final.pt` checkpoint, used during export.

## Export Pipeline

### `export/export_fmadapter.py` — Package Builder

Converts a trained adapter checkpoint into a `.fmadapter` package that macOS can load.

**Usage**:
```bash
python -m export.export_fmadapter \
  --adapter-name ficino_music \
  --checkpoint ./checkpoints/adapter-best.pt \
  --draft-checkpoint ./checkpoints/draft-model-final.pt \
  --output-dir ./exports/
```

**Adapter name rules**: Must match `^\w+$` (letters, numbers, underscores only). Hyphens cause silent load failures on-device.

**What it produces**: `ficino_music.fmadapter` — a directory package containing:
- Converted adapter weights (fp16 binary blob)
- Converted draft model (CoreML MIL format, 4-bit palettized)
- `metadata.json` with adapter identifier and base model signature

### `export/export_utils.py` — Weight Conversion

**`AdapterConverter`**:
1. Loads adapter checkpoint
2. Extracts adapter layer weights using `weights_spec.json` (maps layer names to positions)
3. **Permutes QK weights for RoPE** — rotary position embeddings require a specific weight layout that differs between training and inference formats
4. Casts everything to fp16
5. Writes as a flat binary blob matching `weights_template.bin` layout

**`DraftModelConverter`**:
1. Loads draft model checkpoint
2. Converts to CoreML MIL (Model Intermediate Language) format
3. Applies **4-bit palettization** — quantizes weights to 4-bit with a lookup table per tensor
4. Uses `coremltools==8.3.0` for the conversion
5. Output: CoreML `.mlpackage` embedded in the `.fmadapter`

### `export/constants.py`

```python
BASE_SIGNATURE = "9799725ff8e851184037110b422d891ad3b92ec1"
```

This SHA1 ties the adapter to a specific base model version. macOS checks this at load time — if the OS ships a different model version, the adapter won't load. **You must retrain when Apple updates the base model.**

Also defines paths to all assets (weight spec, template, MIL template, etc.).

## Dependencies

From `requirements.txt`:

| Package | Version | Purpose |
|---------|---------|---------|
| `tamm` | ~=0.1.0 | Apple's ML library (model architecture, preprocessing, packing) |
| `torch` | >=2.6 | Training framework |
| `coremltools` | ==8.3.0 | Draft model export to CoreML format |
| `sentencepiece` | latest | Tokenizer |
| `tqdm` | latest | Progress bars |
| `pydantic` | latest | Config validation |
| `notebook` | latest | Jupyter support (unused for CLI training) |

## Assets Detail

| File | Size | Contents |
|------|------|----------|
| `base-model.pt` | 12.0 GB | Full 3B model: frozen weights + LoRA adapter layers (initialized to zero) |
| `draft-model.pt` | 186 MB | Pre-trained draft model (starting point for distillation) |
| `draft.mil` | 7.7 MB | CoreML MIL template — defines the draft model graph, weights get swapped in during export |
| `tokenizer.model` | 2.6 MB | SentencePiece BPE tokenizer, works standalone |
| `weights_template.bin` | 24 MB | Binary layout template for adapter weight export |
| `weights_spec.json` | — | Maps adapter layer names → positions in the binary template |

## End-to-End Flow

```
1. Prepare JSONL training data
   (message arrays: system + user + assistant)
        │
        ▼
2. train_adapter.py
   Loads base-model.pt → freezes base → trains adapter layers
   Saves adapter-epoch{N}.pt checkpoints (~160 MB each)
        │
        ▼
3. generate.py (local eval)
   Loads base-model.pt + adapter checkpoint
   Runs inference on eval prompts, compare outputs
   Pick best checkpoint by eval loss + qualitative review
        │
        ▼
4. train_draft_model.py (optional)
   Loads base + best adapter (teacher, frozen)
   Trains draft model (student) via knowledge distillation
   Saves draft-model-final.pt
        │
        ▼
5. export_fmadapter.py
   Converts adapter checkpoint → fp16 binary blob
   Converts draft model → CoreML 4-bit palettized
   Packages as .fmadapter with metadata
        │
        ▼
6. Deploy on macOS
   Drop .fmadapter into app bundle or load via FoundationModels API
   Base model signature must match current macOS version
```
