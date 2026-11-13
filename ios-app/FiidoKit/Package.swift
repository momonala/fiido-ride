// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FiidoKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "FiidoKit", targets: ["FiidoKit"]),
        .executable(name: "fiido-convert", targets: ["FiidoConvert"]),
    ],
    targets: [
        .target(name: "FiidoKit"),
        .executableTarget(name: "FiidoConvert", dependencies: ["FiidoKit"]),
        .testTarget(name: "FiidoKitTests", dependencies: ["FiidoKit"]),
    ]
)
