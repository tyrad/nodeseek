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
            path: ".",
            sources: [
                "nodeseek/Core/Domain",
                "nodeseek/Core/Parsing",
                "nodeseek/Core/Networking/HTMLClient.swift",
                "nodeseek/Core/Networking/HTTPHTMLClient.swift",
                "nodeseek/Core/Networking/FormURLEncoder.swift",
                "nodeseek/Core/Networking/ChallengeDetector.swift",
                "nodeseek/Core/Networking/NodeSeekCommentSubmitter.swift",
                "nodeseek/Core/Networking/WebRequestFingerprint.swift",
                "nodeseek/Core/NodeSeekService.swift",
                "nodeseek/Core/CommentComposerContentBuilder.swift",
                "nodeseek/Core/Rendering/DetailImageLayout.swift"
            ]
        ),
        .testTarget(
            name: "NodeSeekCoreTests",
            dependencies: [
                "NodeSeekCore"
            ],
            path: ".",
            sources: [
                "nodeseekTests/Core/KannaNodeSeekParserTests.swift",
                "nodeseekTests/Core/ChallengeDetectorTests.swift",
                "nodeseekTests/Core/DetailImageLayoutTests.swift",
                "nodeseekTests/Core/NodeSeekServiceTests.swift",
                "nodeseekTests/Core/NodeSeekCommentSubmitterTests.swift",
                "nodeseekTests/Core/CommentComposerContentBuilderTests.swift"
            ],
            resources: [
                .copy("nodeseekTests/Fixtures")
            ]
        )
    ]
)
