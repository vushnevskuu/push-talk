import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorderView: View {
    let shortcut: KeyboardShortcut
    @Binding var isRecording: Bool
    let onCapture: (KeyboardShortcut) -> Void
    let onCancel: () -> Void

    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 12) {
            Text(isRecording ? "Press a new shortcut" : shortcut.displayString)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minWidth: 180, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: 1)
                )

            Button(isRecording ? "Cancel" : "Record Shortcut") {
                isRecording.toggle()
            }
            .buttonStyle(.borderedProminent)
        }
        .onChange(of: isRecording) { newValue in
            if newValue {
                installMonitor()
            } else {
                removeMonitor()
            }
        }
        .onDisappear {
            removeMonitor()
        }
    }

    private func installMonitor() {
        removeMonitor()

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecording else { return event }

            if event.keyCode == UInt16(kVK_Escape) {
                isRecording = false
                onCancel()
                return nil
            }

            guard let shortcut = KeyboardShortcut.capture(from: event) else {
                NSSound.beep()
                return nil
            }

            isRecording = false
            onCapture(shortcut)
            return nil
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
