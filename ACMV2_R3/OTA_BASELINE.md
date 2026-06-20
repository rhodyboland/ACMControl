# ACM OTA Baseline Notes

This firmware should be manually flashed once before app-based firmware updates are enabled.

Required board/flash setup:

- Use an ESP32 partition scheme with `otadata`, `ota_0`, and `ota_1`.
- Keep enough app-slot size for the ACM firmware binary.
- Verify the firmware reports `FW:1.0.0-ota,<hw>,1,<serial>;` in BLE telemetry.

Arduino IDE recommendation:

- If the ACM hardware has 8 MB flash, use an 8 MB OTA partition scheme such as `8M with spiffs`.
  - This gives roughly two 3.2 MB OTA app slots and about 1.5 MB SPIFFS.
  - This is the preferred production choice if the module really has 8 MB flash.
- If the ACM hardware has 4 MB flash, prefer `Minimal SPIFFS`.
  - This gives roughly two 1.9 MB OTA app slots and a small SPIFFS partition.
  - This is better than the default 4 MB scheme if the firmware is already near 1.2 MB.
- Avoid `No OTA` and `Huge APP` partition schemes for OTA-capable baseline firmware.

Important: the partition scheme itself cannot be changed by a future OTA update. Any devices already flashed with a non-OTA or too-small partition layout need this baseline flashed manually over USB first.

The iOS app uses the `FW` telemetry section to decide whether a connected ACM can support future app-based firmware updates.

BLE OTA scaffold:

- Service UUID: `8b6f3f10-7d3b-4f8d-9f1b-2f3f4c7a0001`
- Characteristic UUID: `8b6f3f10-7d3b-4f8d-9f1b-2f3f4c7a0002`
- Current test command: write `STATUS`
- Expected notification: `OTA:READY,FW=<version>,HW=<revision>,MTU=185`
