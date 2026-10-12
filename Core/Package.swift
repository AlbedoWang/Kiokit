// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenAnkiCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OpenAnkiCore", targets: ["OpenAnkiCore"]),
        .executable(name: "AnkiProbe", targets: ["AnkiProbe"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
    ],
    targets: [
        .binaryTarget(name: "AnkiBackendFFI", path: "AnkiBackendFFI.xcframework"),
        .target(name: "OpenAnkiCore", dependencies: [
            "AnkiBackendFFI",
            .product(name: "ZIPFoundation", package: "ZIPFoundation"),
        ], resources: [.process("Resources/en.lproj"), .process("Resources/zh-Hans.lproj"), .copy("Resources/AnkiWeb"), .copy("Resources/Licenses")], linkerSettings: [
            .linkedFramework("Security"),
            .linkedFramework("SystemConfiguration"),
            .linkedLibrary("resolv"),
            .linkedLibrary("c++"),
        ]),
        .testTarget(name: "OpenAnkiCoreTests", dependencies: ["OpenAnkiCore"], resources: [.copy("Fixtures")]),
        .executableTarget(name: "AnkiProbe", dependencies: ["OpenAnkiCore"]),
    ]
)
