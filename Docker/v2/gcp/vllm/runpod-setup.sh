#!/bin/bash
# RunPod vLLM 초기 설정 스크립트
# GPU: A40 (48GB) 이상 권장 (L4/RTX 4090 24GB도 가능)
# 모델: EXAONE-3.5-7.8B-Instruct (BF16 ~16GB VRAM)
# 소요: ~15분 (vLLM 설치 + 모델 다운로드, 모델 캐시 있으면 ~5분)
#
# [주의사항]
# - Pod 재시작 시 pip 패키지 초기화됨 → 매번 vLLM 재설치 필요
# - /workspace 경로만 Pod 재시작 후에도 유지됨
# - HF_HOME을 /workspace 하위로 설정해야 모델 캐시 보존
# - --revision 필수: 없으면 transformers v5 호환 버전 로드 → vLLM 0.15.1 크래시
set -euo pipefail

MODEL="LGAI-EXAONE/EXAONE-3.5-7.8B-Instruct"
REVISION="0ff6b5ec7c13b049b253a16a889aa269e6b79a94"
PORT=8010
API_KEY="dojangkok-vllm-key"

# /workspace 하위에 캐시 → Pod 재시작 후에도 모델 유지
export HF_HOME=/workspace/hf-cache

echo "=== [1/3] vLLM 설치 ==="
pip install vllm==0.15.1

echo "=== [2/3] 모델 다운로드 ($MODEL) ==="
huggingface-cli download "$MODEL" --revision "$REVISION"

echo "=== [3/3] vLLM 서버 시작 (port=$PORT) ==="
python3 -m vllm.entrypoints.openai.api_server \
  --host 0.0.0.0 \
  --port "$PORT" \
  --model "$MODEL" \
  --revision "$REVISION" \
  --trust-remote-code \
  --enforce-eager \
  --gpu-memory-utilization 0.90 \
  --max-num-seqs 128 \
  --max-model-len 32768 \
  --api-key "$API_KEY"
