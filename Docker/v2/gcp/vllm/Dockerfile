FROM nvidia/cuda:13.0.0-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive

# Python 3.10 + 시스템 의존성
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      python3.10 python3.10-dev python3.10-venv python3-pip \
      build-essential git curl && \
    ln -sf /usr/bin/python3.10 /usr/bin/python3 && \
    pip3 install --no-cache-dir --upgrade pip && \
    rm -rf /var/lib/apt/lists/*

# vLLM 설치 (PyTorch + CUDA 종속성 포함)
RUN pip3 install --no-cache-dir vllm==0.15.1

# 모델 사전 다운로드 (콜드 스타트 최소화)
ENV HF_HOME=/model-cache
RUN huggingface-cli download \
      LGAI-EXAONE/EXAONE-3.5-2.4B-Instruct \
      --revision e949c91dec92095908d34e6b560af77dd0c993f8

# 다운로드 완료 후 오프라인 모드
ENV HF_HUB_OFFLINE=1

ENTRYPOINT ["python3", "-m", "vllm.entrypoints.openai.api_server"]
CMD ["--port", "8001", \
     "--model", "LGAI-EXAONE/EXAONE-3.5-2.4B-Instruct", \
     "--revision", "e949c91dec92095908d34e6b560af77dd0c993f8", \
     "--trust-remote-code", \
     "--enforce-eager", \
     "--gpu-memory-utilization", "0.85", \
     "--max-num-seqs", "256", \
     "--max-model-len", "4096"]
