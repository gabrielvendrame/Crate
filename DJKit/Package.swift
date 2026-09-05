// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DJKit",
    // macOS 15 per `Synchronization.Atomic`, che è ciò con cui il render callback audio
    // comunica col main senza lock. L'app punta comunque a macOS 26.
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DJKit", targets: ["DJKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "DJKit",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DJKitTests",
            dependencies: ["DJKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
