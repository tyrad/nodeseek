//
//  DetailInlineImageView.swift
//  nodeseek
//
//  Created by Codex on 2026/4/30.
//

import Kingfisher
import OSLog
import UIKit

final class DetailInlineImageView: AnimatedImageView {
    private static let logger = Logger(subsystem: "com.nodeseek.app", category: "DetailInlineImageView")

    private let imageURL: URL
    private let targetPixelWidth: CGFloat
    private let displayScale: CGFloat
    private let allowsInlineAnimation: Bool
    private let usesDetailImageOptimization: Bool
    private let onImageLoaded: (URL, CGSize) -> Void
    private let onImageTapped: (URL) -> Void
    private var loadToken: UUID?
    private let diagnosticID = String(UUID().uuidString.prefix(8))

    init(
        frame: CGRect,
        imageURL: URL,
        targetPixelWidth: CGFloat,
        displayScale: CGFloat,
        allowsInlineAnimation: Bool,
        usesDetailImageOptimization: Bool,
        onImageLoaded: @escaping (URL, CGSize) -> Void,
        onImageTapped: @escaping (URL) -> Void
    ) {
        self.imageURL = imageURL
        self.targetPixelWidth = targetPixelWidth
        self.displayScale = displayScale
        self.allowsInlineAnimation = allowsInlineAnimation
        self.usesDetailImageOptimization = usesDetailImageOptimization
        self.onImageLoaded = onImageLoaded
        self.onImageTapped = onImageTapped
        super.init(frame: frame)
        autoPlayAnimatedImage = true
        framePreloadCount = 6
        needsPrescaling = true
        purgeFramesOnBackground = true
        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()

        guard superview != nil else {
            logDiagnostics("removed url=\(imageURL.absoluteString) frame=\(Self.string(from: frame))")
            loadToken = nil
            kf.cancelDownloadTask()
            purgeFrames()
            return
        }
        guard loadToken == nil else { return }

        let token = UUID()
        loadToken = token
        logDiagnostics(
            "startLoad url=\(imageURL.absoluteString) frame=\(Self.string(from: frame)) targetPixelWidth=\(Self.numberString(targetPixelWidth)) displayScale=\(Self.numberString(displayScale))"
        )

        if shouldUseAnimatedInlineLoader {
            loadAnimatedImage(token: token)
            return
        }

        DetailImageLoader.shared.loadImageForInline(
            imageURL,
            maxPixelWidth: targetPixelWidth,
            displayScale: displayScale,
            allowsOptimization: usesDetailImageOptimization
        ) { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.loadToken == token else { return }
                self.image = image
                if let image {
                    self.logDiagnostics(
                        "loaded url=\(self.imageURL.absoluteString) imageSize=\(Self.string(from: image.size)) frame=\(Self.string(from: self.frame))"
                    )
                    self.onImageLoaded(self.imageURL, image.size)
                } else {
                    self.logDiagnostics("loaded nil url=\(self.imageURL.absoluteString)")
                }
            }
        }
    }

    private var shouldUseAnimatedInlineLoader: Bool {
        allowsInlineAnimation && imageURL.pathExtension.lowercased() == "gif"
    }

    private func loadAnimatedImage(token: UUID) {
        guard let resolvedURL = AvatarImageLoader.resolveImageURL(imageURL) else {
            logDiagnostics("animatedLoad invalidURL url=\(imageURL.absoluteString)")
            return
        }

        logDiagnostics("animatedLoad start url=\(resolvedURL.absoluteString)")
        kf.setImage(
            with: resolvedURL,
            options: [
                .requestModifier(AnyModifier { request in
                    var modifiedRequest = request
                    WebRequestFingerprint.applyImageHeaders(to: &modifiedRequest)
                    return modifiedRequest
                })
            ]
        ) { [weak self] result in
            guard let self, self.loadToken == token else { return }
            switch result {
            case .success(let value):
                self.logDiagnostics(
                    "animatedLoad loaded url=\(resolvedURL.absoluteString) imageSize=\(Self.string(from: value.image.size)) frame=\(Self.string(from: self.frame))"
                )
                self.onImageLoaded(self.imageURL, value.image.size)
            case .failure(let error):
                self.logDiagnostics(
                    "animatedLoad failed url=\(resolvedURL.absoluteString) error=\(error.localizedDescription)"
                )
            }
        }
    }

    @objc
    private func handleTap() {
        onImageTapped(imageURL)
    }

    private func logDiagnostics(_ message: String) {
        guard NodeSeekDebugConfig.enableDetailRenderDiagnostics else { return }
        Self.logger.info("[\(self.diagnosticID, privacy: .public)] \(message, privacy: .public)")
    }

    private static func string(from rect: CGRect) -> String {
        "x=\(numberString(rect.origin.x)),y=\(numberString(rect.origin.y)),w=\(numberString(rect.width)),h=\(numberString(rect.height))"
    }

    private static func string(from size: CGSize) -> String {
        "\(numberString(size.width))x\(numberString(size.height))"
    }

    private static func numberString(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}
