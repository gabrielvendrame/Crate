// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DJKit",
    platforms: [.macOS(.v14)],
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
