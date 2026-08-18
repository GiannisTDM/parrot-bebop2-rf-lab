// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ParrotLab",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ParrotLab", targets: ["ParrotLab"])
    ],
    targets: [
        .executableTarget(
            name: "ParrotLab",
            path: "Sources/ParrotLab",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
