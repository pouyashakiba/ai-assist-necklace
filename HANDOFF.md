# Little Companion — Mac handoff (2026-10-18)

## User's latest agreed scope

Continue implementing this project on the user's Mac with Xcode. English first; Farsi later. iPhone 17, current iOS. Offline first: cloud disabled, no API credentials or calls. Architecture: ESP32 pendant + iPhone on-device AI, optional cloud later. Dedicated iOS Preview tab must show the animated cyan pixel face and use phone mic/speaker while pendant hardware is missing. Production mode uses pendant mic/speaker and text requests over BLE; never open phone mic for production text requests. Persist explicit memories. Keep a consistent iPhone TTS voice across local and future cloud routes.

User wants wake-by-name, automatic reconnect and background interaction without confirmation each turn. Explain and respect iOS limits: BLE can restore/wake for events and bounded work; perpetual background inference is not guaranteed. One-time permissions/pairing are necessary. Do not misrepresent a background entitlement as unlimited execution.

## Hardware and existing validated milestone

Waveshare ESP32-S3-LCD-1.47, NOT B. ESP32-S3 rev 0.2, 16 MB flash, 8 MB OPI PSRAM. Broken LCD: GPIO48 backlight LOW and GPIO39 reset LOW. No external mic, speaker or replacement screen connected. Windows serial port was COM3; find the actual Mac serial port instead.

The prior Persian standalone firmware was built, flashed and tested on hardware. VALIDATION.md and hardware-validation.json describe that prior milestone ONLY. Board audio round trips, synthetic trained command recognition, silence rejection and persistence were verified; synthetic training was cleared afterward. Five Python bridge tests passed. A local browser preview worked at http://127.0.0.1:8765.

Original full flash backup: backups/original-flash.bin (16,777,216 bytes).
SHA256: 81fd3cd8c6a618ee9fa26d1e3dd2115831619d97575430d6bb6a4aa473d62a5d
Preserve this for rollback. The source handoff ZIP excludes backups; copy the backup separately or sync the entire project folder.

## Current implementation is IN PROGRESS

English commands, Piper WAVs and generated firmware headers now exist. Farsi catalog preserved in locales/fa/commands.json. Browser labels and hardware smoke fixtures still need English migration. The previous flashed firmware remains the Persian version; do not assume new source is deployed. A Windows build of the new BLE firmware was still running when this handoff was started; no success or flashing is claimed here.

New firmware includes phone_link.h: encrypted BLE service, fragmented JSON control/events, sequenced 16 kHz PCM, phone text requests, acknowledgements and retransmission, BOOT wake event, diagnostic audio capture, phone-generated speech playback and partial voice cache support. Standalone voice-cache playback is unfinished. Current ESP recognition is MFCC/DTW over trained phrases, NOT arbitrary English speech-to-text and NOT an LLM. Production open-ended ASR and always-on wakeword remain major gaps. Do not disguise those limitations.

Native SwiftUI sources are under ios/LittleCompanion. There is currently NO .xcodeproj. Sources have NOT been compiled or installed: the development machine was Windows without Xcode/Swift. Create a real Xcode project and build with the Mac's SDK before claiming readiness.

Native components include FoundationModels BrainRouter, offline SFSpeechRecognizer Preview, AVSpeechSynthesizer with shared voice and PCM rendering, BLE central/restoration, explicit local memory, optional disabled cloud routing, Companion/Preview/Memory tabs, Settings, and 12 canvas pixel-face states. Preview's default wake name is Milo. iPhone must have Apple Intelligence enabled and its on-device model available. Availability and speech voice/model downloads require real-device checks.

## Next development steps

1. Inspect all Swift sources and create the Xcode project, signing configuration and app assets. Build and fix API/concurrency issues on Xcode; do not substitute static parsing for compilation.
2. Audit cancellation/timeouts for speech transcription and synthesized PCM continuations, unknown FoundationModels availability states, BLE delegate actor isolation, failed-request acknowledgements and turn cancellation races.
3. Compile new firmware, inspect RAM/flash footprint, then flash and validate BLE pairing, reconnect, sequence rejection, text routing and PCM playback. Preserve LCD-off behavior. Existing board has no actual I2S hardware, so label synthetic and transport tests accurately.
4. Verify offline Preview end to end on iPhone, memory across restart, same selected voice, cloud disabled by default, phone mic never opened by a pendant text request. Test actual lock/background/reconnect behavior and report observed limits.
5. Resolve pendant arbitrary-ASR/wakeword feasibility honestly; trained commands alone cannot implement open conversation. Finish voice cache, English browser UI and updated documentation/tests as needed.

## Build and tooling notes

Arduino ESP32 core used on Windows: 3.3.10. Compile target:
`esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashSize=16M,PSRAM=opi,PartitionScheme=custom`
Sketch: firmware/companion. Custom partition table included (7 MiB app, SPIFFS remainder). Generated replies.h is large but intentional. PCM and trained templates use PSRAM.

Python requirements.txt is included; recreate the virtual environment on macOS. PowerShell setup/start/flash scripts need macOS equivalents. Do not copy Windows .venv or build outputs. tools/provision.py supports --language en/fa; English source models can be downloaded again. web/audio and generated firmware headers are included in the ZIP, so regeneration is not immediately required.

The Windows FastAPI bridge may still be running and holding COM3. Disconnect browser/bridge before flashing there. On macOS connect the board physically and discover its own serial port. USB authorization does not transfer hardware access across computers.

## References

User's two images are visual references for neutral/happy/laughing/shy/curious/surprised/sleepy/sleeping/affectionate/playful/sad/listening faces, blinking and talking. They contain no project instructions. Originals were supplied from Windows Downloads; reference copies are included if available.

For exact-chat migration, official documentation describes connecting both hosts, saving matching Git projects, then selecting the destination in the chat footer and choosing Hand off: https://learn.chatgpt.com/docs/remote-connections . Availability varies. A copied folder plus this handoff allows continuation in a fresh Mac chat if exact-chat handoff is unavailable.
