// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tessera",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "TesseraCore",
            targets: ["TesseraCore"]
        ),
        .executable(
            name: "Tessera",
            targets: ["Tessera"]
        ),
        .executable(
            name: "tessera-cli",
            targets: ["tessera-cli"]
        )
    ],
    targets: [
        .target(
            name: "TesseraCore",
            path: "Sources/TesseraCore"
        ),
        .executableTarget(
            name: "Tessera",
            dependencies: ["TesseraCore"],
            path: "Sources/Tessera"
        ),
        .executableTarget(
            name: "tessera-cli",
            dependencies: ["TesseraCore"],
            path: "Sources/tessera-cli"
        ),
        .testTarget(
            name: "TesseraCoreTests",
            dependencies: ["TesseraCore"],
            path: "Tests/TesseraCoreTests"
        )
    ]
)
