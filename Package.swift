// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InputStats",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "InputStats",
            path: "Sources/InputStats"
        )
    ]
)
