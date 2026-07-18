// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Spot",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Spot",
            path: "Sources/Spot"
        )
    ]
)
