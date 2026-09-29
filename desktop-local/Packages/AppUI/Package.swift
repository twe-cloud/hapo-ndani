// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppUI",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "AppUI", targets: ["AppUI"]),
    ],
    dependencies: [
        .package(path: "../AppCore"),
        .package(path: "../AppDocuments"),
        .package(path: "../AppIntegrations"),
    ],
    targets: [
        .target(
            name: "AppUI",
            dependencies: [
                .product(name: "AppCore", package: "AppCore"),
                .product(name: "AppDocuments", package: "AppDocuments"),
                .product(name: "AppIntegrations", package: "AppIntegrations"),
            ]
        ),
    ]
)

