// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppDocuments",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "AppDocuments", targets: ["AppDocuments"]),
    ],
    targets: [
        .target(name: "AppDocuments"),
        .testTarget(name: "AppDocumentsTests", dependencies: ["AppDocuments"]),
    ]
)

