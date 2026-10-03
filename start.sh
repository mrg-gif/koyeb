#!/usr/bin/env bash
# ComfyUI startup for Koyeb: downloads models on first boot, then launches
# the server on port 8000. MODELS_DIR defaults to /data/models on the
# instance's local disk (no volume needed) — NOTE: Koyeb local disk is
# ephemeral, models re-download on redeploy/instance rescheduling.
set -uo pipefail

MODELS_DIR="${MODELS_DIR:-/data/models}"
mkdir -p "$MODELS_DIR"

# url|subfolder|filename
MODELS="
https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_fl2va_pruned_fp8_scaled.safetensors|diffusion_models|minimax_h3_fl2va_pruned_fp8_scaled.safetensors
https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_ref2va_pruned_fp8_scaled.safetensors|diffusion_models|minimax_h3_ref2va_pruned_fp8_scaled.safetensors
https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors|text_encoders|qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors
https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_audio_vae_fp32.safetensors|vae|minimax_h3_audio_vae_fp32.safetensors
https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_video_vae_fp16.safetensors|vae|minimax_h3_video_vae_fp16.safetensors
https://raw.githubusercontent.com/madebyollin/taehv/62f7591f59dfbb4c3c02b7a621d180a9eeaba26c/safetensors/taeh3.safetensors|vae_approx|taeh3.safetensors
"

echo "$MODELS" | while IFS='|' read -r url sub name; do
  [ -z "$url" ] && continue
  dir="$MODELS_DIR/$sub"
  mkdir -p "$dir"
  dest="$dir/$name"
  if [ -f "$dest" ]; then
    echo "skip (complete): $dest"
    continue
  fi
  echo "downloading -> $dest"
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    aria2c -x 16 -s 16 -k 1M -c \
      --lowest-speed-limit=1M --file-allocation=none \
      --max-tries=0 --retry-wait=5 \
      --console-log-level=warn --summary-interval=15 \
      -d "$dir" -o "$name.part" "$url" && break
    echo "aria2c aborted (attempt $attempt/10), resuming..."
  done
  mv "$dir/$name.part" "$dest"
  echo "completed: $dest ($(stat -c%s "$dest") bytes)"
done

# --- LoRA collections from HF dataset repos (LFS-safe; needs HF_TOKEN secret) ---
if [ -n "${HF_TOKEN:-}" ]; then
  for repo in mello community; do
    dir="$MODELS_DIR/loras/$repo"
    if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
      echo "downloading dataset massshare/$repo -> $dir"
      huggingface-cli download "massshare/$repo" --repo-type dataset \
        --local-dir "$dir" --token "$HF_TOKEN" || echo "dataset $repo failed"
    else
      echo "skip (exists): $dir"
    fi
  done
else
  echo "HF_TOKEN not set - skipping mello/community LoRA datasets"
fi

echo "model dir ready, starting ComfyUI..."
exec python /app/ComfyUI/main.py --listen 0.0.0.0 --port 8000
