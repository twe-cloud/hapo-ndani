// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppInference",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "AppInference", targets: ["AppInference"]),
    ],
    dependencies: [
        .package(path: "../AppCore"),
        .package(url: "https://github.com/mattt/llama.swift.git", from: "2.8929.0"),
    ],
    targets: [
        .target(
            name: "AppInference",
            dependencies: [
                .product(name: "AppCore", package: "AppCore"),
                .product(name: "LlamaSwift", package: "llama.swift"),
            ]
        ),
    ]
)
