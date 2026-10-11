import SwiftUI
import MochiCore

@main
struct MochiApp: App {
    var body: some Scene {
        MenuBarExtra {
            VStack(spacing: 8) {
                Text("Mochi is here 🌱")
                    .font(.system(.headline, design: .rounded))
                Button("Quit Mochi") { NSApp.terminate(nil) }
            }
            .padding()
        } label: {
            Text("🍡 Mochi")
        }
        .menuBarExtraStyle(.window)
    }
}
