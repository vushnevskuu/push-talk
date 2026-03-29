import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemController = MenuBarStatusItemController(model: AppRuntime.sharedModel)

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController.install()
    }
}
