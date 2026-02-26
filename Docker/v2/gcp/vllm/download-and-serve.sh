#!/bin/bash
set -euo pipefail

MODEL="${VLLM_MODEL:-LGAI-EXAONE/EXAONE-3.5-2.4B-Instruct}"
REVISION="${VLLM_MODEL_REVISION:-e949c91dec92095908d34e6b560af77dd0c993f8}"
PORT="${VLLM_PORT:-8001}"

echo "=== Downloading model: $MODEL (revision: $REVISION) ==="
huggingface-cli download "$MODEL" --revision "$REVISION"

echo "=== Model download complete. Starting vLLM server ==="
exec python3 -m vllm.entrypoints.openai.api_server \
  --port "$PORT" \
  --model "$MODEL" \
  --revision "$REVISION" \
  --trust-remote-code \
  --enforce-eager \
  --gpu-memory-utilization 0.85 \
  --max-num-seqs 256 \
  --max-model-len 4096
