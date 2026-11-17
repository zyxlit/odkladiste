// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Odkladiste",
    defaultLocalization: "cs",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "OdkladisteCore", targets: ["OdkladisteCore"]),
        .executable(name: "Odkladiste", targets: ["Odkladiste"])
    ],
    targets: [
        .target(
            name: "OdkladisteCore",
            path: "Sources/OdkladisteCore"
        ),
        .executableTarget(
            name: "Odkladiste",
            dependencies: ["OdkladisteCore"],
            path: "Sources/Odkladiste",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "OdkladisteCoreTests",
            dependencies: ["OdkladisteCore"],
            path: "Tests/OdkladisteCoreTests"
        )
    ]
)
