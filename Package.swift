// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AlpBrowser",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AlpBrowser", targets: ["AlpBrowser"])
    ],
    targets: [
        .executableTarget(
            name: "AlpBrowser",
            path: "Sources/AlpBrowser"
        ),
        .testTarget(
            name: "AlpBrowserTests",
            path: "Tests/AlpBrowserTests"
        )
    ]
)
