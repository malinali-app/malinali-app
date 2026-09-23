"""Print held-out full sentences: French source, Pulaar hypothesis, Pulaar reference."""

from __future__ import annotations

import os

os.environ.setdefault("TRANSFORMERS_NO_TF", "1")
os.environ.setdefault("USE_TF", "0")

import argparse
from pathlib import Path

import torch
from sacrebleu.metrics import CHRF
from transformers import MarianMTModel, MarianTokenizer

HERE = Path(__file__).resolve().parent
DATA = HERE / "data"
MODEL = HERE / "models" / "fr-pul"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=12)
    parser.add_argument("--min-words", type=int, default=5)
    parser.add_argument("--max-words", type=int, default=16)
    args = parser.parse_args()

    sources = (DATA / "test.fr").read_text(encoding="utf-8").splitlines()
    targets = (DATA / "test.pul").read_text(encoding="utf-8").splitlines()
    pool = [
        (source, target)
        for source, target in zip(sources, targets)
        if args.min_words <= len(source.split()) <= args.max_words
    ]
    if len(pool) <= args.limit:
        chosen = pool
    else:
        step = len(pool) / args.limit
        chosen = [pool[int(i * step)] for i in range(args.limit)]
    if not chosen:
        raise SystemExit("No full sentences in the test split.")

    device = "cuda" if torch.cuda.is_available() else "cpu"
    tokenizer = MarianTokenizer.from_pretrained(MODEL)
    model = MarianMTModel.from_pretrained(MODEL).to(device)
    model.eval()

    hypotheses = []
    batch_size = 8
    for start in range(0, len(chosen), batch_size):
        batch = [source for source, _ in chosen[start : start + batch_size]]
        encoded = tokenizer(
            batch,
            return_tensors="pt",
            padding=True,
            truncation=True,
            max_length=256,
        ).to(device)
        with torch.no_grad():
            generated = model.generate(
                **encoded,
                num_beams=4,
                max_new_tokens=128,
                no_repeat_ngram_size=3,
            )
        hypotheses.extend(tokenizer.batch_decode(generated, skip_special_tokens=True))

    lines = []
    for (source, reference), hypothesis in zip(chosen, hypotheses):
        block = f"FR  {source}\nHY  {hypothesis}\nREF {reference}"
        print(block)
        print()
        lines.append(block)
    score = CHRF().corpus_score(hypotheses, [[reference for _, reference in chosen]])
    footer = f"chrF on these {len(chosen)} sentences: {score.score:.2f}"
    print(footer)
    (MODEL / "demo.txt").write_text("\n\n".join(lines) + "\n\n" + footer + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
