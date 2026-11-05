// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ArcBrowser",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ArcBrowser", targets: ["ArcBrowser"])
    ],
    targets: [
        .executableTarget(
            name: "ArcBrowser",
            path: "Sources/ArcBrowser"
        )
    ]
)
