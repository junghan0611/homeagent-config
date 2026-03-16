#!/usr/bin/env python3
"""
Qwen3-0.6B 베이스라인 벤치마크 — Zero-shot IoT Intent 파싱
HomeAgent sLLM 파이프라인 Phase 1: 파인튜닝 전 기본 성능 측정

Usage:
    ssh gpu3i
    python /path/to/benchmark_baseline.py

Output: JSON 결과 + 정확도 요약
"""

import json
import time
import sys
from pathlib import Path

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer

MODEL_PATH = "/storage/models/huggingface/Qwen3-0.6B"
# 스크립트와 같은 디렉토리의 시드 데이터셋
DATASET_PATH = Path(__file__).parent / "intent_seed_dataset.jsonl"

SYSTEM_PROMPT = """당신은 스마트홈 IoT 제어 에이전트입니다. 사용자의 자연어 명령을 JSON으로 변환하세요.

출력 형식 (JSON만, 설명 없이):
{"action": "on|off|set_level|set_color|set_color_temp|set_thermostat|lock|unlock|query|list|summary|scene", "target": "방이름|default|all", "device_type": "light|plug|sensor|contact_sensor|lock|thermostat|all", "params": {...}}

예시:
입력: "거실 불 켜줘"
출력: {"action": "on", "target": "거실", "device_type": "light"}

입력: "온도 22도로"
출력: {"action": "set_thermostat", "target": "default", "device_type": "thermostat", "params": {"temperature": 22}}
"""


def load_dataset(path):
    """JSONL 데이터셋 로드"""
    samples = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                samples.append(json.loads(line))
    return samples


def extract_json(text):
    """LLM 출력에서 JSON 추출 시도"""
    # {로 시작하는 첫 JSON 블록 찾기
    start = text.find("{")
    if start == -1:
        return None
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                try:
                    return json.loads(text[start : i + 1])
                except json.JSONDecodeError:
                    return None
    return None


def check_action_match(predicted, expected):
    """action 필드 일치 여부"""
    if predicted is None:
        return False
    return predicted.get("action") == expected.get("action")


def check_target_match(predicted, expected):
    """target 필드 일치 여부"""
    if predicted is None:
        return False
    return predicted.get("target") == expected.get("target")


def check_device_type_match(predicted, expected):
    """device_type 필드 일치 여부"""
    if predicted is None:
        return False
    return predicted.get("device_type") == expected.get("device_type")


def check_full_match(predicted, expected):
    """action + target + device_type 전부 일치"""
    return (
        check_action_match(predicted, expected)
        and check_target_match(predicted, expected)
        and check_device_type_match(predicted, expected)
    )


def run_benchmark():
    print(f"=== Qwen3-0.6B 베이스라인 벤치마크 ===")
    print(f"모델: {MODEL_PATH}")
    print(f"데이터셋: {DATASET_PATH}")
    print()

    # 모델 로드
    print("모델 로딩...")
    t0 = time.time()
    tokenizer = AutoTokenizer.from_pretrained(MODEL_PATH, trust_remote_code=True)
    model = AutoModelForCausalLM.from_pretrained(
        MODEL_PATH,
        torch_dtype=torch.bfloat16,
        device_map="auto",
        trust_remote_code=True,
    )
    model.eval()
    load_time = time.time() - t0
    print(f"모델 로드: {load_time:.1f}초")

    # VRAM 사용량
    if torch.cuda.is_available():
        vram_mb = torch.cuda.max_memory_allocated() / 1024**2
        print(f"VRAM 사용: {vram_mb:.0f} MB")
    print()

    # 데이터셋 로드
    samples = load_dataset(DATASET_PATH)
    print(f"테스트 샘플: {len(samples)}개")
    print()

    # 벤치마크 실행
    results = []
    action_correct = 0
    target_correct = 0
    dtype_correct = 0
    full_correct = 0
    json_parseable = 0
    total_tokens = 0
    total_time = 0.0

    for i, sample in enumerate(samples):
        user_input = sample["input"]
        expected = sample["output"]

        # Qwen3 chat format
        messages = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_input},
        ]

        text = tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True,
            enable_thinking=False  # Qwen3: disable thinking for speed
        )
        inputs = tokenizer(text, return_tensors="pt").to(model.device)

        t0 = time.time()
        with torch.no_grad():
            outputs = model.generate(
                **inputs,
                max_new_tokens=150,
                do_sample=False,  # greedy for reproducibility
                temperature=1.0,
                top_p=1.0,
            )
        gen_time = time.time() - t0

        # 생성된 토큰만 추출
        new_tokens = outputs[0][inputs["input_ids"].shape[1] :]
        response = tokenizer.decode(new_tokens, skip_special_tokens=True)
        n_tokens = len(new_tokens)

        total_tokens += n_tokens
        total_time += gen_time

        # JSON 파싱 시도
        predicted = extract_json(response)
        is_json = predicted is not None
        if is_json:
            json_parseable += 1

        a_match = check_action_match(predicted, expected)
        t_match = check_target_match(predicted, expected)
        d_match = check_device_type_match(predicted, expected)
        f_match = check_full_match(predicted, expected)

        if a_match:
            action_correct += 1
        if t_match:
            target_correct += 1
        if d_match:
            dtype_correct += 1
        if f_match:
            full_correct += 1

        result = {
            "idx": i,
            "input": user_input,
            "expected": expected,
            "predicted": predicted,
            "raw_output": response[:200],
            "json_ok": is_json,
            "action_match": a_match,
            "target_match": t_match,
            "device_type_match": d_match,
            "full_match": f_match,
            "tokens": n_tokens,
            "time_s": round(gen_time, 3),
        }
        results.append(result)

        status = "✅" if f_match else ("⚠️" if a_match else "❌")
        print(
            f"  [{i+1:2d}/{len(samples)}] {status} {user_input[:30]:30s} → "
            f"{'OK' if is_json else 'PARSE_FAIL':10s} "
            f"action={'✓' if a_match else '✗'} "
            f"({gen_time:.2f}s, {n_tokens}tok)"
        )

    # 요약
    n = len(samples)
    avg_time = total_time / n if n > 0 else 0
    avg_tokens = total_tokens / n if n > 0 else 0
    tps = total_tokens / total_time if total_time > 0 else 0

    summary = {
        "model": "Qwen3-0.6B",
        "model_path": MODEL_PATH,
        "dataset_size": n,
        "load_time_s": round(load_time, 1),
        "vram_mb": round(torch.cuda.max_memory_allocated() / 1024**2) if torch.cuda.is_available() else 0,
        "accuracy": {
            "json_parseable": f"{json_parseable}/{n} ({100*json_parseable/n:.1f}%)",
            "action_match": f"{action_correct}/{n} ({100*action_correct/n:.1f}%)",
            "target_match": f"{target_correct}/{n} ({100*target_correct/n:.1f}%)",
            "device_type_match": f"{dtype_correct}/{n} ({100*dtype_correct/n:.1f}%)",
            "full_match": f"{full_correct}/{n} ({100*full_correct/n:.1f}%)",
        },
        "performance": {
            "total_time_s": round(total_time, 1),
            "avg_time_per_sample_s": round(avg_time, 3),
            "avg_tokens_per_sample": round(avg_tokens, 1),
            "tokens_per_second": round(tps, 1),
        },
    }

    print()
    print("=" * 60)
    print("=== 결과 요약 ===")
    print(f"모델:         {summary['model']}")
    print(f"VRAM:         {summary['vram_mb']} MB")
    print(f"로드 시간:    {summary['load_time_s']}s")
    print(f"샘플 수:      {n}")
    print()
    print("--- 정확도 ---")
    for k, v in summary["accuracy"].items():
        print(f"  {k:25s}: {v}")
    print()
    print("--- 성능 ---")
    for k, v in summary["performance"].items():
        print(f"  {k:25s}: {v}")
    print("=" * 60)

    # 결과 저장
    output_path = Path(__file__).parent / "benchmark_results.json"
    with open(output_path, "w") as f:
        json.dump({"summary": summary, "details": results}, f, ensure_ascii=False, indent=2)
    print(f"\n결과 저장: {output_path}")

    return summary


if __name__ == "__main__":
    run_benchmark()
