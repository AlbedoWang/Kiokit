// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KiokitCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KiokitCore", targets: ["KiokitCore"]),
        .executable(name: "AnkiProbe", targets: ["AnkiProbe"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
    ],
    targets: [
        .binaryTarget(name: "AnkiBackendFFI", path: "AnkiBackendFFI.xcframework"),
        .target(name: "KiokitCore", dependencies: [
            "AnkiBackendFFI",
            .product(name: "ZIPFoundation", package: "ZIPFoundation"),
        ], resources: [.process("Resources/en.lproj"), .process("Resources/zh-Hans.lproj"), .copy("Resources/AnkiWeb"), .copy("Resources/Licenses")], linkerSettings: [
            .linkedFramework("Security"),
            .linkedFramework("SystemConfiguration"),
            .linkedLibrary("resolv"),
            .linkedLibrary("c++"),
        ]),
        .testTarget(name: "KiokitCoreTests", dependencies: ["KiokitCore"], resources: [.copy("Fixtures")]),
        .executableTarget(name: "AnkiProbe", dependencies: ["KiokitCore"]),
    ]
)
