// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppIntegrations",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "AppIntegrations", targets: ["AppIntegrations"]),
    ],
    targets: [
        .target(name: "AppIntegrations"),
    ]
)

