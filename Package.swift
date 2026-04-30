// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NodeSeek",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "NodeSeekCore", targets: ["NodeSeekCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/tid-kijyun/Kanna.git", exact: "6.1.0")
    ],
    targets: [
        .target(
            name: "NodeSeekCore",
            dependencies: [
                "Kanna"
            ],
            path: "nodeseek/SharedCore"
        ),
        .testTarget(
            name: "NodeSeekCoreTests",
            dependencies: [
                "NodeSeekCore"
            ],
            path: "nodeseekTests",
            sources: [
                "SharedCore"
            ],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
