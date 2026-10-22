// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FramePlay",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [.library(name: "FramePlay", targets: ["FramePlay"])],
    targets: [
        .target(name: "FramePlay"),
        .testTarget(name: "FramePlayTests", dependencies: ["FramePlay"], resources: [.copy("Fixtures")]),
    ]
)
