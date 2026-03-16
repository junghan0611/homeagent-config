#!/usr/bin/env python3
"""
LoRA merge + GGUF 변환 파이프라인

1. Qwen3-0.6B + LoRA adapter → merged model (safetensors)
2. merged model → GGUF (f16)
3. GGUF f16 → Q4_K_M 양자화

Usage:
    ssh gpu3i
    # nix-shell로 gguf 패키지 포함하여 실행
    nix-shell -p python3Packages.gguf --run 'python3 /tmp/sllm-bench/merge_and_convert.py'
"""

import json
import os
import time
import shutil
from pathlib import Path

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import PeftModel

MODEL_PATH = "/storage/models/huggingface/Qwen3-0.6B"
LORA_PATH = "/tmp/sllm-bench/homeagent-intent-lora"
MERGED_PATH = "/tmp/sllm-bench/homeagent-intent-merged"


def step1_merge_lora():
    """LoRA adapter를 base model에 merge"""
    print("=== Step 1: LoRA Merge ===")

    print("베이스 모델 로딩...")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_PATH, trust_remote_code=True)
    model = AutoModelForCausalLM.from_pretrained(
        MODEL_PATH,
        torch_dtype=torch.float16,  # GGUF 변환 시 f16이 표준
        device_map="cpu",  # merge는 CPU에서
        trust_remote_code=True,
    )

    print("LoRA adapter 로딩...")
    model = PeftModel.from_pretrained(model, LORA_PATH)

    print("LoRA merge 중...")
    t0 = time.time()
    model = model.merge_and_unload()
    merge_time = time.time() - t0
    print(f"merge 완료: {merge_time:.1f}s")

    print(f"merged 모델 저장: {MERGED_PATH}")
    os.makedirs(MERGED_PATH, exist_ok=True)
    model.save_pretrained(MERGED_PATH, safe_serialization=True)
    tokenizer.save_pretrained(MERGED_PATH)

    # config.json 복사 (GGUF 변환에 필요)
    src_config = Path(MODEL_PATH) / "config.json"
    if src_config.exists():
        shutil.copy(src_config, Path(MERGED_PATH) / "config.json")

    # 크기 확인
    total_size = sum(
        f.stat().st_size for f in Path(MERGED_PATH).rglob("*") if f.is_file()
    )
    print(f"merged 모델 크기: {total_size / 1024**2:.1f} MB")
    return MERGED_PATH


def step2_verify_merged():
    """merged 모델 quick verification"""
    print("\n=== Step 2: Merged 모델 검증 ===")

    tokenizer = AutoTokenizer.from_pretrained(MERGED_PATH, trust_remote_code=True)
    model = AutoModelForCausalLM.from_pretrained(
        MERGED_PATH,
        torch_dtype=torch.bfloat16,
        device_map="auto",
        trust_remote_code=True,
    )
    model.eval()

    test_cases = [
        ("거실 불 켜줘", "on"),
        ("침실 밝기 50으로", "set_level"),
        ("온도 몇 도야?", "query"),
        ("문 잠가줘", "lock"),
        ("외출 모드", "scene"),
    ]

    system = '당신은 스마트홈 IoT 에이전트입니다. JSON만 출력: {"action":"...", "target":"...", "device_type":"..."}'

    correct = 0
    for user_input, expected_action in test_cases:
        messages = [
            {"role": "system", "content": system},
            {"role": "user", "content": user_input},
        ]
        text = tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True,
            enable_thinking=False
        )
        inputs = tokenizer(text, return_tensors="pt").to(model.device)

        with torch.no_grad():
            outputs = model.generate(**inputs, max_new_tokens=100, do_sample=False)
        new_tokens = outputs[0][inputs["input_ids"].shape[1]:]
        response = tokenizer.decode(new_tokens, skip_special_tokens=True)

        # JSON 추출
        try:
            start = response.index("{")
            end = response.rindex("}") + 1
            parsed = json.loads(response[start:end])
            action = parsed.get("action", "?")
        except (ValueError, json.JSONDecodeError):
            action = "PARSE_FAIL"

        ok = action == expected_action
        if ok:
            correct += 1
        status = "✅" if ok else "❌"
        print(f"  {status} {user_input:20s} → action={action} (expected={expected_action})")

    print(f"\n  merged 검증: {correct}/{len(test_cases)}")
    del model
    torch.cuda.empty_cache()
    return correct == len(test_cases)


def step3_print_gguf_instructions():
    """GGUF 변환 안내 (llama.cpp convert 필요)"""
    print("\n=== Step 3: GGUF 변환 안내 ===")
    print(f"""
merged 모델이 {MERGED_PATH}에 저장되었습니다.

GGUF 변환 방법 (llama.cpp 필요):

  # 1. llama.cpp 클론 (한 번만)
  git clone https://github.com/ggml-org/llama.cpp /tmp/llama.cpp
  cd /tmp/llama.cpp

  # 2. f16 GGUF 변환
  nix-shell -p python3Packages.gguf python3Packages.numpy python3Packages.torch python3Packages.transformers python3Packages.sentencepiece --run \\
    'python3 convert_hf_to_gguf.py {MERGED_PATH} --outfile /tmp/sllm-bench/homeagent-intent-f16.gguf --outtype f16'

  # 3. Q4_K_M 양자화 (llama-quantize 빌드 필요)
  # cmake -B build && cmake --build build --target llama-quantize
  # ./build/bin/llama-quantize /tmp/sllm-bench/homeagent-intent-f16.gguf /tmp/sllm-bench/homeagent-intent-q4km.gguf Q4_K_M

  # 또는 llama.cpp 없이 gguf 패키지만으로:
  nix-shell -p python3Packages.gguf --run \\
    'python3 -c "from gguf import GGUFWriter; print(\\"gguf available\\")"'

크기 예상:
  f16:    ~1.2 GB (0.6B × 2bytes)
  Q4_K_M: ~0.4 GB (0.6B × ~0.7bytes)
  Q8_0:   ~0.6 GB

ARM 보드 추론:
  llama.cpp -m homeagent-intent-q4km.gguf -p "거실 불 켜줘" --n-predict 100
  예상 속도: RPi5 ~3-5 tok/s, RK3576 ~5-8 tok/s
""")


if __name__ == "__main__":
    merged_path = step1_merge_lora()
    success = step2_verify_merged()
    step3_print_gguf_instructions()

    if success:
        print("\n✅ LoRA merge 성공. GGUF 변환 진행 가능.")
    else:
        print("\n⚠️ merged 모델 검증 일부 실패. 확인 필요.")
