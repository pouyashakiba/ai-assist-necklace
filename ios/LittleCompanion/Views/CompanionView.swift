import SwiftUI

struct CompanionView: View {
    @EnvironmentObject private var companion: CompanionController
    @State private var settingsPresented = false
    @State private var facesPresented = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("PREVIEW · IPHONE AUDIO").font(.caption2.monospaced()).tracking(2).foregroundStyle(Color.companionMint)
                        Spacer()
                        Label(companion.network.online ? "Online" : "Offline", systemImage: companion.network.online ? "network" : "iphone").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("A little more alive.").font(.largeTitle.bold().rounded())
                        Text(companion.statusText).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 14) {
                        HStack {
                            Label(companion.settings.mode.title, systemImage: "sparkle").font(.caption)
                            Spacer()
                            Text(companion.lastSource?.rawValue ?? "ENGLISH FIRST").font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                        PixelFace(mood: companion.mood, speaking: companion.phase == .speaking)
                            .padding(6).background(.black, in: RoundedRectangle(cornerRadius: 23))
                            .overlay(RoundedRectangle(cornerRadius: 23).stroke(Color.white.opacity(0.15), lineWidth: 3))
                            .padding(.vertical, 14)
                        if !companion.liveWords.isEmpty { Text(companion.liveWords).font(.callout).foregroundStyle(Color.companionCyan).frame(maxWidth: .infinity) }
                        HStack(spacing: 10) {
                            Button { Task { await companion.listenOnce() } } label: { Label("Talk to \(companion.settings.name)", systemImage: "mic.fill").frame(maxWidth: .infinity).padding(.vertical, 8) }
                                .buttonStyle(.borderedProminent).tint(.companionCyan).foregroundStyle(Color.companionBackground).disabled(companion.busy)
                            if companion.busy || companion.handsFree || companion.phase == .listening {
                                Button { companion.stop() } label: { Image(systemName: "stop.fill").frame(width: 30, height: 40) }.buttonStyle(.bordered).accessibilityLabel("Stop conversation and listening")
                            }
                        }
                        Button { Task { await companion.toggleHandsFree() } } label: {
                            Label(companion.handsFree ? "Wake listening is on · Say \(companion.settings.name)" : "Listen for my companion's name", systemImage: companion.handsFree ? "waveform.circle.fill" : "ear")
                                .font(.footnote).frame(minHeight: 44)
                        }.disabled(companion.busy).tint(companion.handsFree ? .companionCyan : .companionMint)
                    }.padding(20).background(Color.companionSurface, in: RoundedRectangle(cornerRadius: 25))
                    Text(companion.notice).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 3).accessibilityAddTraits(.updatesFrequently)
                    if let error = companion.memory.persistenceError { Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange) }
                    if companion.memory.messages.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Start something small.").font(.headline)
                            Text("Ask a question, or say “Remember that I like quiet mornings.”").font(.subheadline).foregroundStyle(.secondary)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color.companionSurface, in: RoundedRectangle(cornerRadius: 18))
                    } else {
                        ForEach(companion.memory.messages.suffix(20)) { message in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack { Text(message.role == "user" ? "YOU" : companion.settings.name.uppercased()); Spacer(); if let source = message.source { Text(source.rawValue) } }.font(.caption2.monospaced()).foregroundStyle(.secondary)
                                Text(message.text).textSelection(.enabled)
                            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                .background(message.role == "user" ? Color.companionSurface : Color.companionCyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }.padding(22)
            }
            .background(Color.companionBackground)
            .navigationTitle(companion.settings.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { facesPresented = true } label: { Image(systemName: "face.smiling") }.accessibilityLabel("Expression gallery") }
                ToolbarItem(placement: .topBarTrailing) { Button { settingsPresented = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Settings") }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    TextField("Or type a thought…", text: $companion.draft, axis: .vertical).lineLimit(1...4).submitLabel(.send).onSubmit { companion.submit() }.accessibilityLabel("Message")
                    Button { companion.submit() } label: { Image(systemName: "arrow.up").font(.headline).frame(width: 44, height: 44).background(Color.companionCyan, in: Circle()).foregroundStyle(Color.companionBackground) }
                        .disabled(companion.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || companion.busy).accessibilityLabel("Send message")
                }.padding(14).background(.ultraThinMaterial)
            }
            .sheet(isPresented: $settingsPresented) { SettingsView() }
            .sheet(isPresented: $facesPresented) { ExpressionGallery() }
        }
    }
}

private extension Font { func rounded() -> Font { self } }

struct ExpressionGallery: View {
    @EnvironmentObject private var companion: CompanionController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 135))], spacing: 14) {
                    ForEach(FaceMood.allCases) { mood in
                        Button { companion.setMood(mood) } label: { VStack { PixelFace(mood: mood).background(.black, in: RoundedRectangle(cornerRadius: 14)); Text(mood.title).font(.footnote) }.padding(8) }.buttonStyle(.plain)
                    }
                }.padding()
            }.background(Color.companionBackground).navigationTitle("A face for every feeling").toolbar { Button("Done") { dismiss() } }
        }.presentationDetents([.large])
    }
}
