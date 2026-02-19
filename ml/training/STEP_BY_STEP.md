# STEP BY STEP — RUNPOD TRAINING

## IN (LOCAL)
- `train.jsonl` + `eval.jsonl`
- `adapter_training_toolkit_v26_0_0/` (2.13 GB)

## 1. LAUNCH POD

- RunPod Console > Pods > Deploy
- GPU: **H100 PCIe** (~$2/hr community, ~$2.40/hr secure)
- Template: **RunPod PyTorch** (`runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu`)
- Container disk: 20 GB, Volume disk: 50 GB
- Deploy On-Demand

## 2. UPLOAD

Grab SSH command from Pods > Connect > **SSH over exposed TCP**.

```bash

ssh e3ifcig7fz626q-644110bb@ssh.runpod.io -i ~/.ssh/id_ed25519

rsync -avz --progress \
  -e "ssh -p <PORT> -i ~/.ssh/id_ed25519" \
  ~/Developer/adapter_training_toolkit_v26_0_0/ \
  root@<POD_IP>:/workspace/toolkit/

scp -P <PORT> -i ~/.ssh/id_ed25519 \
  train.jsonl eval.jsonl \
  root@<POD_IP>:/workspace/toolkit/
```

## 3. TRAIN (SSH IN)

```bash
ssh root@<POD_IP> -p <PORT> -i ~/.ssh/id_ed25519
tmux new -s train
cd /workspace/toolkit
nvidia-smi  # sanity check — should show H100 80GB

pip install -r requirements.txt

# TRAIN ADAPTER (~1.5-2 hrs)
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

# DRAFT MODEL (optional, 2-4x inference speed)
python -m examples.train_draft_model \
  --checkpoint ./checkpoints/adapter-final.pt \
  --train-data train.jsonl \
  --eval-data eval.jsonl \
  --epochs 5 \
  --learning-rate 1e-3 \
  --batch-size 4 \
  --checkpoint-dir ./checkpoints/

# EXPORT
python -m export.export_fmadapter \
  --adapter-name ficino_music \
  --checkpoint ./checkpoints/adapter-best.pt \
  --draft-checkpoint ./checkpoints/draft-model-final.pt \
  --output-dir ./exports/
```

## 4. DOWNLOAD

```bash
scp -r -P <PORT> -i ~/.ssh/id_ed25519 \
  root@<POD_IP>:/workspace/toolkit/exports/ \
  ./exports/
```

## 5. TERMINATE

Terminate the pod (not just stop — stopped pods still bill storage). Do this AFTER you've downloaded everything.

## OUT
- `ficino_music.fmadapter` (~160 MB)

## GOTCHAS
- `bf16-mixed` NOT `bf16` (the latter produces garbage)
- Adapter name: letters/numbers/underscores only, NO hyphens
- Pick checkpoint with lowest eval loss, not necessarily the last one
- Use `tmux` — if SSH drops without it, training dies
- `/workspace` survives stop/restart but NOT terminate
- Total cost: ~$5-10 for the full run
