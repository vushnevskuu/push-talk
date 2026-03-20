// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceInsert",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "VoiceInsert",
            targets: ["VoiceInsertApp"]
        ),
        .executable(
            name: "VoiceInsertInjector",
            targets: ["VoiceInsertInjector"]
        )
    ],
    targets: [
        .executableTarget(
            name: "VoiceInsertApp"
        ),
        .executableTarget(
            name: "VoiceInsertInjector"
        )
    ]
)
