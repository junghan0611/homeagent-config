#!/usr/bin/env python3
"""
Qwen3-0.6B LoRA 파인튜닝 — 한국어 IoT Intent 파싱
HomeAgent sLLM 파이프라인 Phase 2: 시드 데이터로 LoRA 적용

Usage:
    ssh gpu3i
    python /path/to/finetune_lora.py

Output: LoRA adapter → /storage/models/homeagent-intent-lora/
"""

import json
import os
import time
from pathlib import Path

import torch
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    TrainingArguments,
)
from peft import LoraConfig, get_peft_model, TaskType
from trl import SFTTrainer, SFTConfig
from datasets import Dataset

MODEL_PATH = "/storage/models/huggingface/Qwen3-0.6B"
OUTPUT_DIR = "/tmp/sllm-bench/homeagent-intent-lora"
DATASET_PATH = Path(__file__).parent / "intent_seed_dataset.jsonl"

SYSTEM_PROMPT = """당신은 스마트홈 IoT 제어 에이전트입니다. 사용자의 자연어 명령을 JSON으로 변환하세요.

출력 형식 (JSON만, 설명 없이):
{"action": "on|off|set_level|set_color|set_color_temp|set_thermostat|lock|unlock|query|list|summary|scene", "target": "방이름|default|all", "device_type": "light|plug|sensor|contact_sensor|lock|thermostat|all", "params": {...}}"""


def load_dataset(path):
    """시드 데이터를 SFT 포맷으로 변환"""
    samples = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                data = json.loads(line)
                samples.append({
                    "messages": [
                        {"role": "system", "content": SYSTEM_PROMPT},
                        {"role": "user", "content": data["input"]},
                        {"role": "assistant", "content": json.dumps(data["output"], ensure_ascii=False)},
                    ]
                })
    return Dataset.from_list(samples)


def main():
    print("=== Qwen3-0.6B LoRA 파인튜닝 ===")
    print(f"모델: {MODEL_PATH}")
    print(f"데이터셋: {DATASET_PATH}")
    print(f"출력: {OUTPUT_DIR}")
    print()

    # 토크나이저
    tokenizer = AutoTokenizer.from_pretrained(MODEL_PATH, trust_remote_code=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    # 모델
    print("모델 로딩...")
    t0 = time.time()
    model = AutoModelForCausalLM.from_pretrained(
        MODEL_PATH,
        torch_dtype=torch.bfloat16,
        device_map="auto",
        trust_remote_code=True,
    )
    print(f"모델 로드: {time.time()-t0:.1f}s")

    # LoRA 설정
    lora_config = LoraConfig(
        task_type=TaskType.CAUSAL_LM,
        r=16,
        lora_alpha=32,
        lora_dropout=0.05,
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"],
        bias="none",
    )

    model = get_peft_model(model, lora_config)
    trainable = sum(p.numel() for p in model.parameters() if p.requires_grad)
    total = sum(p.numel() for p in model.parameters())
    print(f"학습 파라미터: {trainable:,} / {total:,} ({100*trainable/total:.2f}%)")

    # 데이터셋
    dataset = load_dataset(DATASET_PATH)
    print(f"학습 샘플: {len(dataset)}개")

    # 학습 설정 — 52 샘플이라 에폭 많이, 작은 배치
    training_args = SFTConfig(
        output_dir=OUTPUT_DIR,
        num_train_epochs=20,
        per_device_train_batch_size=4,
        gradient_accumulation_steps=2,
        learning_rate=2e-4,
        weight_decay=0.01,
        warmup_ratio=0.1,
        logging_steps=10,
        save_strategy="epoch",
        save_total_limit=2,
        bf16=True,
        optim="adamw_torch",
        max_length=512,
        report_to="none",  # wandb 없이 (간단 테스트)
    )

    # 트레이너
    trainer = SFTTrainer(
        model=model,
        args=training_args,
        train_dataset=dataset,
        processing_class=tokenizer,
    )

    print()
    print("학습 시작...")
    t0 = time.time()
    result = trainer.train()
    train_time = time.time() - t0
    print(f"학습 완료: {train_time:.1f}s")
    print(f"최종 loss: {result.training_loss:.4f}")

    # LoRA adapter 저장
    model.save_pretrained(OUTPUT_DIR)
    tokenizer.save_pretrained(OUTPUT_DIR)
    print(f"LoRA adapter 저장: {OUTPUT_DIR}")

    # VRAM 사용량
    if torch.cuda.is_available():
        vram_mb = torch.cuda.max_memory_allocated() / 1024**2
        print(f"최대 VRAM: {vram_mb:.0f} MB")

    # 요약
    summary = {
        "model": "Qwen3-0.6B + LoRA",
        "lora_r": 16,
        "lora_alpha": 32,
        "trainable_params": trainable,
        "total_params": total,
        "dataset_size": len(dataset),
        "epochs": 20,
        "batch_size": 4,
        "train_time_s": round(train_time, 1),
        "final_loss": round(result.training_loss, 4),
        "vram_mb": round(vram_mb) if torch.cuda.is_available() else 0,
        "output_dir": OUTPUT_DIR,
    }

    summary_path = Path(OUTPUT_DIR) / "training_summary.json"
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    with open(summary_path, "w") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)
    print(f"학습 요약: {summary_path}")

    return summary


if __name__ == "__main__":
    main()
