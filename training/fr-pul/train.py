"""Fine-tune Helsinki-NLP/opus-mt-fr-ha on the exported French–Pulaar bitext."""

from __future__ import annotations

import os

os.environ.setdefault("TRANSFORMERS_NO_TF", "1")
os.environ.setdefault("USE_TF", "0")

import argparse
from pathlib import Path

import torch
from transformers import (
    DataCollatorForSeq2Seq,
    MarianMTModel,
    MarianTokenizer,
    Seq2SeqTrainer,
    Seq2SeqTrainingArguments,
)

BASE_MODEL = "Helsinki-NLP/opus-mt-fr-ha"
HERE = Path(__file__).resolve().parent
DATA = HERE / "data"
OUT = HERE / "models" / "fr-pul"
# Hausa Boko already uses ɓ ɗ ƴ. Pulaar also needs ŋ, ɲ, and the capitals.
REQUIRED_TARGET_CHARS = ("ɓ", "ɗ", "ƴ", "ŋ", "ɲ", "ñ", "Ɓ", "Ɗ", "Ƴ", "Ŋ", "Ɲ", "Ñ")


def read_pairs(split: str) -> list[tuple[str, str]]:
    sources = (DATA / f"{split}.fr").read_text(encoding="utf-8").splitlines()
    targets = (DATA / f"{split}.pul").read_text(encoding="utf-8").splitlines()
    if len(sources) != len(targets):
        raise SystemExit(f"{split} files are not aligned: {len(sources)} vs {len(targets)}")
    return list(zip(sources, targets))


def pieces_for(tokenizer: MarianTokenizer, text: str) -> list[str]:
    encoded = tokenizer(text_target=text, add_special_tokens=False)
    return tokenizer.convert_ids_to_tokens(encoded["input_ids"])


def char_is_atomic(tokenizer: MarianTokenizer, char: str) -> bool:
    pieces = pieces_for(tokenizer, f"a{char}a")
    joined = " ".join(pieces)
    if "<unk>" in joined or "<0x" in joined:
        return False
    return any(char in piece for piece in pieces)


def ensure_letters(tokenizer: MarianTokenizer, model: MarianMTModel) -> list[str]:
    missing = [char for char in REQUIRED_TARGET_CHARS if not char_is_atomic(tokenizer, char)]
    report = ["target pieces for aXa:"]
    for char in REQUIRED_TARGET_CHARS:
        report.append(f"  {char}: {' '.join(pieces_for(tokenizer, f'a{char}a'))}")
    if missing:
        added = tokenizer.add_tokens(missing)
        model.resize_token_embeddings(len(tokenizer))
        seed_from = {
            "ŋ": "n",
            "ɲ": "n",
            "ñ": "n",
            "ɓ": "b",
            "ɗ": "d",
            "ƴ": "y",
            "Ŋ": "n",
            "Ɲ": "n",
            "Ñ": "n",
            "Ɓ": "b",
            "Ɗ": "d",
            "Ƴ": "y",
        }
        shared = model.model.shared.weight.data
        vocab = tokenizer.get_vocab()
        with torch.no_grad():
            for char in missing:
                new_id = vocab[char]
                donor = _donor_id(vocab, seed_from.get(char, "n"))
                if donor is not None:
                    shared[new_id].copy_(shared[donor])
        report.append(f"added tokens ({added}): {' '.join(missing)}")
    else:
        report.append("no tokens added")
    for char in REQUIRED_TARGET_CHARS:
        if not char_is_atomic(tokenizer, char):
            raise SystemExit(f"target vocab still splits {char!r}")
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "tokenizer_report.txt").write_text("\n".join(report) + "\n", encoding="utf-8")
    print("\n".join(report))
    return missing


def _donor_id(vocab: dict[str, int], letter: str) -> int | None:
    for key in (f"▁{letter}", letter):
        if key in vocab:
            return vocab[key]
    return None


class PairDataset(torch.utils.data.Dataset):
    def __init__(self, pairs: list[tuple[str, str]], tokenizer: MarianTokenizer, max_length: int):
        self.pairs = pairs
        self.tokenizer = tokenizer
        self.max_length = max_length

    def __len__(self) -> int:
        return len(self.pairs)

    def __getitem__(self, index: int) -> dict[str, list[int]]:
        source, target = self.pairs[index]
        encoded = self.tokenizer(
            source,
            text_target=target,
            max_length=self.max_length,
            truncation=True,
        )
        return {
            "input_ids": encoded["input_ids"],
            "attention_mask": encoded["attention_mask"],
            "labels": encoded["labels"],
        }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs", type=float, default=4)
    parser.add_argument("--batch", type=int, default=8)
    parser.add_argument("--lr", type=float, default=2e-5)
    parser.add_argument("--max-length", type=int, default=128)
    parser.add_argument("--max-steps", type=int, default=-1)
    args = parser.parse_args()

    if not torch.cuda.is_available():
        raise SystemExit("CUDA is not visible. Run this inside WSL on the RTX 4070.")

    train_pairs = read_pairs("train")
    dev_pairs = read_pairs("dev")
    print(f"train {len(train_pairs)}  dev {len(dev_pairs)}  gpu {torch.cuda.get_device_name(0)}")

    tokenizer = MarianTokenizer.from_pretrained(BASE_MODEL)
    model = MarianMTModel.from_pretrained(BASE_MODEL)
    ensure_letters(tokenizer, model)

    collator = DataCollatorForSeq2Seq(tokenizer, model=model, padding=True)
    use_bf16 = torch.cuda.is_bf16_supported()
    training_args = Seq2SeqTrainingArguments(
        output_dir="/tmp/fr-pul-checkpoints",
        per_device_train_batch_size=args.batch,
        per_device_eval_batch_size=args.batch,
        gradient_accumulation_steps=2,
        learning_rate=args.lr,
        warmup_steps=200,
        num_train_epochs=args.epochs,
        max_steps=args.max_steps,
        bf16=use_bf16,
        fp16=not use_bf16,
        eval_strategy="epoch",
        save_strategy="epoch",
        load_best_model_at_end=True,
        metric_for_best_model="eval_loss",
        greater_is_better=False,
        logging_steps=25,
        save_total_limit=2,
        report_to=[],
        dataloader_pin_memory=True,
    )
    trainer = Seq2SeqTrainer(
        model=model,
        args=training_args,
        train_dataset=PairDataset(train_pairs, tokenizer, args.max_length),
        eval_dataset=PairDataset(dev_pairs, tokenizer, args.max_length),
        data_collator=collator,
        processing_class=tokenizer,
    )
    trainer.train()
    trainer.save_model(str(OUT))
    tokenizer.save_pretrained(str(OUT))
    print(f"saved {OUT}")


if __name__ == "__main__":
    main()
