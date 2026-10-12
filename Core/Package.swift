// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenAnkiCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "OpenAnkiCore", targets: ["OpenAnkiCore"])],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
        .package(url: "https://github.com/facebook/zstd.git", exact: "1.5.7"),
    ],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(name: "OpenAnkiCore", dependencies: [
            "CSQLite",
            .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            .product(name: "libzstd", package: "zstd"),
        ], resources: [.process("Resources")]),
        .testTarget(name: "OpenAnkiCoreTests", dependencies: ["OpenAnkiCore"], resources: [.copy("Fixtures")]),
    ]
)
