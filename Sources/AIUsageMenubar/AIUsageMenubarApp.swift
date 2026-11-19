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
                Image("CodexLogo", bundle: .module)
                    .renderingMode(.template).resizable().scaledToFit().frame(width: 16, height: 16)
                    .accessibilityLabel("Codex")
                Text(model.codexMenuBarText ?? (model.codexLoading ? "…" : model.codexError == nil ? "—" : "!"))
                    .monospacedDigit().help(model.codexError ?? "Codex 5-hour window")
                Image("CopilotLogo", bundle: .module)
                    .renderingMode(.template).resizable().scaledToFit().frame(width: 16, height: 16)
                    .accessibilityLabel("GitHub Copilot")
                Text(model.copilotMenuBarText ?? (model.copilotLoading ? "M …" : "M —"))
                    .monospacedDigit().help(model.copilotError ?? "Copilot monthly quota")
            }
            .fixedSize()
        }
        .menuBarExtraStyle(.window)
    }
}
