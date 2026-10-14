// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Notepad",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Notepad",
            path: "Sources/Notepad"
        )
    ]
)
