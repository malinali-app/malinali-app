# French → Pulaar, fine-tuned from opus-mt-fr-ha

Starts from [Helsinki-NLP/opus-mt-fr-ha](https://huggingface.co/Helsinki-NLP/opus-mt-fr-ha) and fine-tunes on Turso plus the local ARPRIM and Open-Data files. The saved folder is `models/fr-pul/` (`config.json`, `model.safetensors`, SentencePiece files) for the Candle Marian loader.

Run inside WSL, from this directory. PyTorch with CUDA is already on this machine; the venv only adds the Hugging Face stack.

```bash
python3 -m venv --system-site-packages .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python export_turso.py
.venv/bin/python train.py
.venv/bin/python demo.py
```

`export_turso.py` reads `secrets.txt` at the repo root and does not print the token. After Turso, it merges:

- `training/pulaar_french_parallel_corpus.json` (Open-Data; Pulaar is `Original`, French is `Translated`)
- ARPRIM dictionary `ARPRIM_terminologies_v18.json`
- ARPRIM sentences `ARPRIM_corpus_phrases_v1.jsonl` (COVID rows dropped)

Turso pairs win on overlap. The split is a hash of each pair, so new rows do not move old test sentences. `data/` and `models/` stay untracked.

`train.py` continues from `models/fr-pul/` when that checkpoint exists (`--base Helsinki-NLP/opus-mt-fr-ha` to restart). Default `--max-length` is 256.

Hausa already spells ɓ ɗ ƴ. If ŋ or ɲ are missing from the target vocab, training adds them and copies the embedding of `n` as a start.
