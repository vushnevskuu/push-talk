import AppKit
import SwiftUI

@MainActor
final class MenuBarStatusItemController: NSObject {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    /// Reused to avoid recreating SwiftUI hierarchy; `view.fittingSize` on a fresh host triggered
    /// EXC_BAD_ACCESS in `MenuBarMenuView.body` on macOS 26 (see crash 2026-03-24).
    private var menuHostingController: NSHostingController<MenuBarMenuView>?

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
    }

    func install() {
        configureStatusItem()
        configurePopover()
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        if menuHostingController == nil {
            menuHostingController = NSHostingController(rootView: MenuBarMenuView(model: model))
        }
        popover.contentViewController = menuHostingController
        popover.contentSize = NSSize(width: 360, height: 720)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = NSImage(systemSymbolName: "mic.circle.fill", accessibilityDescription: "VoiceInsert")
        button.image?.isTemplate = true
        button.action = #selector(togglePopover(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
    }
}
