import SwiftUI
import AppKit

@main
struct AIUsageMenubarApp: App {
    @StateObject private var model = AppModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            Label("AI Usage", systemImage: "chart.bar.xaxis")
        }
        .menuBarExtraStyle(.window)
    }
}
