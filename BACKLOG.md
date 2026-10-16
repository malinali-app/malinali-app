# Backlog

- Carry on FON whisper training
- await djelia approval for bambara whisper training - https://huggingface.co/datasets/djelia/bambara-mt-v2

- [x] use sherpa onnx models for vocal translation in english and french

- [x] Park `dofbi/wolof-asr`
- [x] Wolof speech is `M9and2M/whisper-small-wolof` (`wolof-small`, English prompt, sherpa-onnx int8)
- [x] Show Wolof on screen — `kShowWolofText`
- [x] Voice UI: show Whisper transcript before Marian finishes
- [ ] Voice latency: use `VoiceStageTimings` (`bottleneck=whisper|marian`) before chasing Marian opts

## TO THINK

- add a CI for test
- add a CD for android/iOS builds

- app l10n and include wolof by using the guidelines in 
https://github.com/flutter/flutter/issues/164462

- include Amharic even if BLEU is low
https://huggingface.co/Hailay/movoc-mt-en-am-ti

Direction 	BLEU 	chrF
en -> am 	24.699 	33.655
am -> en 	20.485 	45.554
en -> ti 	20.556 	18.634
ti -> en 	10.571 	31.945
