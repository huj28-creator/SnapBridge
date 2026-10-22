// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SnapBridgeCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "SnapBridgeCore", targets: ["SnapBridgeCore"])],
    targets: [
        .target(name: "SnapBridgeCore", path: "Shared", exclude: ["KeychainStore.swift", "NearbyTransport.swift"], sources: ["WireProtocol.swift", "PhotoStore.swift", "PhotoProcessing.swift", "PerformanceTrace.swift", "FastPhotoChannel.swift", "PhotoBatch.swift"]),
        .testTarget(name: "SnapBridgeCoreTests", dependencies: ["SnapBridgeCore"])
    ]
)
