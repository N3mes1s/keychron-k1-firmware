# Local Bluetooth controls for K1 Ultra 8K

Target: Keychron K1 Ultra 8K Knob ANSI, `3434:1610`, board `rtl8762gtu_kb`,
shield `keychron_k1_ultra_ansi`. Do not use this image for another model/layout.
This branch is a prototype, not a hardware-qualified release.

## Ownership and dependency boundaries

The firmware is maintained in `N3mes1s/keychron-k1-firmware`, with the original
Keychron repository retained locally as `upstream`. The manifest uses our
`N3mes1s/keychron-zephyr` and `N3mes1s/keychron-hal-realtek` forks at exact commit
IDs. Other Zephyr dependencies are also frozen to commit IDs. Nothing tracks a
moving vendor branch during builds.

This provides control over our source changes and dependency updates. It does
not remove vendor code: the Realtek HAL includes precompiled radio/SDK libraries,
and the image header tool is a vendor binary. Their source is not available in
this checkout, so they cannot be independently source-audited here. The compiler
is the official Zephyr SDK 0.16.8, verified against pinned SHA-256 values before
extraction. The native Mac utility has no third-party runtime packages.

Base source: Keychron/zmk `7f8d16732a3782e237915bff30a1f67de09268b7`.
Source dependencies are recorded in `app/west.yml`. The local setup downloads
them once; subsequent builds and keyboard control do not need internet access.

## Build on Apple Silicon

Requirements: Git, uv, Xcode command-line tools, and `dtc` (device-tree-compiler).

```sh
git clone --branch codex/bluetooth-controls https://github.com/N3mes1s/keychron-k1-firmware.git
cd keychron-k1-firmware
./scripts/bootstrap-macos.sh
./scripts/test-local.sh
./scripts/build-macos.sh
```

The header-packaged candidate is `app/build/zephyr/zmk-ota.bin`. The raw linker
output `zmk.bin` is retained separately and is not the OTA candidate. Packaging
starts with a fresh copy of the raw image on every run to avoid repeated headers.

The fork also restores the missing `RTK_DFU` Kconfig declaration selected by the
stock K1 shield and selects the header tool using the build host, not the ARM
cross-compilation target. Both fixes are required to package the image on this Mac.

## Native Mac controls

The keyboard must be in Bluetooth mode, paired to this Mac, and running this
firmware. macOS may ask for Bluetooth permission for the utility. It first looks
up the keyboard's existing system HID connection; it does not require a second
computer or Keychron's website.

```sh
local/bin/keychron-bluetooth status
local/bin/keychron-bluetooth debounce 0 10
local/bin/keychron-bluetooth profile responsive
local/bin/keychron-bluetooth profile stock
local/bin/keychron-bluetooth custom 7.5 15 0 4000
```

If multiple matching keyboards are connected, pass `--device` followed by the
macOS peripheral UUID printed by a previous status call. The utility verifies the
protocol and encrypted active-host status before writing, then reads settings
back. It does not read key events, upload data, or run a cloud client.

Timing profiles:

| Profile | Mac interval request | Other hosts | Peripheral latency |
| --- | --- | --- | --- |
| stock (default) | 15 ms | 7.5 ms | 30 |
| responsive | 11.25–15 ms | 7.5–11.25 ms | 0 |
| fast | 7.5 ms | 7.5 ms | 0 |

All profiles request a 4 s supervision timeout. Lower latency values may increase
power consumption. A peripheral latency of 30 permits skipped connection events;
it does not establish that every keystroke is delayed by 30 events.

These are connection-parameter requests. macOS and the radio stack decide what
is negotiated. The `negotiated` fields and
`negotiated_timing_matches_request` report the observed connection separately.
`parameter_submission_result == 0` means the request was submitted locally, not
that the central accepted it. No 1000 Hz/8000 Hz Bluetooth guarantee is made.

The existing stored debounce setting is common to USB, Bluetooth and 2.4 GHz.
The 0 ms press / 10 ms release fix does not require a new firmware to apply over
Bluetooth. This fork adds wireless access to that control and connection timing.

## GATT protocol v1

Service: `8b7f9b20-6f06-4e8c-bc17-41f136c1a100`.
Read/write control: `8b7f9b20-6f06-4e8c-bc17-41f136c1a101`.

Both operations require an encrypted LE connection, a stored bond, the active
keyboard profile's peer address and the matching local Bluetooth identity.
Prepared/offset writes, unknown versions/opcodes and invalid lengths are rejected.
There is no raw Launcher bridge, bootloader command, firmware write, keymap/macro
read, or key-report stream on this service. USB Launcher operation is retained.

Commands are bytes, with all 16-bit values little endian:

| Command | Bytes |
| --- | --- |
| Debounce | `[1, 1, press_ms, release_ms]` |
| Preset | `[1, 2, profile]` (stock=0, responsive=1, fast=2) |
| Custom | `[1, 3, min_interval:u16, max_interval:u16, latency:u16, timeout:u16]` |

Interval units are 1.25 ms; supervision-timeout units are 10 ms. Custom intervals
are bounded to 7.5–50 ms, peripheral latency to 0–30 and timeout to 2–6 s. The
Bluetooth supervision constraint is checked before the setting can be applied.
Press debounce allows 0–50 ms; release debounce allows 1–50 ms.

Status is 24 bytes (normal GATT long reads handle the default 23-byte MTU):

| Offset | Field |
| --- | --- |
| 0 | protocol version (1) |
| 1 | capabilities (debounce=1, timing=2) |
| 2, 3 | press/release debounce in ms |
| 4 | selected timing profile (custom=3) |
| 5 | flags: encrypted=1, active bonded host=2, timing save pending=4, negotiated timing matches=8 |
| 6, 8, 10, 12 | requested min/max interval, latency, timeout (`u16`) |
| 14, 16, 18 | actual interval, latency, timeout (`u16`) |
| 20 | last local parameter-submission result (`i16`, initially `-ENODATA`) |
| 22 | timing-save result (`i16`) |

Timing preferences are stored in a separate versioned settings record. Debounce
uses the existing Launcher persistence mechanism (a delayed write of about 1 s).
Invalid optional tuning records fall back to stock timing without preventing
Bluetooth startup. GATT service-changed/database-hash support remains enabled.

## Validation and hardware test gate

Local checks cover all 65,536 press/release byte combinations, malformed packet
lengths/versions/opcodes, parameter boundaries, supervision timing constraints,
presets and native-client status decoding. The target firmware and native Mac
client compile. This does not exercise the Realtek controller or a live bond.

Hardware validation is still required: encrypted read/write authorization,
existing keyboard input, pairing/reconnection, negotiated timing on macOS,
persisted settings after power cycling, battery impact and stock USB recovery.
Adding the service can require service-cache refresh/re-pairing on some hosts.

Do not flash automatically. Prepare the official stock image and a spare input
method, review the image/target and authorize the hardware write separately.
No firmware has been flashed as part of creating this branch. No latency
improvement from this custom firmware has been measured yet.
