// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "monkeys",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "monkeys",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ]
        ),
        .testTarget(name: "MonkeysTests", dependencies: ["monkeys"]),
    ]
)
