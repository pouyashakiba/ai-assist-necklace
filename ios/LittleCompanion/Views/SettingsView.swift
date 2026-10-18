import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject private var companion: CompanionController
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var keySaved = !KeychainStore.read().isEmpty
    @State private var keyNotice = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Your companion") {
                    TextField("Name and wake phrase", text: $companion.settings.name).autocorrectionDisabled().onChange(of: companion.settings.name) { _, _ in if companion.handsFree { companion.stop() } }
                    Text("Use a distinctive name. Renaming stops any active listening session; turn it on again to use the new name.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Where answers come from") {
                    Picker("Brain", selection: $companion.settings.mode) { ForEach(BrainMode.allCases) { Text($0.title).tag($0) } }
                    Label(companion.brain.offlineStatus, systemImage: companion.brain.offlineAvailable ? "checkmark.circle" : "exclamationmark.circle").font(.footnote)
                    Text("Automatic uses cloud AI when connected and configured, then falls back to the iPhone. iPhone only never sends your conversation to the cloud. Offline answers have a smaller knowledge range.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Cloud AI · personal API key") {
                    Toggle("Enable cloud processing", isOn: $companion.settings.cloudEnabled)
                    Text("Off by default. With cloud off, replies are generated on this iPhone, even when internet is available.").font(.caption).foregroundStyle(.secondary)
                    TextField("Model ID", text: $companion.settings.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(keySaved ? "Key saved in Keychain · replace…" : "OpenAI API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save API key") {
                        do { try KeychainStore.save(key); key = ""; keySaved = true; keyNotice = "Saved securely on this iPhone." }
                        catch { keyNotice = error.localizedDescription }
                    }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if keySaved { Button("Remove API key", role: .destructive) { do { try KeychainStore.save(""); keySaved = false; keyNotice = "Cloud key removed." } catch { keyNotice = error.localizedDescription } } }
                    if !keyNotice.isEmpty { Text(keyNotice).font(.caption) }
                    Text("Cloud mode sends your question, recent conversation, and relevant saved facts to OpenAI. API usage is billed separately from ChatGPT. The model is editable because access varies by account.").font(.caption).foregroundStyle(.secondary)
                }
                Section("One voice, in every mode") {
                    Toggle("Speak replies", isOn: $companion.settings.speakReplies)
                    Picker("English voice", selection: $companion.settings.voiceID) {
                        Text("Best available English voice").tag("")
                        ForEach(companion.speech.voices, id: \.identifier) { Text("\($0.name) · \($0.language)").tag($0.identifier) }
                    }
                    Toggle("Play through pendant", isOn: $companion.settings.pendantSpeaker)
                    Text("The same iPhone speech engine speaks cloud and offline answers. Pendant playback needs an enabled I2S amplifier and speaker; otherwise leave this off. Download enhanced English voices in iOS Settings for a more natural voice.").font(.caption).foregroundStyle(.secondary)
                    Button("Preview my voice") { Task { do { try await companion.speech.speak("Hi, I'm \(companion.settings.name). Same little companion, wherever we go.", voiceID: companion.settings.voiceID) } catch { keyNotice = error.localizedDescription } } }.disabled(companion.busy || companion.handsFree)
                }
                Section("Wake-name listening") {
                    Text("Enable a listening session in the Companion tab before locking the phone. The app uses on-device English recognition to hear its name. It does not have Siri's system privileges. Phone calls, resource limits, force-quit, and restarts can end listening. Check its status and resume when needed.").font(.footnote)
                    Text("If the phone is powered off, it cannot process speech. The pendant can still use its limited standalone fallback when powered and fitted with audio hardware.").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Make it yours").toolbar { Button("Done") { key = ""; dismiss() } }
        }.onDisappear { key = "" }
    }
}
