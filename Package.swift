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
            path: "nodeseek/Core",
            exclude: [
                "Imaging",
                "UI",
                "NodeSeekService.swift",
                "Networking/CookieBridge.swift",
                "Networking/HiddenWebViewCommentSubmissionClient.swift",
                "Networking/HiddenWebViewHTMLClient.swift",
                "Networking/HTTPHTMLClient.swift",
                "Networking/LoginWebViewController.swift",
                "Networking/NodeSeekCommentSubmitter.swift",
                "Networking/NodeSeekDebugConfig.swift",
                "Rendering/DTCoreTextHTMLContentRenderer.swift",
                "Rendering/HTMLContentRenderer.swift",
                "Rendering/RenderedContentBlock.swift"
            ],
            sources: [
                "Domain",
                "Parsing",
                "Networking/HTMLClient.swift",
                "Networking/FormURLEncoder.swift",
                "Networking/ChallengeDetector.swift",
                "Networking/WebRequestFingerprint.swift",
                "CommentComposerContentBuilder.swift",
                "Rendering/DetailImageLayout.swift"
            ]
        ),
        .testTarget(
            name: "NodeSeekCoreTests",
            dependencies: [
                "NodeSeekCore"
            ],
            path: "nodeseekTests",
            exclude: [
                "App",
                "ArchitectureSkeletonTests.swift",
                "Core/ChallengeSessionStoreTests.swift",
                "Core/CookieBridgeTests.swift",
                "Core/DTCoreTextHTMLContentRendererTests.swift",
                "Core/HTMLContentRendererTests.swift",
                "Core/LoginWebViewControllerTests.swift",
                "Core/NodeSeekCommentSubmitterTests.swift",
                "Core/NodeSeekServiceTests.swift",
                "Core/SwiftDrawPerformanceTests.swift",
                "Features",
                "nodeseekTests.swift"
            ],
            sources: [
                "Core/KannaNodeSeekParserTests.swift",
                "Core/ChallengeDetectorTests.swift",
                "Core/DetailImageLayoutTests.swift",
                "Core/CommentComposerContentBuilderTests.swift"
            ],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
