import Foundation

@main
enum VoiceInsertProcessEntry {
    static func main() {
        if EventInjectorMode.runIfRequested(arguments: CommandLine.arguments) {
            return
        }

        VoiceInsertApp.main()
    }
}
