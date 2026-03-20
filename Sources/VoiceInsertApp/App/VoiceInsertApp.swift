import SwiftUI

struct VoiceInsertApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("VoiceInsert", systemImage: "mic.circle.fill") {
            MenuBarMenuView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
