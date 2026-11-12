// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "woot-push",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.20.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
    ],
    targets: [
        .target(name: "PushRelay", dependencies: [
            .product(name: "Hummingbird", package: "hummingbird"),
            .product(name: "AsyncHTTPClient", package: "async-http-client"),
            .product(name: "Crypto", package: "swift-crypto"),
        ]),
        .executableTarget(name: "woot-push", dependencies: ["PushRelay"]),
        .testTarget(name: "PushRelayTests", dependencies: [
            "PushRelay",
            .product(name: "HummingbirdTesting", package: "hummingbird"),
        ]),
    ]
)
