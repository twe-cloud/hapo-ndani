// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppTesting",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "AppTesting", targets: ["AppTesting"]),
    ],
    dependencies: [
        .package(path: "../AppCore"),
    ],
    targets: [
        .target(
            name: "AppTesting",
            dependencies: [
                .product(name: "AppCore", package: "AppCore"),
            ]
        ),
    ]
)

