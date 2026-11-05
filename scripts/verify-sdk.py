#!/usr/bin/env python3
"""Verify pinned official SDK downloads before extracting compiler executables."""
import hashlib
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[1]
ARCHIVES = {
    'zephyr-sdk-0.16.8_macos-aarch64_minimal.tar.xz':
        'e1432a80ad9ec85dd3fdc5607b981ef66bc93ee383e47cac47527a5debd85361',
    'toolchain_macos-aarch64_arm-zephyr-eabi.tar.xz':
        '91986ff78f4de0c401de7fb8cb4094ea6dc5112a9e60c8c757372ac54516baa2',
}

for name, expected in ARCHIVES.items():
    archive = ROOT / '.toolchains/downloads' / name
    with archive.open('rb') as stream:
        actual = hashlib.file_digest(stream, 'sha256').hexdigest()
    if actual != expected:
        raise SystemExit(f'Checksum mismatch: {name}')
for name in ARCHIVES:
    target = ROOT / '.toolchains'
    if name.startswith('toolchain_'):
        target /= 'zephyr-sdk-0.16.8'
    with tarfile.open(ROOT / '.toolchains/downloads' / name) as archive:
        archive.extractall(target, filter='data')
print('Official Zephyr SDK checksums verified.')
