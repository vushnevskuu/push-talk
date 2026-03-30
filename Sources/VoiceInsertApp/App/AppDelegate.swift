import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemController = MenuBarStatusItemController(model: AppRuntime.sharedModel)

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController.install()
    }

    /// После выдачи прав в System Settings монитор клавиш часто остаётся в Local Only, пока приложение снова не переинициализирует event tap / hot key.
    func applicationDidBecomeActive(_ notification: Notification) {
        AppRuntime.sharedModel.refreshPermissionsFromUI()
    }
}
