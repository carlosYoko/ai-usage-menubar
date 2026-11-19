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
            HStack(spacing: 7) {
                if let codex = model.codexMenuBarText {
                    Image(systemName: "sparkles").accessibilityLabel("Codex")
                    Text(codex).monospacedDigit()
                } else if let error = model.codexError {
                    Image(systemName: "sparkles").accessibilityLabel("Codex")
                    Text("!").help(error)
                }
                if let copilot = model.copilotMenuBarText {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").accessibilityLabel("GitHub Copilot")
                    Text(copilot).monospacedDigit()
                }
                if model.codexMenuBarText == nil && model.copilotMenuBarText == nil && model.codexError == nil {
                    Image(systemName: "chart.bar.xaxis")
                    Text("AI Usage")
                }
            }
            .fixedSize()
        }
        .menuBarExtraStyle(.window)
    }
}
