#!/usr/bin/env python3
"""Copy libonnxruntime.so and give it a private SONAME.

sherpa-onnx already ships libonnxruntime.so (symbol version 1.28). Replacing
that file makes Whisper fail to find OrtGetApiBase. Marian keeps its own
runtime under libort_marian.so.
"""

from __future__ import annotations

import sys
from pathlib import Path

_OLD = b"libonnxruntime.so"
_NEW = b"libort_marian.so"


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} SRC DST")
    if len(_NEW) > len(_OLD):
        raise SystemExit("replacement SONAME is longer than the original")
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    data = bytearray(src.read_bytes())
    index = data.find(_OLD)
    if index < 0:
        raise SystemExit(f"{src}: SONAME string not found")
    if data.find(_OLD, index + 1) >= 0:
        raise SystemExit(f"{src}: SONAME string is not unique")
    padded = _NEW + b"\x00" * (len(_OLD) - len(_NEW))
    data[index : index + len(_OLD)] = padded
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(data)


if __name__ == "__main__":
    main()
