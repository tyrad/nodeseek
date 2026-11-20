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
        .package(url: "https://github.com/tid-kijyun/Kanna.git", exact: "6.1.0"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.7.3")
    ],
    targets: [
        .target(
            name: "NodeSeekCore",
            dependencies: [
                "Kanna",
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "nodeseek/SharedCore"
        ),
        .testTarget(
            name: "NodeSeekCoreTests",
            dependencies: [
                "NodeSeekCore"
            ],
            path: "nodeseekTests",
            exclude: [
                "App",
                "AppRuntime",
                "Features"
            ],
            sources: [
                "SharedCore"
            ],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
