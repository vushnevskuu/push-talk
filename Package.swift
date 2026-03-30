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
            targets: ["VoiceInsert"]
        ),
        .executable(
            name: "VoiceInsertInjector",
            targets: ["VoiceInsertInjector"]
        )
    ],
    targets: [
        .executableTarget(
            name: "VoiceInsert",
            path: "Sources/VoiceInsertApp"
        ),
        .executableTarget(
            name: "VoiceInsertInjector"
        )
    ]
)
