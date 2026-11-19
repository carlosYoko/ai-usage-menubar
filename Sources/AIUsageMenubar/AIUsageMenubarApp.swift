import SwiftUI
import AppKit
import Combine

@main
struct AIUsageMenubarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var modelObservation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.imagePosition = .noImage
        }

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 600)
        popover.contentViewController = NSHostingController(rootView: MenuContentView(model: model))

        modelObservation = model.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in self?.updateStatusItem() }
        }
        updateStatusItem()
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.controlTextColor
        ]
        let title = NSMutableAttributedString()
        appendIcon("CodexLogo", to: title)
        title.append(NSAttributedString(string: " \(model.codexMenuBarText ?? (model.codexLoading ? "…" : model.codexError == nil ? "—" : "!"))  ", attributes: attributes))
        appendIcon("CopilotLogo", to: title)
        title.append(NSAttributedString(string: " \(model.copilotMenuBarText ?? (model.copilotLoading ? "M…" : "M—"))", attributes: attributes))
        button.attributedTitle = title
        button.toolTip = [model.codexError, model.copilotError].compactMap { $0 }.joined(separator: "\n")
    }

    private func appendIcon(_ name: String, to title: NSMutableAttributedString) {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return }
        image.isTemplate = true
        image.size = NSSize(width: 12, height: 12)
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -2, width: 12, height: 12)
        title.append(NSAttributedString(attachment: attachment))
    }
}
