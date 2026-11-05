#!/bin/bash
set -euo pipefail
K1_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$K1_ROOT"
mkdir -p local/bin
cc -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined -Iapp/include \
  tests/ble_tuning_protocol.c -o local/bin/test-ble-tuning
local/bin/test-ble-tuning
swiftc client/Protocol.swift tests/ProtocolTests.swift -o local/bin/test-client-protocol
local/bin/test-client-protocol
git diff --check
