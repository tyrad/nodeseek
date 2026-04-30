//
//  PageScrubberView.swift
//  nodeseek
//
//  Created by Codex on 2026/4/29.
//

import UIKit

final class PageScrubberView: UIView {
    private enum Layout {
        static let minimumWidth: CGFloat = 58
        static let collapsedHeight: CGFloat = 42
        static let expandedHeight: CGFloat = 220
        static let cornerRadius: CGFloat = 14
        static let compactAlpha: CGFloat = 0.62
        static let activeAlpha: CGFloat = 1
        static let horizontalInset: CGFloat = 12
        static let loadingIndicatorSize: CGFloat = 16
        static let loadingIndicatorSpacing: CGFloat = 8
        static let trailingEdgeCompensation: CGFloat = 16
        static let hitTargetOutset: CGFloat = 8
        static let expandedCornerRadius: CGFloat = 18
        static let snapRatio: CGFloat = 0.08
        static let accelerationPower: CGFloat = 1.35
        static let hudMinimumWidth: CGFloat = 238
        static let hudHorizontalInset: CGFloat = 32
        static let hudVerticalOffset: CGFloat = 0
        static let tapHUDMinimumVisibleDuration: TimeInterval = 0.45
        static let titleFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
        static let hudSubtitleFont = UIFont.systemFont(ofSize: 12, weight: .medium)
    }

    var onPageSelected: ((Int) -> Void)?

    private var currentPage = 1
    private var totalPages = 1
    private var isLoading = false
    private var isScrubbing = false
    private var startPage = 1
    private var startY: CGFloat = 0
    private var startTouchY: CGFloat = 0
    private var candidatePage = 1
    private var hasMovedDuringScrub = false
    private var scrubSessionID = 0

    private let toggleButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let barView = UIView()
    private let hudView = UIView()
    private let hudTitleLabel = UILabel()
    private let hudSubtitleLabel = UILabel()
    private let feedbackGenerator = UISelectionFeedbackGenerator()
    private let touchDownFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    private var widthConstraint: NSLayoutConstraint?
    private var hudWidthConstraint: NSLayoutConstraint?
    private var hudPositionConstraints: [NSLayoutConstraint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        configure(currentPage: 1, totalPages: 1, isLoading: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(currentPage: Int, totalPages: Int, isLoading: Bool) {
        self.currentPage = max(1, currentPage)
        self.totalPages = max(self.currentPage, totalPages)
        self.isLoading = isLoading
        candidatePage = self.currentPage
        isHidden = self.totalPages <= 1
        alpha = isScrubbing ? Layout.activeAlpha : Layout.compactAlpha
        if self.totalPages <= 1 {
            endScrubbing(commitSelection: false, animated: false)
        }
        updateToggleButton()
        updateHUDText(page: candidatePage)
        updateAdaptiveWidths()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard superview != nil else {
            hudPositionConstraints.forEach { $0.isActive = false }
            hudPositionConstraints.removeAll()
            hudView.removeFromSuperview()
            return
        }
        installHUDInSuperviewIfNeeded()
        updateAdaptiveWidths()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateAdaptiveWidths()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isHidden == false, alpha > 0.01, isUserInteractionEnabled else { return false }
        return currentHitFrame().contains(point)
    }

    private func currentHitFrame() -> CGRect {
        let visibleFrame: CGRect
        if isScrubbing || barView.alpha > 0.01 {
            visibleFrame = effectiveTrackFrame()
        } else if toggleButton.frame.isEmpty == false {
            visibleFrame = toggleButton.frame
        } else {
            visibleFrame = CGRect(
                x: bounds.minX,
                y: bounds.midY - Layout.collapsedHeight / 2,
                width: bounds.width,
                height: Layout.collapsedHeight
            )
        }
        return visibleFrame.insetBy(dx: -Layout.hitTargetOutset, dy: -Layout.hitTargetOutset)
    }

    private func installHUDInSuperviewIfNeeded() {
        guard let superview else { return }
        guard hudView.superview !== superview else { return }

        hudPositionConstraints.forEach { $0.isActive = false }
        hudPositionConstraints.removeAll()
        hudView.removeFromSuperview()
        superview.addSubview(hudView)
        let constraints = [
            hudView.centerXAnchor.constraint(equalTo: superview.centerXAnchor),
            hudView.centerYAnchor.constraint(equalTo: superview.centerYAnchor, constant: Layout.hudVerticalOffset)
        ]
        hudPositionConstraints = constraints
        NSLayoutConstraint.activate(constraints)
        superview.bringSubviewToFront(hudView)
    }

    private func setupUI() {
        backgroundColor = .clear
        accessibilityIdentifier = "page-scrubber"
        translatesAutoresizingMaskIntoConstraints = false

        configureToggleButton()
        configureLoadingIndicator()
        configureBarView()
        configureHUDView()

        addSubview(barView)
        addSubview(toggleButton)
        addSubview(loadingIndicator)

        let widthConstraint = widthAnchor.constraint(equalToConstant: Layout.minimumWidth)
        self.widthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            widthConstraint,

            barView.leadingAnchor.constraint(equalTo: leadingAnchor),
            barView.trailingAnchor.constraint(equalTo: trailingAnchor),
            barView.centerYAnchor.constraint(equalTo: centerYAnchor),
            barView.heightAnchor.constraint(equalToConstant: Layout.expandedHeight),

            toggleButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            toggleButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            toggleButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggleButton.heightAnchor.constraint(equalToConstant: Layout.collapsedHeight),

            loadingIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.horizontalInset),
            loadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            loadingIndicator.widthAnchor.constraint(equalToConstant: Layout.loadingIndicatorSize),
            loadingIndicator.heightAnchor.constraint(equalToConstant: Layout.loadingIndicatorSize)
        ])
    }

    private func configureToggleButton() {
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .systemBackground
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        configuration.background.backgroundColor = .clear
        configuration.background.cornerRadius = Layout.cornerRadius
        configuration.cornerStyle = .fixed
        configuration.titleLineBreakMode = .byClipping
        toggleButton.configuration = configuration
        toggleButton.backgroundColor = .label
        toggleButton.titleLabel?.font = Layout.titleFont
        toggleButton.titleLabel?.numberOfLines = 1
        toggleButton.titleLabel?.lineBreakMode = .byClipping
        toggleButton.titleLabel?.adjustsFontSizeToFitWidth = true
        toggleButton.titleLabel?.minimumScaleFactor = 0.82
        toggleButton.accessibilityIdentifier = "page-scrubber-toggle-button"
        toggleButton.accessibilityLabel = "页码选择"
        toggleButton.layer.shadowColor = UIColor.black.cgColor
        toggleButton.layer.cornerRadius = Layout.cornerRadius
        toggleButton.layer.shadowOpacity = 0.18
        toggleButton.layer.shadowRadius = 12
        toggleButton.layer.shadowOffset = CGSize(width: 0, height: 5)
        toggleButton.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        toggleButton.isUserInteractionEnabled = false
        toggleButton.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureLoadingIndicator() {
        loadingIndicator.color = .systemBackground
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureBarView() {
        barView.backgroundColor = .label
        barView.layer.cornerRadius = Layout.expandedCornerRadius
        barView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        barView.layer.shadowColor = UIColor.black.cgColor
        barView.layer.shadowOpacity = 0.18
        barView.layer.shadowRadius = 12
        barView.layer.shadowOffset = CGSize(width: 0, height: 5)
        barView.alpha = 0
        barView.transform = CGAffineTransform(scaleX: 0.7, y: 0.92)
        barView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureHUDView() {
        hudView.backgroundColor = UIColor.label.withAlphaComponent(0.88)
        hudView.layer.cornerRadius = 18
        hudView.alpha = 0
        hudView.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        hudView.translatesAutoresizingMaskIntoConstraints = false

        hudTitleLabel.font = .systemFont(ofSize: 32, weight: .bold)
        hudTitleLabel.textColor = .systemBackground
        hudTitleLabel.textAlignment = .center
        hudTitleLabel.adjustsFontSizeToFitWidth = true
        hudTitleLabel.minimumScaleFactor = 0.7

        hudSubtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        hudSubtitleLabel.textColor = UIColor.systemBackground.withAlphaComponent(0.78)
        hudSubtitleLabel.textAlignment = .center
        hudSubtitleLabel.numberOfLines = 1
        hudSubtitleLabel.lineBreakMode = .byClipping
        hudSubtitleLabel.adjustsFontSizeToFitWidth = true
        hudSubtitleLabel.minimumScaleFactor = 0.72

        let stackView = UIStackView(arrangedSubviews: [hudTitleLabel, hudSubtitleLabel])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false
        hudView.addSubview(stackView)

        let hudWidthConstraint = hudView.widthAnchor.constraint(equalToConstant: Layout.hudMinimumWidth)
        self.hudWidthConstraint = hudWidthConstraint

        NSLayoutConstraint.activate([
            hudWidthConstraint,
            stackView.leadingAnchor.constraint(equalTo: hudView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: hudView.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: hudView.topAnchor, constant: 14),
            stackView.bottomAnchor.constraint(equalTo: hudView.bottomAnchor, constant: -14)
        ])
    }

    private func updateToggleButton() {
        var configuration = toggleButton.configuration ?? UIButton.Configuration.plain()
        configuration.title = "\(currentPage)/\(totalPages)"
        configuration.baseForegroundColor = isLoading ? .tertiaryLabel : .systemBackground
        configuration.background.backgroundColor = .clear
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 8,
            leading: Layout.horizontalInset,
            bottom: 8,
            trailing: isLoading
                ? Layout.horizontalInset + Layout.loadingIndicatorSize + Layout.loadingIndicatorSpacing
                : Layout.horizontalInset
        )
        toggleButton.configuration = configuration
        toggleButton.backgroundColor = isLoading ? .secondaryLabel : .label
        isLoading ? loadingIndicator.startAnimating() : loadingIndicator.stopAnimating()
    }

    private func updateHUDText(page: Int) {
        hudTitleLabel.text = "第 \(page) 页"
        hudSubtitleLabel.text = "手指滑动切换分页 1-\(totalPages)，松开确认"
        updateAdaptiveWidths()
    }

    private func updateAdaptiveWidths() {
        let title = "\(currentPage)/\(totalPages)" as NSString
        let textWidth = ceil(title.size(withAttributes: [.font: Layout.titleFont]).width)
        let loadingWidth = isLoading ? Layout.loadingIndicatorSize + Layout.loadingIndicatorSpacing : 0
        widthConstraint?.constant = max(
            Layout.minimumWidth,
            textWidth + Layout.horizontalInset * 2 + loadingWidth + Layout.trailingEdgeCompensation
        )

        let subtitle = hudSubtitleLabel.text ?? ""
        let subtitleWidth = ceil((subtitle as NSString).size(withAttributes: [.font: Layout.hudSubtitleFont]).width)
        let availableWidth = max(0, (superview?.bounds.width ?? UIScreen.main.bounds.width) - 96)
        hudWidthConstraint?.constant = min(
            max(Layout.hudMinimumWidth, subtitleWidth + Layout.hudHorizontalInset),
            availableWidth
        )
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let y = touches.first?.location(in: self).y else { return }
        beginScrubbing(at: y)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let y = touches.first?.location(in: self).y else { return }
        updateScrubbing(to: y)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let y = touches.first?.location(in: self).y {
            updateScrubbing(to: y)
        }
        endScrubbing(commitSelection: true, animated: true)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endScrubbing(commitSelection: false, animated: true)
    }

    private func beginScrubbing(at y: CGFloat) {
        guard totalPages > 1 else { return }
        guard isScrubbing == false else { return }
        scrubSessionID += 1
        isScrubbing = true
        startPage = currentPage
        startTouchY = y
        startY = clampedTrackY(y)
        candidatePage = currentPage
        hasMovedDuringScrub = false
        feedbackGenerator.prepare()
        touchDownFeedbackGenerator.prepare()
        touchDownFeedbackGenerator.impactOccurred()
        updateHUDText(page: candidatePage)
        setScrubbingAppearance(active: true, animated: false)
    }

    private func updateScrubbing(to y: CGFloat) {
        guard isScrubbing else { return }
        guard abs(y - startTouchY) > 2 else {
            return
        }
        hasMovedDuringScrub = true
        let nextPage = targetPage(for: y)
        guard nextPage != candidatePage else { return }
        candidatePage = nextPage
        updateHUDText(page: nextPage)
        feedbackGenerator.selectionChanged()
        feedbackGenerator.prepare()
    }

    private func endScrubbing(commitSelection: Bool, animated: Bool) {
        let selectedPage = candidatePage
        let sessionID = scrubSessionID
        let shouldDelayHUDDismissal = commitSelection && hasMovedDuringScrub == false
        let shouldSelect = commitSelection
            && isScrubbing
            && isLoading == false
            && selectedPage != currentPage
        isScrubbing = false
        if shouldDelayHUDDismissal {
            DispatchQueue.main.asyncAfter(deadline: .now() + Layout.tapHUDMinimumVisibleDuration) { [weak self] in
                guard let self, self.scrubSessionID == sessionID, self.isScrubbing == false else { return }
                self.setScrubbingAppearance(active: false, animated: animated)
            }
        } else {
            setScrubbingAppearance(active: false, animated: animated)
        }
        if shouldSelect {
            onPageSelected?(selectedPage)
        }
    }

    private func targetPage(for y: CGFloat) -> Int {
        let trackFrame = effectiveTrackFrame()
        let trackMinY = trackFrame.minY
        let trackHeight = trackFrame.height
        let clampedY = clampedTrackY(y)
        let positionRatio = (clampedY - trackMinY) / trackHeight
        if positionRatio <= Layout.snapRatio {
            return 1
        }
        if positionRatio >= 1 - Layout.snapRatio {
            return totalPages
        }

        let normalizedDistance = (clampedY - startY) / trackHeight
        let direction: CGFloat = normalizedDistance < 0 ? -1 : 1
        let accelerated = direction * pow(abs(normalizedDistance), Layout.accelerationPower)
        let pageDelta = Int(round(accelerated * CGFloat(totalPages)))
        return min(max(startPage + pageDelta, 1), totalPages)
    }

    private func effectiveTrackFrame() -> CGRect {
        guard barView.frame.height > 0 else {
            return CGRect(
                x: bounds.minX,
                y: bounds.midY - Layout.expandedHeight / 2,
                width: bounds.width,
                height: Layout.expandedHeight
            )
        }
        return barView.frame
    }

    private func clampedTrackY(_ y: CGFloat) -> CGFloat {
        let trackFrame = effectiveTrackFrame()
        return min(max(y, trackFrame.minY), trackFrame.maxY)
    }

    private func setScrubbingAppearance(active: Bool, animated: Bool) {
        let changes = {
            self.superview?.bringSubviewToFront(self.hudView)
            self.alpha = active ? Layout.activeAlpha : Layout.compactAlpha
            self.toggleButton.alpha = active ? 0 : 1
            self.loadingIndicator.alpha = active ? 0 : 1
            self.barView.alpha = active ? 1 : 0
            self.barView.transform = active ? .identity : CGAffineTransform(scaleX: 0.7, y: 0.92)
            self.hudView.alpha = active ? 1 : 0
            self.hudView.transform = active ? .identity : CGAffineTransform(scaleX: 0.96, y: 0.96)
        }
        guard animated else {
            changes()
            return
        }
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState],
            animations: changes
        )
    }
}

#if DEBUG
extension PageScrubberView {
    func beginScrubbingForTesting(at y: CGFloat) {
        beginScrubbing(at: y)
    }

    func updateScrubbingForTesting(to y: CGFloat) {
        updateScrubbing(to: y)
    }

    func endScrubbingForTesting(at y: CGFloat) {
        updateScrubbing(to: y)
        endScrubbing(commitSelection: true, animated: false)
    }
}
#endif
