// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Bolt",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Bolt",
            path: "Sources/Bolt"
        )
    ]
)
