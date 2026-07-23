# ACM OTA Baseline Notes

This firmware should be manually flashed once before app-based firmware updates are enabled.

Required board/flash setup:

- Use an ESP32 partition scheme with `otadata`, `ota_0`, and `ota_1`.
- Keep enough app-slot size for the ACM firmware binary.
- Verify the firmware reports `FW:1.0.0-ota,<hw>,1,<serial>;` in BLE telemetry.

Arduino IDE recommendation:

- Production module `ESP32-S3-WROOM-1-N8R2`: 8 MB flash, 2 MB PSRAM.
- Development/personal module `N16R8`: 16 MB flash, 8 MB PSRAM.
- Use the included `partitions.csv` as the common OTA baseline partition table for both.
  - It targets the first 8 MB of flash, so it works on both N8 and N16 modules.
  - It gives two 3 MB OTA app slots plus about 1.94 MB SPIFFS.
  - The N16R8 unit will leave its extra 8 MB flash unused, which is preferable to maintaining separate production/dev partition layouts.
- Avoid `No OTA` and `Huge APP` partition schemes for OTA-capable baseline firmware.

Arduino IDE settings:

- Board: the matching ESP32-S3 board profile for the ACM hardware.
- Flash Size:
  - Production `N8R2`: `8MB`
  - Personal `N16R8`: `16MB`, or `8MB` if using the exact same upload settings as production.
- PSRAM:
  - Production `N8R2`: `OPI PSRAM` / `2MB`, depending on the board menu wording.
  - Personal `N16R8`: `OPI PSRAM` / `8MB`, depending on the board menu wording.
- Partition Scheme: `Custom` / `Custom partition table`.
- Custom partition file: `ACMV2_R3/partitions.csv`.

Important: the partition scheme itself cannot be changed by a future OTA update. Any devices already flashed with a non-OTA or too-small partition layout need this baseline flashed manually over USB first.

The iOS app uses the `FW` telemetry section to decide whether a connected ACM can support future app-based firmware updates.

BLE OTA scaffold:

- Service UUID: `8b6f3f10-7d3b-4f8d-9f1b-2f3f4c7a0001`
- Characteristic UUID: `8b6f3f10-7d3b-4f8d-9f1b-2f3f4c7a0002`
- Current test command: write `STATUS`
- Expected notification: `OTA:READY,FW=<version>,HW=<revision>,MTU=185`
