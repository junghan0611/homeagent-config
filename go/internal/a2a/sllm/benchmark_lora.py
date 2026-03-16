#!/usr/bin/env python3
"""
Qwen3-0.6B + LoRA 벤치마크 — 파인튜닝 후 성능 비교
"""

import json
import time
from pathlib import Path

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import PeftModel

MODEL_PATH = "/storage/models/huggingface/Qwen3-0.6B"
LORA_PATH = "/tmp/sllm-bench/homeagent-intent-lora"
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
    samples = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                samples.append(json.loads(line))
    return samples


def extract_json(text):
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


def run_benchmark():
    print("=== Qwen3-0.6B + LoRA 벤치마크 ===")

    # 모델 로드
    print("베이스 모델 로딩...")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_PATH, trust_remote_code=True)
    model = AutoModelForCausalLM.from_pretrained(
        MODEL_PATH,
        torch_dtype=torch.bfloat16,
        device_map="auto",
        trust_remote_code=True,
    )

    print("LoRA adapter 로딩...")
    model = PeftModel.from_pretrained(model, LORA_PATH)
    model.eval()

    if torch.cuda.is_available():
        vram_mb = torch.cuda.max_memory_allocated() / 1024**2
        print(f"VRAM: {vram_mb:.0f} MB")

    # 데이터셋
    samples = load_dataset(DATASET_PATH)
    print(f"테스트 샘플: {len(samples)}개")
    print()

    # 벤치마크
    action_correct = 0
    full_correct = 0
    json_parseable = 0
    total_time = 0.0
    results = []

    for i, sample in enumerate(samples):
        user_input = sample["input"]
        expected = sample["output"]

        messages = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_input},
        ]
        text = tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True,
            enable_thinking=False
        )
        inputs = tokenizer(text, return_tensors="pt").to(model.device)

        t0 = time.time()
        with torch.no_grad():
            outputs = model.generate(
                **inputs, max_new_tokens=150, do_sample=False,
            )
        gen_time = time.time() - t0
        total_time += gen_time

        new_tokens = outputs[0][inputs["input_ids"].shape[1]:]
        response = tokenizer.decode(new_tokens, skip_special_tokens=True)

        predicted = extract_json(response)
        is_json = predicted is not None
        if is_json:
            json_parseable += 1

        a_match = predicted is not None and predicted.get("action") == expected.get("action")
        t_match = predicted is not None and predicted.get("target") == expected.get("target")
        d_match = predicted is not None and predicted.get("device_type") == expected.get("device_type")
        f_match = a_match and t_match and d_match

        if a_match:
            action_correct += 1
        if f_match:
            full_correct += 1

        status = "✅" if f_match else ("⚠️" if a_match else "❌")
        print(
            f"  [{i+1:2d}/{len(samples)}] {status} {user_input[:30]:30s} → "
            f"action={'✓' if a_match else '✗'} "
            f"({gen_time:.2f}s)"
        )

        results.append({
            "input": user_input,
            "expected": expected,
            "predicted": predicted,
            "action_match": a_match,
            "full_match": f_match,
        })

    n = len(samples)
    print()
    print("=" * 60)
    print("=== LoRA 결과 요약 ===")
    print(f"JSON 파싱:     {json_parseable}/{n} ({100*json_parseable/n:.1f}%)")
    print(f"action 일치:   {action_correct}/{n} ({100*action_correct/n:.1f}%)")
    print(f"full 일치:     {full_correct}/{n} ({100*full_correct/n:.1f}%)")
    print(f"평균 시간:     {total_time/n:.3f}s/sample")
    print("=" * 60)

    # 비교
    baseline_path = Path(__file__).parent / "benchmark_results.json"
    if baseline_path.exists():
        with open(baseline_path) as f:
            baseline = json.load(f)["summary"]["accuracy"]
        print()
        print("=== baseline vs LoRA 비교 ===")
        print(f"  action: {baseline['action_match']} → {action_correct}/{n} ({100*action_correct/n:.1f}%)")
        print(f"  full:   {baseline['full_match']} → {full_correct}/{n} ({100*full_correct/n:.1f}%)")

    # 결과 저장
    output_path = Path(__file__).parent / "benchmark_lora_results.json"
    with open(output_path, "w") as f:
        json.dump({
            "summary": {
                "model": "Qwen3-0.6B + LoRA",
                "json_parseable": f"{json_parseable}/{n}",
                "action_match": f"{action_correct}/{n} ({100*action_correct/n:.1f}%)",
                "full_match": f"{full_correct}/{n} ({100*full_correct/n:.1f}%)",
                "avg_time_s": round(total_time/n, 3),
            },
            "details": results,
        }, f, ensure_ascii=False, indent=2)
    print(f"\n결과 저장: {output_path}")


if __name__ == "__main__":
    run_benchmark()
