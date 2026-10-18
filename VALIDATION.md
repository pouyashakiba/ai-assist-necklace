# Validation — 2026-10-18

Confirmed on the connected **Waveshare ESP32-S3-LCD-1.47 (non-B)** at COM3. ESP32-S3 revision v0.2, 16 MB Winbond flash, 8,388,608 bytes PSRAM. No physical microphone or speaker was connected.

## Completed

- Full original flash saved to `backups/original-flash.bin` (16,777,216 bytes). SHA256 stored beside it and independently verified. First 65,536 bytes matched a separate ROM-loader read. Every remaining backup chunk passed the stub's MD5 digest check. Backups are ignored by Git.
- Arduino ESP32 3.3.10 compilation passed. Final application binary: 1,769,344 bytes. Static RAM: 218,540 bytes. Partition binary verified: app at `0x10000`, size `0x700000`; SPIFFS at `0x710000`, size `0x8F0000`.
- Bootloader, partition table, boot selector and application flashed successfully; esptool verified each written hash.
- Live firmware status reports `little-companion-1.0`, PSRAM 8 MiB, `lcd: off`, `storage: true`, and `hardware_audio: false`. Firmware drives the confirmed non-B backlight GPIO48 LOW and holds ST7789 reset GPIO39 LOW. No physical electrical/display measurement was made.
- **All 13 reply WAVs** were retrieved from the board through USB and compared byte-for-byte with the provisioned originals; format checked as mono, 16 kHz PCM.
- Two Persian synthetic command utterances were trained twice each on the actual board. Time-stretched held-out variants were classified correctly as command IDs 0 and 1 by the board's MFCC/DTW recognizer.
- Silent PCM was rejected by the board.
- Training survived an explicit firmware restart and reconnect. Synthetic templates were then removed; all 12 training counts were zero at handoff.
- Five USB protocol tests passed: partial binary frames, binary preservation, rejected-header handling, truncated-audio disconnection, disconnected-port error.
- Python syntax and JavaScript syntax checks passed. Page returns HTTP 200; command metadata contains 12 commands plus the unknown reply. Cross-origin mutation returned 403; invalid Host returned 400.
- Browser UI reviewed at desktop and 375 px widths, and at the app's narrower default panel. Horizontal overflow fixed. All 12 face presets present; selecting happy changed the main face and disabled automatic mood. No external font/script dependencies. No browser console errors/warnings during layout review.
- Final page connected to COM3, displayed 8 MB PSRAM and LCD off, and completed playback of the Persian greeting received from the board. The page showed the greeting text and happy face; browser console remained clear.

## Fixes found through hardware tests

The default esptool pipelined read stalled near 512 KB. A one-block-at-a-time read completed the 16 MiB backup with digest validation. Native HWCDC needed a startup handshake and a drain of duplicate status messages. Audio uploaded in one large write overflowed the board's 256-byte RX queue; paced 128-byte chunks passed the complete real-board recognition test. First-time SPIFFS formatting is given a separate extended timeout.

## Still requires real hardware/user evaluation

Synthetic utterance tests verify the data path, on-board DSP, and persistence; **they do not establish recognition accuracy for a human speaker, noisy room, or unseen phrases**. The user must train at least two commands with their own microphone before speaking tests. The browser microphone capture path has not been tested with the user's live voice. I2S microphone/amplifier playback and standalone push-to-talk need the missing physical components and are untested. The future replacement LCD driver is not implemented because the display model is unspecified; the supplied expression geometry is implemented in the web preview.

This is an experimental, speaker-dependent fixed-command assistant with prerecorded Persian replies. It has no open-ended conversation model, general Persian transcription, cloud speech service, or emotion inference model.

Machine-readable real-board results: `hardware-validation.json`.
