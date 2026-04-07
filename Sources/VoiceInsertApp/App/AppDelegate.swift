import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemController = MenuBarStatusItemController(model: AppRuntime.sharedModel)

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController.install()
    }

    /// After granting permissions in System Settings, the shortcut monitor may stay Local Only until the app re-inits the event tap / hotkey.
    func applicationDidBecomeActive(_ notification: Notification) {
        AppRuntime.sharedModel.refreshPermissionsFromUI()
        AppRuntime.sharedModel.refreshSubscriptionEntitlementFromHost()
    }
}
