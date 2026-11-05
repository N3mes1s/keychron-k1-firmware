# K1 Ultra Bluetooth controls

This fork develops local Bluetooth settings for the **Keychron K1 Ultra 8K Knob
ANSI**, USB `3434:1610`. Work lives on `codex/bluetooth-controls` and is based on
Keychron's official `rtl8762g` source. This is experimental firmware; a successful
build does not establish that it is safe to flash or that latency improves on a
particular host.

The prototype adds encrypted, bonded-host controls for debounce and Bluetooth
connection timing, negotiated-timing readback, and a native macOS controller
using Apple's CoreBluetooth framework. The stock timing profile is the default.
It does not turn Bluetooth into the keyboard's 8 kHz proprietary radio mode.

See [build, protocol, and hardware validation instructions](docs/local-bluetooth.md).
The original upstream ZMK introduction follows.

# Zephyr™ Mechanical Keyboard (ZMK) Firmware

[![Discord](https://img.shields.io/discord/719497620560543766)](https://zmk.dev/community/discord/invite)
[![Build](https://github.com/zmkfirmware/zmk/workflows/Build/badge.svg)](https://github.com/zmkfirmware/zmk/actions)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-v2.0%20adopted-ff69b4.svg)](CODE_OF_CONDUCT.md)

[ZMK Firmware](https://zmk.dev/) is an open source ([MIT](LICENSE)) keyboard firmware built on the [Zephyr™ Project](https://www.zephyrproject.org/) Real Time Operating System (RTOS). ZMK's goal is to provide a modern, wireless, and powerful firmware free of licensing issues.

Check out the website to learn more: https://zmk.dev/.

You can also come join our [ZMK Discord Server](https://zmk.dev/community/discord/invite).

To review features, check out the [feature overview](https://zmk.dev/docs/). ZMK is under active development, and new features are listed with the [enhancement label](https://github.com/zmkfirmware/zmk/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement) in GitHub. Please feel free to add 👍 to the issue description of any requests to upvote the feature.
