#!/bin/bash
set -euo pipefail
K1_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$K1_ROOT"
.venv/bin/cmake -S app -B app/build -G Ninja \
  -DBOARD=rtl8762gtu_kb -DSHIELD=keychron_k1_ultra_ansi \
  -DBOARD_ROOT="$K1_ROOT/app" -DDTS_ROOT="$K1_ROOT/app" \
  -DZEPHYR_TOOLCHAIN_VARIANT=zephyr \
  -DZEPHYR_SDK_INSTALL_DIR="$K1_ROOT/.toolchains/zephyr-sdk-0.16.8" \
  -DPython3_EXECUTABLE="$K1_ROOT/.venv/bin/python" \
  -DCMAKE_MAKE_PROGRAM="$K1_ROOT/.venv/bin/ninja"
.venv/bin/cmake --build app/build -j "${K1_BUILD_JOBS:-6}"
mkdir -p local/bin
swiftc client/Protocol.swift client/KeychronBluetooth.swift -o local/bin/keychron-bluetooth \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker client/Info.plist
echo 'OTA candidate: app/build/zephyr/zmk-ota.bin'
echo 'Bluetooth controls: local/bin/keychron-bluetooth --help'
