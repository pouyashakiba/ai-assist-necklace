import SwiftUI

@main struct LittleCompanionApp: App {
    @StateObject private var companion = CompanionController()
    var body: some Scene {
        WindowGroup {
            TabView {
                PendantView().tabItem { Label("Companion", systemImage: "link") }
                CompanionView().tabItem { Label("Preview", systemImage: "face.smiling") }
                MemoryView().tabItem { Label("Memory", systemImage: "sparkles.rectangle.stack") }
            }.environmentObject(companion).tint(.companionCyan).preferredColorScheme(.dark)
        }
    }
}
