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
            HStack(spacing: 3) {
                Image("CodexLogo", bundle: .module)
                    .renderingMode(.template).resizable().scaledToFit().frame(width: 12, height: 12)
                    .accessibilityLabel("Codex")
                Text(model.codexMenuBarText ?? (model.codexLoading ? "…" : model.codexError == nil ? "—" : "!"))
                    .monospacedDigit().help(model.codexError ?? "Codex 5-hour window")
                Image("CopilotLogo", bundle: .module)
                    .renderingMode(.template).resizable().scaledToFit().frame(width: 12, height: 12)
                    .accessibilityLabel("GitHub Copilot")
                Text(model.copilotMenuBarText ?? (model.copilotLoading ? "M…" : "M—"))
                    .monospacedDigit().help(model.copilotError ?? "Copilot monthly quota")
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .menuBarExtraStyle(.window)
    }
}
