# ComfyUI on Koyeb (H100) — all-in-one image.
# Deploy: push this folder to a GitHub repo, then in Koyeb choose
# "GitHub" source with the Docker builder. Models download to
# /data/models on the instance's local disk on first boot (see start.sh)
# — no Volume needed, but local disk is ephemeral (see start.sh notes).

FROM pytorch/pytorch:2.13.0-cuda12.6-cudnn9-devel

# Ubuntu 24.04's pip refuses system-wide installs (PEP 668); allow them
ENV PIP_BREAK_SYSTEM_PACKAGES=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl wget aria2 unzip libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI

# Fix: websocket compression (permessage-deflate) can break behind
# HTTP proxies — browsers get disconnected, UI falls into a reconnect
# loop. Harmless if the proxy handles it fine, fatal if it doesn't.
RUN sed -i 's/web.WebSocketResponse()/web.WebSocketResponse(compress=False)/' /app/ComfyUI/server.py

RUN cd /app/ComfyUI && pip install --no-cache-dir -r requirements.txt

# --- custom nodes (baked in) ---
RUN cd /app/ComfyUI/custom_nodes && \
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-SolAttn_triton.git && \
    git clone --depth 1 https://github.com/xmarre/ComfyUI-Spectrum-MiniMax-H3.git && \
    git clone --depth 1 https://github.com/jlucasmcrell/ComfyUI-H3-Multishot.git && \
    git clone --depth 1 https://github.com/Larryvrh/ComfyUI-MiniMax-H3-Turbo && \
    git clone --depth 1 https://github.com/rgthree/rgthree-comfy && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-KJNodes && \
    git clone --depth 1 https://github.com/yolain/ComfyUI-Easy-Use && \
    git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite && \
    git clone --depth 1 https://github.com/GACLove/ComfyUI-VFI && \
    git clone --depth 1 https://github.com/olduvai-jp/ComfyUI-S3-IO && \
    git clone --depth 1 https://github.com/PlagueKind/ComfyUI-PlagueKind-Nodes && \
    git clone --depth 1 https://github.com/darksidewalker/ComfyUI-DaSiWa-Nodes && \
    git clone --depth 1 https://github.com/bbaudio-2025/Comfyui-MMH3-UltimateUpscale && \
    wget -q https://github.com/NikoDemon80/ComfyUI-H3-Motion-Context/archive/refs/tags/v0.3.1.zip && \
    unzip -q v0.3.1.zip && \
    mv ComfyUI-H3-Motion-Context-0.3.1 ComfyUI-H3-Motion-Context && \
    rm v0.3.1.zip
RUN for f in /app/ComfyUI/custom_nodes/*/requirements.txt; do \
      [ -e "$f" ] && pip install --no-cache-dir -r "$f"; done; true

# ComfyUI master sometimes expects a newer frontend than requirements.txt pins
RUN pip install --no-cache-dir "comfyui-frontend-package>=1.53.6" huggingface_hub

COPY extra_model_paths.yaml /app/ComfyUI/extra_model_paths.yaml
COPY manager_config.ini /app/ComfyUI/user/__manager/config.ini
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

EXPOSE 8000
CMD ["/app/start.sh"]
