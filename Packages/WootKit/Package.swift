// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WootKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "ChatwootModels", targets: ["ChatwootModels"]),
        .library(name: "ChatwootAPI", targets: ["ChatwootAPI"]),
        .library(name: "ChatwootRealtime", targets: ["ChatwootRealtime"]),
    ],
    targets: [
        .target(name: "ChatwootModels"),
        .target(name: "ChatwootAPI", dependencies: ["ChatwootModels"]),
        .target(name: "ChatwootRealtime", dependencies: ["ChatwootModels"]),
        .testTarget(
            name: "WootKitTests",
            dependencies: ["ChatwootModels", "ChatwootAPI", "ChatwootRealtime"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
