import SwiftUI
import UniformTypeIdentifiers

struct MemoryView: View {
    @EnvironmentObject private var companion: CompanionController
    @State private var fact = ""
    @State private var exportPresented = false
    @State private var document = MemoryDocument(data: Data())
    @State private var status = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Little things worth remembering.").font(.title2.bold())
                    Text("Say “Remember that…” or add a fact here. Facts stay on this iPhone until you remove them. Saving facts is memory, not retraining the model.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Teach me something") {
                    TextField("A name, preference, or useful fact", text: $fact, axis: .vertical).lineLimit(2...4)
                    Button("Remember this") { if companion.memory.remember(fact) { fact = ""; status = "Saved on your iPhone." } else { status = companion.memory.persistenceError ?? "Couldn't save the fact." } }.disabled(fact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("\(companion.memory.facts.count) saved memories") {
                    if companion.memory.facts.isEmpty { Text("Nothing saved yet. Let's get to know each other.").foregroundStyle(.secondary) }
                    ForEach(companion.memory.facts) { item in
                        VStack(alignment: .leading, spacing: 6) { Text(item.text); Text(item.updated, style: .date).font(.caption).foregroundStyle(.secondary) }
                            .swipeActions { Button("Forget", role: .destructive) { companion.memory.forget(item.id) } }
                    }
                }
                Section {
                    Button("Export memories and conversation") { do { document = MemoryDocument(data: try companion.memory.exportData()); exportPresented = true } catch { status = error.localizedDescription } }
                    Button("Clear conversation history", role: .destructive) { companion.memory.clearConversation() }
                    if !status.isEmpty { Text(status).font(.caption) }
                    if let error = companion.memory.persistenceError { Text(error).foregroundStyle(.orange) }
                }
            }.navigationTitle("Memory").fileExporter(isPresented: $exportPresented, document: document, contentType: .json, defaultFilename: "companion-memory") { result in if case .failure(let error) = result { status = error.localizedDescription } }
        }
    }
}

struct MemoryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
