# Backlog

- [x] Park `dofbi/wolof-asr`
- [x] Wolof speech is `M9and2M/whisper-small-wolof` (`wolof-small`, English prompt, sherpa-onnx int8)
- [x] Show Wolof on screen — `kShowWolofText`
- [x] Voice UI: show Whisper transcript before Marian finishes
- [ ] Voice latency: use `VoiceStageTimings` (`bottleneck=whisper|marian`) before chasing Marian opts

short message
Voice timings bottleneck=marian whisper=2160ms release=0ms marian=12855ms [opus-mt-fr-en(load=390ms tx=5954ms) traduction-en-wolof(load=322ms tx=6189ms)]
total=15090ms

Voice timings bottleneck=marian whisper=3382ms release=0ms marian=4494ms [opus-mt_tiny_fra-eng-onnx(load=336ms tx=455ms) traduction-en-wolof-onnx(load=1459ms
tx=2244ms)] total=7992ms

TODO marianMT ONNX The other pairs (fr-en, en-fr, Wolof) are the same command with --only … --upload once you want the rest.

TODO  wo-en-whisper/models/whisper-small-wo-en/best/ failed
so cleaner data recipe and a new run

## TO THINK

Why not also finetune using
https://huggingface.co/datasets/thiomi/thiomi-5k

TODO - l10n and include wolof by using the guidelines in 
https://github.com/flutter/flutter/issues/164462

TODO - include Amharic even if BLEU is low
https://huggingface.co/Hailay/movoc-mt-en-am-ti

Direction 	BLEU 	chrF
en -> am 	24.699 	33.655
am -> en 	20.485 	45.554
en -> ti 	20.556 	18.634
ti -> en 	10.571 	31.945

***

- add a CI for test 
- add a CD for android/iOS builds
