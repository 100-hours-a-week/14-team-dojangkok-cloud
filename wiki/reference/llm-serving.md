## (M12‐1)LLM 서빙 조사 총정리

- 작성일: 2026-01-22
- 최종수정일: 2026-01-22
- 작성자: waf.jung(정승환)/클라우드

---

## 목적

- 2026-01-22에 수행한 **LLM 서빙(플랫폼/운영/비용/테스트)** 조사를 **이 문서 하나로** 확인할 수 있게 통합 정리한다.
- 도장콕의 **EXAONE 3.5 2.4B + LoRA 어댑터 2개(Multi-LoRA)** 서빙 보조 플랫폼 결정을 빠르게 돕는다.

## 작성 계기

- 도장콕은 임차인의 임대 계약 과정(계약 전·계약 중)을 돕기 위해, **쉬운 계약서(해설 + 리스크 검증)** 와 **집노트(답사 기록/매물 비교/체크리스트)** 같은 기능을 제공한다.
- 위 기능들은 실사용 흐름에서 `OCR → RAG → LLM 생성` 형태로 연결되며,  **피크 시간대에 LLM 기반 기능에 대한 동시 요청이 크게 증가**할 수 있다(예: 계약서 업로드/검토 요청 집중, 체크리스트 생성 요청 동시 폭증 등).
- 특히 “계약 직전” 상황에서는 응답 지연/실패가 곧 사용자 이탈과 신뢰 하락으로 이어질 수 있어, **비용 효율뿐 아니라 동시 요청 처리/운영 안정성**이 중요해졌다.
- 현재 GCP에서 운용 가능한 GPU 인스턴스가 제한적(1대)인 조건에서는 피크 트래픽에서 대기열이 길어질 수 있어, **오버플로우(외부 GPU) 활용 가능성**까지 포함해 옵션을 검토할 필요가 생겼다.
- 또한 베이스 모델(EXAONE 3.5 2.4B)에 업무별 LoRA 어댑터 2개를 붙여 **요청별 동적 선택(Multi-LoRA)** 이 필요하며, 플랫폼별 지원 방식/제약이 달라 비교가 필요했다.
- 그래서 2026-01-22에 플랫폼/가격/테스트를 분산 조사했고, 팀의 의사결정과 후속 구현(테스트/운영)을 빠르게 하기 위해 본 문서를 “총정리”로 작성한다.

## 범위

### 포함
- 플랫폼 비교(지원 기능, 과금, 설정 난이도, 운영 리스크)
- Multi-LoRA(요청별 어댑터 동적 선택) 지원 방식
- RunPod 테스트 결과(2026-01-22) 및 vLLM 이슈
- HuggingFace IE / GCP Vertex AI의 가격·특성 요약

### 제외
- 모델 학습(파인튜닝) 파이프라인 상세
- RAG/OCR 아키텍처 상세
- AI CD/CI 운영(별도 작업)


---

## 목차

1. [요구사항](#1-요구사항)
2. [AI팀 기존 테스트 결과 요약](#2-ai팀-기존-테스트-결과-요약)
3. [플랫폼 비교(핵심 표)](#3-플랫폼-비교핵심-표)
4. [가격 총정리](#4-가격-총정리)
5. [플랫폼별 상세](#5-플랫폼별-상세)
6. [RunPod 테스트 결과(2026-01-22)](#6-runpod-테스트-결과2026-01-22)
7. [GCP Vertex AI: Multi-LoRA/배포 옵션](#7-gcp-vertex-ai-multi-lora배포-옵션)
8. [HuggingFace IE: Quota/Scale to Zero](#8-huggingface-ie-quota-scale-to-zero)
9. [리스크/오픈 이슈](#9-리스크오픈-이슈)
10. [참고 자료](#10-참고-자료)
11. [동시 요청 대응: 운영 의견](#11-동시-요청-대응-운영-의견)

---

## 1) 요구사항

| 항목 | 내용 |
|------|------|
| 베이스 모델 | EXAONE 3.5 2.4B Instruct |
| HuggingFace | `LGAI-EXAONE/EXAONE-3.5-2.4B-Instruct` |
| LoRA 어댑터 | 2개 (팀 자체 개발) |
| 서빙 방식 | Multi-LoRA (요청 시 어댑터 동적 선택) |
| 우선순위 | 비용 효율 > 설정 간편성 > 엔터프라이즈 기능 |
> 어댑터에 대한 구체적인 요구사항은 AI 팀원분들 개발이 진행되면서 구체화될 예정

---

## 2) AI팀 기존 테스트 결과 요약

### 서비스 파이프라인

```
OCR → RAG → LLM 생성
```

- 라이프스타일 기반 체크리스트 생성
- OCR 통한 계약서 분석
- RAG 기반 법률 설명
- 질의응답 챗봇

### 7개 모델 비교 테스트 결과(발췌)

#### 정량평가 (KoBEST 5종)

| 모델 | BoolQ | COPA | SentiNeg | WiC | F1 |
|------|-------|------|----------|-----|-----|
| **Konan-LLM-OND** | **0.854** | - | - | - | - |
| **Kanana-1.5** | - | **0.775** | **0.894** | - | - |
| **EXAONE-3.5** | - | - | - | **0.509** | **0.482** |

#### 정성평가 (실무 테스트)

| 모델 | 총 지연(p50) | TTFT(p50) | 평균 출력토큰 | VRAM | 디코드 지연 |
|------|-------------|----------|------------|------|------------|
| **EXAONE-3.5-2.4B** | 44.92s | 3.40s | 769 | 7.9GB | **0.054s** |
| Midm-2.0 Mini | 37.51s | 4.10s | 375 | 7.9GB | - |
| HyperCLOVAX-1.5B | 204.33s | 1.84s | 3,542 | 4.8GB | - |

### 최종 선정: EXAONE-3.5-2.4B Instruct

- 상위권 응답 속도
- KoBEST + 실무 평가 균형
- 토큰당 디코드 지연 **0.054초** (가장 효율적)
- Colab T4에서 안정 운영

---

## 3) 플랫폼 비교(핵심 표)

> “지원 여부”는 2026-01-22 조사 당시 기준 요약이며, 실제 운영 전 최신 정책/제약 재확인이 필요하다.

### 3.1 LoRA/Multi-LoRA 지원 방식

| 플랫폼 | Multi-LoRA | LoRA 직접 업로드 | 비고 |
|--------|:----------:|:----------------:|------|
| **RunPod** | ✅ | ✅ | vLLM으로 자유 구성 |
| **FriendliAI** | ✅ | ✅ | EXAONE 공식 파트너(리포트 기준) |
| **Fireworks AI** | ✅ | ✅ | 어댑터 파일 업로드 |
| **Together AI** | ✅ | ✅ | Serverless Multi-LoRA |
| **Modal** | ✅ | ✅ | vLLM 직접 설정 |
| **GCP Vertex AI** | ✅ | ✅ | HuggingFace DLC 사용(Handler 필요) |
| **HuggingFace IE** | ✅ | ⚠️ | Custom Handler 필요 |
| **Replicate** | ⚠️ | ⚠️ | 커스텀 모델은 유휴 과금 이슈 |
| **AWS Bedrock** | ❌ | ❌ | LoRA 머지 후 전체 모델 임포트 필요 |

### 3.2 EXAONE 지원

| 플랫폼 | EXAONE 지원 | 방식 |
|--------|:-----------:|------|
| **FriendliAI** | ✅ | LG AI Research 공식/유일 파트너(리포트 기준) |
| **RunPod** | ✅ | 직접 지원(모델 페이지/서빙) |
| **Modal** | ⚠️ | vLLM으로 직접 배포 |
| **GCP Vertex AI** | ⚠️ | HuggingFace DLC로 커스텀 배포 |
| **HuggingFace IE** | ⚠️ | 모델 업로드 후 배포(Handler 필요 가능) |
| **Fireworks AI** | ❓ | 커스텀 모델 업로드(제약/승인 가능) |
| **Together AI** | ❓ | 커스텀 모델 업로드(승인 필요 가능) |
| **Replicate** | ❓ | 커스텀 모델 |
| **AWS Bedrock** | ❌ | 미지원 가능성 높음(지원 아키텍처 제한) |

### 3.3 비용 비교(2.4B 모델 기준, 2026-01)

| 플랫폼 | 과금 방식 | 예상 비용 | 유휴 시 비용 |
|--------|----------|----------|-------------|
| **Fireworks AI** | 토큰당 | $0.10/1M (≤4B) | **$0** |
| **Together AI** | 토큰당 | ~$0.10/1M | **$0** |
| **RunPod Serverless** | 초당 | ~$0.00016/sec (추정) | **$0** |
| **Modal** | 초당 | T4 $0.59/hr | **$0** |
| **FriendliAI** | 토큰당/초당 | $0.10/1M (8B) 등 | **$0** |
| **HuggingFace IE** | 시간당 | T4 $0.50/hr | 계속 과금(Scale to 0 가능) |
| **GCP Vertex AI** | 시간당 | T4 ~$0.40/hr | 계속 과금 |
| **Replicate** | 초당 | T4 $0.81/hr | **커스텀은 과금** |
| **AWS Bedrock** | Provisioned | 최소 1시간 커밋 | 커밋 기간 과금 |

### 3.4 설정 복잡도(체감)

| 플랫폼 | 난이도 | 필요 작업 |
|--------|:------:|----------|
| **FriendliAI** | ⭐ | 바로 사용 가능(모델/플랜 확인 필요) |
| **Fireworks AI** | ⭐ | 어댑터 업로드 중심(커스텀 베이스 제약 가능) |
| **Together AI** | ⭐ | 어댑터 업로드 중심(커스텀 베이스 승인 가능) |
| **Replicate** | ⭐⭐ | Cog 패키징 |
| **Modal** | ⭐⭐⭐ | Python + vLLM 설정 |
| **RunPod** | ⭐⭐⭐ | Docker + vLLM 설정 |
| **HuggingFace IE** | ⭐⭐⭐ | Custom Handler 작성 가능성 |
| **GCP Vertex AI** | ⭐⭐⭐⭐ | HF DLC + Custom Handler |
| **AWS Bedrock** | ⭐⭐⭐⭐⭐ | LoRA 머지 + 모델 임포트/IAM |

---

## 4) 가격 총정리

> 아래 가격은 2026-01-22 리포트에 기록된 값이다. (플랫폼 정책에 따라 변동 가능)

### 4.1 GPU 시간당 가격 비교

| GPU | RunPod | HuggingFace IE | GCP Vertex AI | Together AI | FriendliAI |
|-----|-------:|---------------:|--------------:|------------:|-----------:|
| **T4** | - | **$0.50** | **$0.40** | - | - |
| **L4** | - | $0.70-0.80 | ~$0.70 | - | - |
| **A10G** | - | $1.00 | - | - | - |
| **A40** | **$0.41** | - | - | - | - |
| **RTX 4090** | $0.44 | - | - | - | - |
| **L40S** | - | $1.80 | - | - | - |
| **A100 80GB** | $0.78 | $2.50 | $2.93 | $2.40-2.56 | $2.90 |
| **H100** | $1.47 | - | ~$10.00 | $3.36 | $3.90 |
| **H200** | - | $5.00 | - | $4.99 | $4.50 |

### 4.2 서버리스 토큰 가격 비교(입력+출력 평균)

| 모델 크기 | Together AI | Fireworks AI | FriendliAI |
|-----------|------------:|-------------:|-----------:|
| **~3B** | ~$0.10/1M | ~$0.10/1M | $0.002/sec |
| **7-8B** | $0.18-0.30/1M | ~$0.20/1M | $0.10/1M |
| **70B+** | $0.90/1M | ~$0.90/1M | $0.60-1.00/1M |

### 4.3 과금 방식 요약

| 플랫폼 | 과금 방식 | 유휴 시 | Scale to Zero |
|--------|----------|--------|:-------------:|
| **RunPod Pod** | 시간당 | 계속 과금 | ❌ |
| **RunPod Serverless** | 초당 | **$0** | ✅ |
| **HuggingFace IE** | 시간당(분 단위) | 계속 과금 | ✅(재시작 느림) |
| **GCP Vertex AI** | 시간당 | 계속 과금 | ⚠️(설정/운영 부담) |
| **Together AI** | 토큰당 | **$0** | ✅ |
| **Fireworks AI** | 토큰당 | **$0** | ✅ |
| **FriendliAI** | 토큰당/초당 | **$0** | ✅ |
| **AWS Bedrock** | Provisioned | 커밋 기간 과금 | ❌ |

### 4.4 EXAONE 2.4B + LoRA 2개: 월간 비용 추정(가정 기반)

> 가정: **일 1,000 요청, 평균 1,000 토큰** → 월 30M tokens

| 플랫폼 | 계산 방식 | 월 예상 비용 |
|--------|----------|------------:|
| **Together AI(서버리스)** | 30M tokens × $0.10/1M | **~$3** |
| **Fireworks AI(서버리스)** | 30M tokens × $0.10/1M | **~$3** |
| **RunPod Serverless** | ~30hr × $0.16/hr (추정) | **~$5** |
| **RunPod Pod(24/7)** | 720hr × $0.41 | ~$295 |
| **HuggingFace IE(24/7)** | 720hr × $0.50 | ~$360 |
| **GCP Compute Engine GPU VM(24/7)** | g2-standard-4 + T4 ≈ $219/월 (on-demand, 내부 추정) | ~$219 |
| **GCP Vertex AI(24/7)** | 720hr × $0.40 | ~$288 |

> ⚠️ Together/Fireworks의 토큰 과금 계산은 “**EXAONE 커스텀 모델을 해당 조건으로 서빙 가능**”하다는 전제가 필요하다.

### 4.5 Self-Hosted GPU VM(Compute Engine/EC2) 월 비용 비교 (24/7 vs 12/7 + Spot)

> 가정: 월 30일 기준, 단순 계산(디스크/네트워크/약정/세금 등 미반영)
> - 24/7: 24h × 30d = 720h
> - 12/7: 12h × 30d = 360h (예: 피크 시간대만 가동 후 종료)

| 클라우드 | VM 예시 | GPU | On-demand(24/7) | On-demand(12/7) | Spot(24/7) | Spot(12/7) | 비고 |
|---|---|---:|---:|---:|---:|---:|---|
| **GCP Compute Engine** | g2-standard-4 | T4 | ~$219 | ~$110 | ~$65 | ~$33 | Spot은 선점/중단 가능 |
| **GCP Compute Engine** | (추정) | L4 | ~$350 | ~$175 | ~$108 | ~$54 | L4 on-demand는 내부 추정 |
| **AWS EC2** | g4dn.xlarge | T4 | ~$380 | ~$190 | ~$150 | ~$75 | Spot은 선점/중단 가능 |

#### Spot(선점형) 프로비저닝 시 운영적으로 달라지는 점 (AWS/GCP 공통)

- 인스턴스가 공급자 사정으로 회수될 수 있어, **요청 실패/연결 끊김/콜드 스타트 증가**가 발생할 수 있다.
- LLM 서빙은 모델 로딩이 무거워 “재시작 비용”이 커질 수 있으므로, Spot을 24/7 메인으로 쓰기보다 **버스트/오버플로우**에 붙이는 전략이 안전하다.
- 권장 대응(요약):
  - **큐/백프레셔**로 과부하 시 요청을 적절히 대기/차단
  - **재시도/멱등 처리**(요청 ID) + 타임아웃
  - 모델/LoRA 아티팩트는 **외부 스토리지**에 두고 재기동 시 빠르게 복구
  - **온디맨드 1대 + Spot N대**(버스트) 조합 + 헬스체크 기반 라우팅

### 4.6 외부 서비스(전용 GPU/관리형) 월 비용 비교 (24/7 vs 12/7)

> 가정: 월 30일 기준, 단순 계산(부가 요금/할인/정책 변화 미반영)

| 플랫폼/서비스 | GPU(예시) | 단가(시간당) | 월 비용(24/7) | 월 비용(12/7) | 비고 |
|---|---:|---:|---:|---:|---|
| **GCP Vertex AI** | T4 | $0.40/hr | ~$288 | ~$144 | 관리형, 유휴 과금 |
| **RunPod Pod** | A40 | $0.41/hr | ~$295 | ~$148 | GPU 스펙 차이 유의 |
| **RunPod Pod** | RTX 4090 | $0.44/hr | ~$317 | ~$158 | GPU 스펙 차이 유의 |
| **HuggingFace IE** | T4 | $0.50/hr | ~$360 | ~$180 | Scale to Zero 가능(재시작 느림) |
| **HuggingFace IE** | L4 | $0.70-0.80/hr | ~$504-576 | ~$252-288 | 가격 범위(리포트 기준) |
| **Modal** | T4 | $0.59/hr | ~$425 | ~$212 | 초당 과금, 유휴 $0(미실행 시) |
| **Replicate** | T4 | $0.81/hr | ~$583 | ~$292 | 커스텀 모델은 유휴 과금 이슈(리포트 기준) |

---

## 5) 플랫폼별 상세

### 5.1 RunPod

**장점**
- EXAONE 직접 지원 확인(리포트 기준)
- vLLM Multi-LoRA로 어댑터 2개 동시 서빙 가능
- Serverless 사용 시 유휴 비용 $0
- 인프라 제어권(커스텀 설정/관측/튜닝) 확보

**단점/주의**
- Docker/vLLM 설정 필요
- 직접 모니터링/스케일링 설계 필요
- 실험에서 vLLM v1 엔진 초기화 실패 이슈 관측(아래 6장)

**예시: vLLM(OpenAI-compatible) 서버 실행**
```bash
python -m vllm.entrypoints.openai.api_server \
  --model LGAI-EXAONE/EXAONE-3.5-2.4B-Instruct \
  --host 0.0.0.0 \
  --port 8000 \
  --trust-remote-code \
  --enable-lora \
  --lora-modules adapter1=/adapters/v1 adapter2=/adapters/v2
```

---

### 5.2 FriendliAI 

**장점**
- EXAONE 공식/유일 API 제공자(리포트 기준)
- 서버리스 + Dedicated 모두 제공
- Multi-LoRA 지원

**단점/확인 필요**
- EXAONE 3.5 2.4B 제공/조건은 별도 확인 필요(리포트에는 4.0 위주 언급)
- 소형 모델 가격 경쟁력은 Together/Fireworks 대비 낮을 수 있음

**가격 상세(리포트 발췌, 2026-01 기준)**

서버리스 추론:
| 모델 | 입력 | 출력 |
|------|------|------|
| K-EXAONE-236B-A23B | 무료(1/28까지, 리포트 기준) | 무료 |
| Llama-3.1-8B-Instruct | $0.10/1M | $0.10/1M |
| Llama-3.3-70B-Instruct | $0.60/1M | $0.60/1M |
| EXAONE-4.0.1-32B | $0.60/1M | $1.00/1M |
| 소형 모델(초당) | $0.002/sec | - |

Dedicated Endpoint:
| GPU | 가격/시간 |
|-----|----------|
| A100 80GB | $2.90/hr |
| H100 80GB | $3.90/hr |
| H200 141GB | $4.50/hr |
| B200 192GB | $8.90/hr |

---

### 5.3 GCP Vertex AI

**장점**
- 엔터프라이즈급 운영(권한/IAM, VPC, 로깅, 거버넌스) 용이
- HuggingFace DLC + Custom Handler로 Multi-LoRA 가능

**단점**
- Custom Handler 작성 필요(특히 EXAONE + LoRA)
- 시간당 과금(유휴 비용)
- 설정/운영 복잡도 높음

> Vertex AI의 LoRA/배포 옵션은 7장에 상세 정리.

---

### 5.4 Fireworks AI

**장점**
- LoRA 서빙 우수(리포트 기준: 최대 100개 어댑터 동시 서빙, 베이스 모델 가격으로)
- 서버리스 토큰 기반 과금(유휴 $0)
- 배치 추론/캐시 입력 할인 정책 존재(리포트 기준)

**단점/확인 필요**
- 커스텀 베이스 모델은 서버리스 미지원일 수 있어 Dedicated 필요 가능
- EXAONE 기본 미지원(커스텀 업로드 승인 필요 가능)

**가격 상세(리포트 발췌, 2026-01 기준)**

서버리스 추론(모델 크기별):
| 모델 크기 | 입력/출력 |
|-----------|----------|
| ≤4B | $0.10/1M |
| 4B-16B | $0.20/1M |
| >16B | $0.90/1M |
| MoE 0-56B | $0.50/1M |
| MoE 56-176B | $1.20/1M |

파인튜닝:
| 모델 크기 | SFT | DPO |
|-----------|-----|-----|
| ≤16B | $0.50/1M | $1.00/1M |
| 16B-80B | $3.00/1M | $6.00/1M |

Dedicated(온디맨드):
| GPU | 가격/시간 |
|-----|----------|
| A100 80GB | $2.90/hr |
| H100 80GB | $4.00/hr |
| H200 141GB | $6.00/hr |

---

### 5.5 Together AI

**장점**
- Serverless Multi-LoRA 지원(유휴 $0)
- 토큰 기반 과금
- HuggingFace 모델 파인튜닝 지원(리포트 기준)
- OpenAI 호환 API

**단점/확인 필요**
- EXAONE 기본 미지원(커스텀 업로드 필요, 승인 기간 불확실)
- Dedicated 필요 시 비용 상승 가능

**가격 상세(리포트 발췌, 2026-01 기준)**

서버리스 추론:
| 모델 크기 | 입력 | 출력 |
|-----------|------|------|
| ~3B(2.4B 추정) | ~$0.10/1M | ~$0.10/1M |
| 7-8B | $0.18-0.30/1M | $0.18-0.30/1M |
| 70B+ | $0.90/1M | $0.90/1M |

파인튜닝(≤16B):
| 방식 | 비용 |
|------|------|
| LoRA | $0.48/1M tokens |
| Full Fine-tune | $0.54/1M tokens |
| DPO(LoRA) | $1.44/1M tokens |

Dedicated Endpoint:
| GPU | 가격 |
|-----|------|
| A100 80GB | $2.40~$2.56/hr |
| H100 | $3.36/hr |
| H200 | $4.99/hr |

도장콕 시나리오 비용 추정(2.4B + LoRA 2개, 리포트 기준):
| 시나리오 | 일 요청 | 평균 토큰 | 월 비용 |
|----------|---------|----------|---------|
| 테스트 | 100 | 1,000 | ~$0.30 |
| 소규모 | 1,000 | 1,000 | ~$3 |
| 중규모 | 10,000 | 1,000 | ~$30 |
| 대규모 | 100,000 | 1,000 | ~$300 |

테스트 방법(리포트 발췌):
- 지원 모델로 빠른 테스트(예: Qwen2.5)
- LoRA 어댑터 업로드 후 요청에 어댑터 지정
- 커스텀 모델(EXAONE) 업로드는 승인 대기(수일~수주 가능), Dedicated 배포가 필요할 수 있음

---

### 5.6 Modal Labs

**장점**
- vLLM 네이티브 지원(리포트 기준)
- 초당 과금 + 유휴 $0
- GPU 빠른 스핀업(리포트 기준)
- 월 $30 무료 크레딧(리포트 기준)

**단점**
- vLLM 구성/운영을 직접 해야 함
- Multi-LoRA 운영 구현은 직접 설계 필요

GPU 가격(리포트 발췌, 2026-01 기준):
| GPU | 초당 | 시간당 |
|-----|------|--------|
| T4 | $0.000164 | $0.59/hr |
| L4 | $0.000222 | $0.80/hr |
| A10 | $0.000306 | $1.10/hr |
| L40S | $0.000542 | $1.95/hr |
| A100 40GB | $0.000583 | $2.10/hr |
| A100 80GB | $0.000694 | $2.50/hr |
| H100 | $0.001097 | $3.95/hr |
| H200 | $0.001261 | $4.54/hr |

---

### 5.7 Replicate

**장점**
- API-first 플랫폼, 배포 흐름이 단순(리포트 기준)
- 공개 모델은 유휴 비용 무료(리포트 기준)

**단점**
- 프라이빗/커스텀 모델은 유휴 시에도 과금(리포트 기준)
- EXAONE 기본 미지원

GPU 가격(리포트 발췌, 2026-01 기준):
| GPU | 초당 | 시간당 |
|-----|------|--------|
| T4 | $0.000225 | $0.81/hr |
| L40S | $0.000975 | $3.51/hr |
| A100 80GB | $0.001400 | $5.04/hr |
| H100 | $0.001525 | $5.49/hr |

---

### 5.8 HuggingFace Inference Endpoints

> 가격/Quota/Scale to Zero는 8장에 상세 정리.

**장점**
- HuggingFace Hub 기반 배포(클릭 중심)
- Scale to Zero 제공(유휴 비용 절감 가능)
- 다양한 GPU 옵션(AWS/GCP)

**단점**
- 기본은 시간당 과금(분 단위 청구)
- Multi-LoRA/EXAONE은 Custom Handler 필요 가능
- Quota 제약

---

### 5.9 AWS Bedrock (비추천)

**비추천 사유(핵심)**
- LoRA 어댑터 직접 서빙 미지원
- 머지 후 전체 모델 임포트 필요 → 어댑터 2개면 모델 2개 배포 구조
- Provisioned Throughput 중심(비용/운영 부담)

---

## 6) RunPod 테스트 결과(2026-01-22)

### 환경

| 항목 | 값 |
|------|-----|
| GPU | A40 (48GB VRAM) |
| vCPU | 9 |
| Memory | 50GB |
| Container Disk | 8GB |
| Volume | 40GB |
| 리전 | CA-MTL-1 |
| 타입 | On-Demand |
| 비용 | $0.41/hr |
| 모델 | EXAONE-3.5-2.4B-Instruct |

### 배포 과정

#### 1차 시도: vLLM 템플릿

| 항목 | 결과 |
|------|------|
| 템플릿 | vLLM 기본 템플릿(Llama 3.1 8B 설정) |
| 결과 | ❌ 실패 |
| 원인 | Llama gated 모델 접근 실패 → 컨테이너 무한 재시작 |
| SSH 접속 | 불안정(자주 끊김) |

#### 2차 시도: PyTorch 템플릿

| 항목 | 결과 |
|------|------|
| 템플릿 | PyTorch Environment (JupyterLab 포함) |
| vLLM 설치 | ✅ `pip install vllm huggingface_hub` |
| HuggingFace 로그인 | ✅ 성공 |
| 모델 로딩 | ❌ 실패 : 로딩하다가 인스턴스 종료 |

### 발생 이슈 요약

1) **SSH 연결 불안정**
- 원인: 컨테이너 크래시(1차 시도) 영향
- 대응: Web Terminal 또는 “깨끗한 템플릿” 사용 권장

2) **vLLM 템플릿 주의사항**
- Start Command에 모델이 하드코딩되어 있을 수 있음
- gated 모델 사용 시 HF 토큰 필요
- EXAONE 사용 시 `--trust-remote-code` 필요

3) **pip 의존성 경고**
- `pyzmq` 충돌(notebook vs vllm) 경고
- 리포트 기준: vLLM 동작에 치명적 문제는 아니었음

4) **vLLM v1 엔진 초기화 실패(미해결)**
- 증상: `RuntimeError: Engine core initialization failed`
- 추정 원인: vLLM 최신 버전(v1 엔진)과 EXAONE 호환 문제
- 시도 옵션: `--enforce-eager`, `--disable-custom-all-reduce` (해결 못함)

### 권장 세팅 순서(리포트 기준)

```bash
# 1) PyTorch 템플릿으로 Pod 생성
# 2) vLLM 설치
pip install vllm huggingface_hub

# 3) HuggingFace 로그인
huggingface-cli login

# 4) vLLM 서버 실행(EXAONE)
python -m vllm.entrypoints.openai.api_server \
  --model LGAI-EXAONE/EXAONE-3.5-2.4B-Instruct \
  --host 0.0.0.0 \
  --port 8000 \
  --dtype bfloat16 \
  --trust-remote-code
```

### 성능 측정(미완)

| 지표 | 값 | 비고 |
|------|-----|------|
| Cold Start | - | |
| TTFT | - | |
| Tokens/sec | - | |
| 총 응답시간 | - | |
| VRAM 사용량 | - | |

---

## 7) GCP Vertex AI: Multi-LoRA/배포 옵션

### 7.1 LoRA 지원 방식(요약)

1) **HuggingFace DLC + Custom Handler**
- 베이스 모델 1개 배포 + 여러 LoRA 어댑터 로딩
- 요청 시 어댑터 동적 선택
- 장점: 단일 베이스 배포로 비용 절감 가능
- 단점: Handler 코드 작성/운영 필요

2) **Hex-LLM**
- TPU 기반 서빙(리포트 기준), Dynamic LoRA Loading 옵션 존재
- 단, 공식 지원 모델이 Llama 계열 중심이며 EXAONE 호환은 미확인

3) **Model Garden 통합 파인튜닝**
- Vertex AI Custom Training Job로 LoRA/QLoRA 수행 후 Endpoint 배포
- 지원 모델: Gemma/Gemma2, Llama2/3 등(Model Garden 범위)

### 7.2 LoRA vs QLoRA 비교(리포트 발췌)

| 항목 | LoRA | QLoRA |
|------|------|-------|
| GPU 메모리 | 높음 | **75% 절감** |
| 속도 | **66% 빠름** | 느림 |
| 비용 | **40% 저렴** | 높음 |
| 정확도 | 유사 | 유사 |

#### GPU별 배치 사이즈 예시(OpenLLaMA-7B 기준, 리포트 발췌)

| GPU | LoRA | QLoRA |
|-----|------|-------|
| A100 40GB | 2 | **24** |
| L4 | OOM ❌ | **12** |
| V100 | OOM ❌ | **8** |

### 7.3 Vertex AI Prediction GPU 가격(리포트 발췌)

| GPU | 시간당 가격 | VRAM |
|-----|-----------|------|
| **T4** | **$0.40** | 16GB |
| L4 | ~$0.70(추정) | 24GB |
| P100 | $1.84 | 16GB |
| **A100** | **$2.93** | 40/80GB |
| H100 | ~$10(추정) | 80GB |

> 참고: Spot 인스턴스 사용 시 60-91% 할인 가능(리포트 메모).

### 7.4 EXAONE 3.5 2.4B 배포 시나리오(리포트 기준)

#### 옵션 A: HuggingFace DLC + Custom Handler
- Container: HF DLC(PyTorch)
- GPU: T4 또는 L4
- Handler: EXAONE + LoRA 로딩 로직 구현

#### 옵션 B: Hex-LLM(TPU 기반)
- LoRA Dynamic Loading 옵션은 있으나, EXAONE 호환 미확인

### 7.5 다른 플랫폼과 비교(리포트 발췌)

| 항목 | Vertex AI | RunPod | HuggingFace IE |
|------|-----------|--------|----------------|
| Multi-LoRA | ✅(Custom Handler) | ✅(vLLM) | ✅(TGI/Handler) |
| 설정 난이도 | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ |
| EXAONE 지원 | ⚠️ Custom 필요 | ✅(리포트 기준) | ⚠️ Custom 필요 |
| T4 가격/hr | $0.40 | - | $0.50 |
| 유휴 시 과금 | ✅ 계속 | ✅ 계속(단, Serverless는 $0) | ✅(Scale to 0 가능) |
| GCP 통합 | ✅ | ❌ | ❌ |

### 7.6 결론(요약)

- GCP 통합(권한/네트워크/로깅/감사)이 최우선이면 Vertex AI 고려 가치가 높다.
- 다만 EXAONE + Multi-LoRA는 Handler 중심으로 복잡도가 높아, “빠른 PoC” 목적에는 RunPod/Modal이 더 유리할 수 있다.

---

## 8) HuggingFace IE: Quota/Scale to Zero

### 8.1 과금 방식

| 항목 | 내용 |
|------|------|
| 과금 단위 | 시간당(분 단위 청구) |
| 유휴 시 | 계속 과금(Scale to Zero 설정 시 유휴 비용 절감 가능) |
| 청구 주기 | 월별 |

### 8.2 GPU 라인업(AWS, 리포트 발췌)

| GPU | 개수 | VRAM | 시간당 가격 |
|-----|:----:|-----:|----------:|
| **T4** | x1 | 14GB | **$0.50** |
| **L4** | x1 | 24GB | **$0.80** |
| **A10G** | x1 | 24GB | **$1.00** |
| **L40S** | x1 | 48GB | **$1.80** |
| **A100** | x1 | 80GB | **$2.50** |
| **H200** | x1 | 141GB | **$5.00** |

### 8.3 GPU 라인업(GCP, 리포트 발췌)

| GPU | 개수 | VRAM | 시간당 가격 |
|-----|:----:|-----:|----------:|
| **T4** | x1 | 16GB | **$0.50** |
| **L4** | x1 | 24GB | **$0.70** |
| **A100** | x1 | 80GB | **$3.60** |
| **H100** | x1 | 80GB | **$10.00** |

### 8.4 EXAONE 3.5 2.4B 권장 인스턴스(리포트 기준)

| 옵션 | GPU | VRAM | 가격 | 비고 |
|------|-----|------|------|------|
| **최저가** | T4 x1 | 14-16GB | $0.50/hr | 충분(모델 ~5GB 가정) |
| **권장** | L4 x1 | 24GB | $0.70-0.80/hr | 여유 있음 |

### 8.5 Quota/Scale to Zero

**Quota**
- Free/PRO/Enterprise 플랜에 따라 GPU 할당량 차이
- UI에서 “Quotas Used”로 확인(리포트 기준)

**Scale to Zero**
- 유휴 일정 시간 후 0으로 스케일
- 스케일 0 상태는 과금 없음(리포트 기준)
- 단, 재시작 시 모델 로딩 시간(수 분) 고려 필요

### 8.6 구독 플랜 비교(리포트 발췌)

| 플랜 | 가격 | 주요 혜택 |
|------|------|----------|
| Free | $0 | 기본 기능 |
| PRO | $9/월 | ZeroGPU quota, 우선 GPU 접근, 100GB 스토리지(리포트 기준) |
| Team | $20/user/월 | SSO, 중앙 청구 |
| Enterprise | $50+/user/월 | 24/7 SLA, 전담 지원 |

### 8.7 RunPod vs HuggingFace IE 비교(리포트 발췌)

| 항목 | RunPod (A40) | HuggingFace (T4) | HuggingFace (L4) |
|------|-------------|------------------|------------------|
| VRAM | 48GB | 14-16GB | 24GB |
| 시간당 | $0.41 | $0.50 | $0.70-0.80 |
| 과금 방식 | 시간당 | 시간당(분 단위) | 시간당(분 단위) |
| Scale to Zero | ❌(Serverless 별도) | ✅ | ✅ |
| 설정 난이도 | 높음 | 낮음 | 낮음 |
| Custom Code | 자유 | 제한적 | 제한적 |

### 8.8 EXAONE 테스트 메모(리포트 기준)

- 시작 인스턴스: **T4 x1($0.50/hr)** 권장
- `TRUST_REMOTE_CODE=true` 환경변수 필요
- Container Type: **Text Generation Inference**

---

## 9) 리스크/오픈 이슈

### 기술 리스크
- vLLM/EXAONE 조합 호환성(현재 RunPod에서 엔진 초기화 실패 이슈 관측)
- `trust_remote_code` 필요 환경에서의 보안/정책(플랫폼별 제약 가능)
- Multi-LoRA 운영(어댑터 버전 관리/롤백/호환성) 체계 필요

### 제품/운영 리스크
- EXAONE 라이선스(상업 사용/배포/제3자 플랫폼 업로드) 조건 확정 필요
- 서버리스 플랫폼의 커스텀 모델 승인/제약 변경 가능성(리드타임 리스크)

---

## 10) 참고 자료

### 플랫폼
- RunPod EXAONE Deep: https://www.runpod.io/models/lgai-exaone-exaone-deep-2-4b
- vLLM Multi-LoRA: https://docs.vllm.ai/en/latest/models/lora.html
- Vertex AI Multi-LoRA(예시 글): https://medium.com/google-cloud/open-models-on-vertex-ai-with-hugging-face-serving-multiple-lora-adapters-on-vertex-ai-e3ceae7b717c
- AWS Bedrock Custom Model Import: https://docs.aws.amazon.com/bedrock/latest/userguide/model-customization-import-model.html
- FriendliAI LG AI Research 파트너십: https://friendli.ai/blog/lg-ai-research-partnership-exaone-4.0

### 모델
- EXAONE 3.5 2.4B(Instruct): https://huggingface.co/LGAI-EXAONE/EXAONE-3.5-2.4B-Instruct
- EXAONE GitHub: https://github.com/LG-AI-EXAONE/EXAONE-3.5
- Kanana(Kakao): https://huggingface.co/kakaocorp
- SOLAR(Upstage): https://huggingface.co/upstage/SOLAR-10.7B-Instruct-v1.0
- Qwen2.5 Collection: https://huggingface.co/collections/Qwen/qwen25
- Gemma 2 2B: https://huggingface.co/google/gemma-2-2b-it

### 한국어 LLM 리소스
- Awesome Korean LLM: https://github.com/NomaDamas/awesome-korean-llm
- KoAlpaca: https://github.com/Beomi/KoAlpaca
- Open Ko-LLM Leaderboard: https://huggingface.co/spaces/upstage/open-ko-llm-leaderboard
- 국내 LLM 비교(MSAP): https://www.msap.ai/blog-home/blog/korea-llm/

### 팀 문서(외부)
- AI팀 Wiki(모델 추론 성능 최적화): https://github.com/100-hours-a-week/14-team-dojangkok-ai/wiki/%EB%AA%A8%EB%8D%B8-%EC%B6%94%EB%A1%A0-%EC%84%B1%EB%8A%A5-%EC%B5%9C%EC%A0%81%ED%99%94

---

## 11) 동시 요청 대응: 운영 의견

> 전제: 현재 GCP에서 운용 가능한 GPU 인스턴스가 1대라서, 피크 시간대 동시 요청을 “즉시” 수용하기 어렵다는 상황.

### 의견 A) “외부 분산” 전에 단일 GPU 처리량을 먼저 최대화해야 한다

- GPU 1대여도 동시 요청을 완전히 못 받는 건 아니며, 서빙 엔진의 **동적/연속 배칭(continuous/dynamic batching)**으로 처리량을 올릴 여지가 크다.
- 함께 필요해지는 것: **요청 큐(백프레셔), 동시성 제한, 타임아웃/취소, 토큰 상한, 스트리밍, 캐시, 관측(지연/에러/토큰/VRAM)**.
- 장점: 외부 의존성 없이 “체감” 개선이 빠르다.
- 한계: 피크 트래픽이 크면 결국 GPU 풀이 필요하다.

### 의견 B) 근본 해결은 “GCP 내 GPU 확장/자동확장”이지만 리드타임 이슈가 있다

- 동시 요청을 꾸준히 처리하려면 GPU 풀이 늘어야 한다.
- 다만 현실적으로는 **쿼터/예산/리전** 이슈로 확장이 느릴 수 있어, 단기 대응이 어려울 수 있다.

### 의견 C) 외부 서비스는 “오버플로우(overflow) 라우팅”으로 쓰는 게 현실적이다

- 구조 예시: **Primary(GCP 1대) + Overflow(외부 GPU) + 라우터(큐/헬스체크/용량기반 분배)**.
- 평시에는 GCP 중심(단순/저렴/데이터 근접), 피크에서만 외부로 “버스트 처리”하는 접근이 비용·운영 균형이 좋다.
- 주의: 운영 복잡도(라우팅/관측/장애/레이트리밋/폴백)가 증가한다.

### 의견 D) 외부로 분산이 제한되면, 기능·품질을 나눠 “degrade(강등) 전략”을 적용한다

- 민감도가 높은 기능(예: 계약서 원문)은 GCP 내부, 덜 민감한 기능은 외부로 분리하는 방식.
- 피크에는 임시로 **더 작은 대체 모델**을 사용하거나, 답변을 간소화해 지연/실패를 줄이는 정책도 가능하다.
- 이 경우 제품적으로 “품질/일관성” 정책 합의가 필요하다.

### 의견 E) “실시간”이 필수가 아니라면, 비동기(잡 큐)로 푸는 게 더 깔끔할 수 있다

- 체크리스트 생성/분석처럼 비동기 처리 가능한 작업은 “접수 → 완료 알림/조회” UX로 바꾸면 GPU 1대로도 운영 난이도가 크게 내려간다.
- 실시간 챗 UX에는 부분 적용(예: 길거나 무거운 작업만 비동기) 같은 절충이 가능하다.

### 정리(개인 의견)

- “GPU 1대 → 외부 서비스로 동시 요청 분산”을 고민하는 방향은 적절하다.
- 다만 보통은 **(1) 단일 GPU 최적화 + 큐/제한/관측**을 먼저 하고, 그래도 부족하면 **(2) 오버플로우 라우팅**을 붙이는 순서가 비용/복잡도 대비 효율적이다.

### 결정을 위해 확인하면 좋은 질문

1) 피크 동시요청 규모(RPS/동시 세션)는 어느 정도로 예상하는가?
2) 평균 입력/출력 토큰과 허용 지연(SLO)은 어느 수준인가?
3) 계약서 원문 등 민감 데이터가 외부로 나가도 되는가(정책/법무/신뢰 관점)?

