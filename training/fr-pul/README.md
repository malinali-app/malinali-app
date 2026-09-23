# French → Pulaar, fine-tuned from opus-mt-fr-ha

Starts from [Helsinki-NLP/opus-mt-fr-ha](https://huggingface.co/Helsinki-NLP/opus-mt-fr-ha). Turso plus ARPRIM and Open-Data are labeled, then training can drop scripture/UI and upsample street phrases. The saved folder is `models/fr-pul/` for the Candle Marian loader.

```bash
python3 -m venv --system-site-packages .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python export_turso.py
.venv/bin/python train.py
.venv/bin/python demo.py --label street
```

`export_turso.py` writes `data/{train,dev,test}.{fr,pul,jsonl}`. JSONL fields: `fr`, `pul`, `origin`, `labels`, `primary`.

Primary labels: `street`, `glossary`, `scripture`, `literary`, `news`, `ui`, `covid`. Train defaults: exclude `scripture,ui,covid`, upsample `street=3`, keep 25% of glossary, eval on `street`. Decode uses `length_penalty=1.2` and a short `max_new_tokens` cap.

`train.py` continues from `models/fr-pul/` when that checkpoint exists.
