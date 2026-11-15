#!/usr/bin/env bash
# ComfyUI startup for Koyeb: downloads models on first boot, then launches
# the server on port 8188. MODELS_DIR defaults to /data/models on the
# instance's local disk (no volume needed) — NOTE: Koyeb local disk is
# ephemeral, models re-download on redeploy/instance rescheduling.
set -uo pipefail

# Load the CUDA 13 forward-compat driver libs (host driver is CUDA 12.4-class)
if [ -d /usr/local/cuda-13.0/compat ]; then
  export LD_LIBRARY_PATH="/usr/local/cuda-13.0/compat:${LD_LIBRARY_PATH:-}"
fi

# --- Cloudflare tunnel: direct public URL that bypasses Koyeb's proxy ---
# Two modes:
#   1) NAMED tunnel (sustained URL — preferred): set the TUNNEL_TOKEN secret
#      in Koyeb. The tunnel + public hostname are configured once in the
#      Cloudflare Zero Trust dashboard (Networks -> Tunnels), and this
#      instance reconnects to that SAME url on every boot. Nothing else to do.
#   2) QUICK tunnel (fallback when TUNNEL_TOKEN is unset): random
#      https://<random>.trycloudflare.com URL per boot, printed below.
if [ -n "${TUNNEL_TOKEN:-}" ]; then
  echo "starting NAMED cloudflare tunnel (sustained URL from dashboard config)"
  cloudflared tunnel --no-autoupdate run --token "$TUNNEL_TOKEN" \
    > /tmp/cloudflared.log 2>&1 &
  TUNNEL_URL="named tunnel (see Cloudflare dashboard hostname)"
else
  echo "TUNNEL_TOKEN not set - falling back to quick tunnel (random URL per boot)"
  cloudflared tunnel --url http://localhost:8188 --no-autoupdate \
    > /tmp/cloudflared.log 2>&1 &
  TUNNEL_URL=""
  for i in $(seq 1 30); do
    TUNNEL_URL=$(grep -o "https://[a-z0-9-]*\.trycloudflare\.com" /tmp/cloudflared.log | head -1)
    [ -n "$TUNNEL_URL" ] && break
    sleep 1
  done
fi
echo "=================================================="
echo "  CLOUDFLARE TUNNEL: ${TUNNEL_URL:-NOT READY - check /tmp/cloudflared.log}"
echo "=================================================="

MODELS_DIR="${MODELS_DIR:-/data/models}"
mkdir -p "$MODELS_DIR"
case "$TUNNEL_URL" in https://*) echo "$TUNNEL_URL" > "$MODELS_DIR/tunnel_url.txt" ;; esac

# url|subfolder|filename
MODELS="
https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_fl2va_pruned_bf16.safetensors|diffusion_models|minimax_h3_fl2va_pruned_bf16.safetensors
https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/diffusion_models/minimax_h3_ref2va_pruned_bf16.safetensors|diffusion_models|minimax_h3_ref2va_pruned_bf16.safetensors
https://huggingface.co/Comfy-Org/MiniMax-H3-Image/resolve/main/diffusion_models/minimax_h3_image_pruned_bf16.safetensors|diffusion_models|minimax_h3_image_pruned_bf16.safetensors
https://huggingface.co/Comfy-Org/MiniMax-Music-3/resolve/main/diffusion_models/minimax_music3_dit_fp32.safetensors|diffusion_models|minimax_music3_dit_fp32.safetensors
https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/text_encoders/qwen3vl_32b_minimax_h3_bf16.safetensors|text_encoders|qwen3vl_32b_minimax_h3_bf16.safetensors
https://huggingface.co/Comfy-Org/MiniMax-H3-Image/resolve/main/text_encoders/qwen3.5_9b_w4a8_gptq.safetensors|text_encoders|qwen3.5_9b_w4a8_gptq.safetensors
https://huggingface.co/Comfy-Org/MiniMax-Music-3/resolve/main/text_encoders/minimax_music3_text_encoder_pruned_bf16.safetensors|text_encoders|minimax_music3_text_encoder_pruned_bf16.safetensors
https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_audio_vae_fp32.safetensors|vae|minimax_h3_audio_vae_fp32.safetensors
https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main/vae/minimax_h3_video_vae_fp16.safetensors|vae|minimax_h3_video_vae_fp16.safetensors
https://huggingface.co/Comfy-Org/MiniMax-H3-Image/resolve/main/vae/minimax_h3_image_vae_fp16.safetensors|vae|minimax_h3_image_vae_fp16.safetensors
https://huggingface.co/Comfy-Org/MiniMax-Music-3/resolve/main/vae/minimax_music3_dav.safetensors|vae|minimax_music3_dav.safetensors
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
  for repo in mello mello2 community speedloras; do
    dir="$MODELS_DIR/loras/public/$repo"
    if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
      echo "downloading dataset massshare/$repo -> $dir"
      hf download "massshare/$repo" --repo-type dataset \
        --local-dir "$dir" --token "$HF_TOKEN" || echo "dataset $repo failed"
    else
      echo "skip (exists): $dir"
    fi
  done
else
  echo "HF_TOKEN not set - skipping mello/mello2/community/speedloras LoRA datasets"
fi

echo "model dir ready, starting ComfyUI..."
exec python /app/ComfyUI/main.py --listen 0.0.0.0 --port 8188
