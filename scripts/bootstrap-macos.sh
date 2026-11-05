#!/bin/bash
set -euo pipefail
K1_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$K1_ROOT"
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo 'This setup script supports Apple Silicon macOS.' >&2
  exit 1
fi
command -v uv >/dev/null
command -v dtc >/dev/null || { echo 'Install device-tree-compiler (dtc) first.' >&2; exit 1; }
if [[ ! -x .venv/bin/python ]]; then uv venv .venv --python 3.13; fi
uv pip install --python .venv/bin/python -r requirements-build.lock
if [[ ! -d .west ]]; then .venv/bin/west init -l app; fi
.venv/bin/west update --narrow -o=--depth=1
mkdir -p .toolchains/downloads
K1_SDK_BASE=https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.16.8
for K1_ARCHIVE in zephyr-sdk-0.16.8_macos-aarch64_minimal.tar.xz toolchain_macos-aarch64_arm-zephyr-eabi.tar.xz; do
  if [[ ! -f ".toolchains/downloads/$K1_ARCHIVE" ]]; then
    curl -fSL "$K1_SDK_BASE/$K1_ARCHIVE" -o ".toolchains/downloads/$K1_ARCHIVE"
  fi
done
.venv/bin/python scripts/verify-sdk.py
echo 'Build setup complete. Subsequent builds need no network.'
