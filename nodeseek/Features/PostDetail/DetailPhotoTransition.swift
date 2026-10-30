//
//  DetailPhotoTransition.swift
//  nodeseek
//

import JXPhotoBrowser
import UIKit

/// 详情里能作为看大图缩放起点的图片。
protocol DetailPhotoThumbnailSource: AnyObject {
    var detailPhotoThumbnailURL: URL? { get }
    var detailPhotoThumbnailView: UIImageView { get }
}

/// 点击瞬间记下的那张图。图库可能稍后才打开，用它避免缩到同一地址的另一张上。
enum DetailPhotoTransitionAnchor {
    private static weak var imageView: UIImageView?
    private static var url: URL?

    static func record(imageView: UIImageView, url: URL) {
        self.imageView = imageView
        self.url = url
    }

    static func take() -> (imageView: UIImageView, url: URL)? {
        defer {
            imageView = nil
            url = nil
        }
        guard let imageView, let url else { return nil }
        return (imageView, url)
    }
}

enum DetailPhotoThumbnailFinder {
    static func thumbnail(
        matching url: URL,
        in root: UIView?,
        anchorView: UIImageView?,
        anchorURL: URL?
    ) -> UIImageView? {
        let target = canonical(url)
        if let anchorView, let anchorURL, canonical(anchorURL) == target,
           isUsable(anchorView), stillShows(anchorView, url: target) {
            return anchorView
        }
        guard let root else { return nil }
        let matches = sources(in: root).compactMap { source -> UIImageView? in
            guard let sourceURL = source.detailPhotoThumbnailURL, canonical(sourceURL) == target else { return nil }
            let view = source.detailPhotoThumbnailView
            return isUsable(view) ? view : nil
        }
        if let anchorView, let cell = enclosingCell(of: anchorView),
           let sameCell = matches.first(where: { $0.isDescendant(of: cell) }) {
            return sameCell
        }
        return matches.first
    }

    private static func canonical(_ url: URL) -> String {
        ImageURLResolver.resolve(url)?.absoluteString ?? url.absoluteString
    }

    /// 点击后图库可能才打开。视图若已换成别的图，就不再拿它当起点。
    private static func stillShows(_ view: UIImageView, url: String) -> Bool {
        var current: UIView? = view
        while let candidate = current {
            if let source = candidate as? DetailPhotoThumbnailSource,
               source.detailPhotoThumbnailView === view,
               let sourceURL = source.detailPhotoThumbnailURL,
               canonical(sourceURL) == url {
                return true
            }
            current = candidate.superview
        }
        return false
    }

    /// 转场时源图会被藏起来。不能因为 isHidden 就丢掉它，否则关闭时缩不回去。
    private static func isUsable(_ view: UIImageView) -> Bool {
        guard view.image != nil,
              view.bounds.width > 1,
              view.bounds.height > 1,
              let window = view.window else { return false }
        return view.convert(view.bounds, to: window).intersects(window.bounds)
    }

    private static func enclosingCell(of view: UIView) -> UIView? {
        var current = view.superview
        while let view = current {
            if view is UITableViewCell || view is UICollectionViewCell {
                return view
            }
            current = view.superview
        }
        return nil
    }

    private static func sources(in view: UIView) -> [DetailPhotoThumbnailSource] {
        var result: [DetailPhotoThumbnailSource] = []
        if let source = view as? DetailPhotoThumbnailSource {
            result.append(source)
        }
        for subview in view.subviews {
            result.append(contentsOf: sources(in: subview))
        }
        return result
    }
}

enum DetailPhotoTransitionTiming {
    /// 库默认 0.25 秒，进出大图再短一截。
    static let duration: TimeInterval = 0.18
}

/// 关闭前按当前页决定缩放或淡出，离开后保证源图不会一直藏着。
final class DetailPhotoBrowserController: JXPhotoBrowserViewController {
    var prepareForDismiss: (() -> Void)?
    var onDidLeave: (() -> Void)?

    override func dismissSelf() {
        prepareForDismiss?()
        super.dismissSelf()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil {
            onDidLeave?()
        }
    }

    override func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        switch transitionType {
        case .fade: return DetailPhotoFadeAnimator(isPresenting: true)
        case .zoom: return DetailPhotoZoomPresentAnimator()
        case .none: return super.animationController(forPresented: presented, presenting: presenting, source: source)
        }
    }

    override func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        switch transitionType {
        case .fade: return DetailPhotoFadeAnimator(isPresenting: false)
        case .zoom: return DetailPhotoZoomDismissAnimator()
        case .none: return super.animationController(forDismissed: dismissed)
        }
    }
}

private final class DetailPhotoZoomPresentAnimator: JXZoomPresentAnimator {
    override func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval {
        DetailPhotoTransitionTiming.duration
    }
}

private final class DetailPhotoZoomDismissAnimator: JXZoomDismissAnimator {
    override func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval {
        DetailPhotoTransitionTiming.duration
    }
}

private final class DetailPhotoFadeAnimator: JXFadeAnimator {
    override func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval {
        DetailPhotoTransitionTiming.duration
    }
}
