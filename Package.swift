// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClipFlow",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClipFlow",
            path: "Sources/ClipFlow"
        )
    ]
)
