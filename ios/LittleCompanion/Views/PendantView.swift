import SwiftUI

struct PendantView: View {
    @EnvironmentObject private var companion: CompanionController
    @State private var wiredAudioConfirmed = false
    @State private var settingsPresented = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(companion.pendant.status, systemImage: companion.pendant.connected ? "link" : "link.badge.plus")
                    Text("ESP32-S3 · broken LCD kept off · Bluetooth LE").font(.caption).foregroundStyle(.secondary)
                    Label(companion.settings.cloudEnabled ? "Cloud enabled when configured" : "Offline first · cloud disabled", systemImage: companion.settings.cloudEnabled ? "cloud" : "iphone")
                    Text(companion.brain.offlineStatus).font(.caption).foregroundStyle(.secondary)
                }
                if companion.pendant.connected {
                    Section("Audio hardware") {
                        Label(companion.pendant.hardwareAudio ? "Wired audio enabled" : "Using the iPhone microphone and speaker", systemImage: companion.pendant.hardwareAudio ? "hifispeaker" : "iphone")
                        Toggle("I have wired the I2S mic and amplifier", isOn: $wiredAudioConfirmed)
                        Button(companion.pendant.hardwareAudio ? "Disable pendant audio" : "Enable pendant audio") {
                            Task { do { try await companion.pendant.enableHardware(!companion.pendant.hardwareAudio) } catch { companion.notice = error.localizedDescription } }
                        }.disabled(!wiredAudioConfirmed && !companion.pendant.hardwareAudio)
                        Text("Only enable after wiring the documented I2S pins. The current board has no attached mic or speaker, so use iPhone audio for now.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section { Button("Disconnect pendant", role: .destructive) { companion.pendant.disconnect() } }
                } else {
                    Section("Nearby companions") {
                        Button(companion.pendant.scanning ? "Stop searching" : "Find my pendant") { if companion.pendant.scanning { companion.pendant.stopScan() } else { companion.pendant.scan() } }
                        ForEach(companion.pendant.devices) { discovery in Button { companion.pendant.connect(discovery) } label: { HStack { Text(discovery.name); Spacer(); Text("\(discovery.rssi) dBm").font(.caption).foregroundStyle(.secondary) } } }
                    }
                }
                Section("What the pendant does") {
                    Text("Normal use accepts text from the pendant without opening the iPhone microphone or requiring a tap per request. The phone generates the answer and voice; the pendant plays the audio. The Preview tab uses the iPhone's mic, speaker and face display while you don't have audio/display hardware.").font(.footnote)
                    Text("Background Bluetooth is enabled. iOS controls execution time and may terminate the app; uninterrupted model availability isn't guaranteed. Initial permissions and pairing are required once. No recurring confirmation is added by the app.").font(.caption).foregroundStyle(.secondary)
                    Text("Current onboard recognition is limited to trained command phrases. Full English transcription on the ESP32 is not implemented yet; arbitrary spoken questions require that upgrade or phone-side transcription.").font(.caption).foregroundStyle(.orange)
                    Text("Its screen is broken, so expressions are shown in the Companion tab. A replacement display needs its own driver.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Your companion").toolbar { Button { settingsPresented = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Settings") }.sheet(isPresented: $settingsPresented) { SettingsView() }
        }
    }
}
