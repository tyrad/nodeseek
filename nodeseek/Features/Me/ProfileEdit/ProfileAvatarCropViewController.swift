//
//  ProfileAvatarCropViewController.swift
//  nodeseek
//

import UIKit

/// 方形裁剪：拖动、双指缩放，把要保留的部分放进圆圈里。
final class ProfileAvatarCropViewController: UIViewController, UIScrollViewDelegate {
    /// 和网页裁剪组件的输出一致。
    static let outputSize = CGSize(width: 100, height: 100)

    private let image: UIImage
    private let onCrop: (UIImage) -> Void
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let maskLayer = CAShapeLayer()
    private let dimView = UIView()
    private var cropRect: CGRect = .zero
    private var lastLayoutSize: CGSize = .zero

    init(image: UIImage, onCrop: @escaping (UIImage) -> Void) {
        self.image = Self.normalized(image)
        self.onCrop = onCrop
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        // 看图片的界面固定用深色，不受系统外观影响。
        overrideUserInterfaceStyle = .dark
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scrollView)

        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: image.size)
        scrollView.addSubview(imageView)
        scrollView.contentSize = image.size

        dimView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.6)
        dimView.isUserInteractionEnabled = false
        dimView.frame = view.bounds
        dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        maskLayer.fillRule = .evenOdd
        dimView.layer.mask = maskLayer
        view.addSubview(dimView)

        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("移动和缩放", tableName: "Me", comment: "")
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let cancelButton = makeButton(title: NSLocalizedString("取消", tableName: "Me", comment: ""), filled: false) { [weak self] in
            self?.dismiss(animated: true)
        }
        let chooseButton = makeButton(title: NSLocalizedString("选取", tableName: "Me", comment: ""), filled: true) { [weak self] in
            self?.finishCropping()
        }
        chooseButton.accessibilityIdentifier = "avatar-crop-choose"
        let buttons = UIStackView(arrangedSubviews: [cancelButton, UIView(), chooseButton])
        buttons.alignment = .center
        buttons.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttons)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            buttons.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            buttons.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.size != lastLayoutSize else { return }
        lastLayoutSize = view.bounds.size
        let safe = view.bounds.inset(by: view.safeAreaInsets)
        let side = min(safe.width - 32, safe.height - 160)
        cropRect = CGRect(x: safe.midX - side / 2, y: safe.midY - side / 2, width: side, height: side)

        let path = UIBezierPath(rect: view.bounds)
        path.append(UIBezierPath(ovalIn: cropRect))
        maskLayer.path = path.cgPath

        // 内边距让图片的任一边都能拖到裁剪框边上。
        scrollView.contentInset = UIEdgeInsets(
            top: cropRect.minY,
            left: cropRect.minX,
            bottom: view.bounds.height - cropRect.maxY,
            right: view.bounds.width - cropRect.maxX
        )
        let minScale = max(side / image.size.width, side / image.size.height)
        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = max(minScale * 6, 1)
        scrollView.zoomScale = minScale
        // 初始居中。
        let contentSize = CGSize(width: image.size.width * minScale, height: image.size.height * minScale)
        scrollView.contentOffset = CGPoint(
            x: (contentSize.width - side) / 2 - cropRect.minX,
            y: (contentSize.height - side) / 2 - cropRect.minY
        )
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    private func finishCropping() {
        let cropped = Self.crop(image, to: view.convert(cropRect, to: imageView))
        dismiss(animated: true) { [onCrop] in onCrop(cropped) }
    }

    /// rect 是原图坐标（点）；输出固定尺寸，倍率为 1，像素数和网页上传的一致。
    static func crop(_ image: UIImage, to rect: CGRect) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        return renderer.image { context in
            // 图片没铺满时（理论上不会）补白，和网页组件的默认底色一致。
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: outputSize))
            let scale = outputSize.width / max(rect.width, 1)
            image.draw(in: CGRect(
                x: -rect.minX * scale,
                y: -rect.minY * scale,
                width: image.size.width * scale,
                height: image.size.height * scale
            ))
        }
    }

    /// 统一成朝上的图片，并把超大原图缩小，裁剪时省内存。
    private static func normalized(_ image: UIImage) -> UIImage {
        let maxSide: CGFloat = 2048
        let ratio = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func makeButton(title: String, filled: Bool, action: @escaping () -> Void) -> UIButton {
        var configuration = filled ? UIButton.Configuration.filled() : UIButton.Configuration.plain()
        configuration.title = title
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .label
        configuration.baseForegroundColor = filled ? .systemBackground : .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
        return UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
    }
}
