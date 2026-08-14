# Bundled ACM Firmware

Place the firmware binary to install from the app here and add it to the `ACMControl` app target's Copy Bundle Resources phase.

Current app-side sender expects:

- File name: `ACMV2_R3.bin`
- Target version sent to the ACM: `1.0.1`
- Chunk size: 72 binary bytes, hex-encoded in the BLE command payload

The first implementation intentionally uses a bundled firmware file rather than a remote manifest, so every app release carries the firmware it knows how to install.
