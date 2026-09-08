import AsyncDisplayKit
import UIKit

final class DetailVoteNode: ASDisplayNode {
    private let sizeLock = NSLock()
    private var contentHeight: CGFloat = 160

    init(id: Int, service: NodeSeekVoteServing? = nil, onLayoutInvalidated: @escaping () -> Void) {
        super.init()
        setViewBlock { [weak self] in
            DetailVoteView(id: id, service: service, onHeightChanged: { height in
                guard let self else { return }
                self.sizeLock.lock()
                let changed = abs(self.contentHeight - height) > 0.5
                self.contentHeight = height
                self.sizeLock.unlock()
                if changed {
                    // 自定义 UIView 不会自动向 Texture 父节点传递尺寸变化。
                    // 必须一路作废到单元格，否则列表重排仍会命中正文的旧高度。
                    var ancestor: ASDisplayNode? = self
                    while let node = ancestor {
                        node.setNeedsLayout()
                        if node is ASCellNode { break }
                        ancestor = node.supernode
                    }
                    onLayoutInvalidated()
                }
            })
        }
        style.flexShrink = 1
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        sizeLock.lock()
        let height = contentHeight
        sizeLock.unlock()
        return CGSize(width: constrainedSize.width.isFinite ? constrainedSize.width : 320, height: height)
    }
}

@MainActor
final class DetailVoteView: UIView {
    let model: VoteViewModel
    private let stack = UIStackView()
    private let onHeightChanged: (CGFloat) -> Void
    private var lastHeight: CGFloat = 0
    private var confirming = false

    init(id: Int, service: NodeSeekVoteServing? = nil, onHeightChanged: @escaping (CGFloat) -> Void) {
        model = VoteViewModel(id: id, service: service ?? NodeSeekVoteService.shared)
        self.onHeightChanged = onHeightChanged
        super.init(frame: .zero)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 10
        clipsToBounds = true
        stack.axis = .vertical
        stack.spacing = 10
        addSubview(stack)
        accessibilityIdentifier = "detail-vote-\(id)"
        model.onChange = { [weak self] in self?.updateContent() }
        updateContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        model.setVisible(window != nil)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            updateContent()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 24 else { return }
        let size = stack.systemLayoutSizeFitting(
            CGSize(width: bounds.width - 24, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        )
        stack.frame = CGRect(x: 12, y: 12, width: bounds.width - 24, height: size.height)
        let height = ceil(size.height + 24)
        if abs(lastHeight - height) > 0.5 {
            lastHeight = height
            onHeightChanged(height)
        }
    }

    private func label(_ text: String, style: UIFont.TextStyle, color: UIColor = .label) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: style, compatibleWith: traitCollection)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private func button(_ title: String, identifier: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.title = title
        config.titleLineBreakMode = .byWordWrapping
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 8, bottom: 10, trailing: 8)
        let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = font
            return outgoing
        }
        button.configuration = config
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.contentHorizontalAlignment = .leading
        button.accessibilityIdentifier = identifier
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func updateContent() {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        stack.addArrangedSubview(label(model.vote?.title ?? "投票 #\(model.id)", style: .headline))
        if let vote = model.vote {
            let mode = "\(vote.isPublic ? "公开" : "匿名") · \(vote.multiple ? "多选" : "单选")"
            stack.addArrangedSubview(label(mode + (vote.locked ? " · 已锁定" : ""), style: .caption1, color: .secondaryLabel))
            for item in vote.items {
                let selected = model.selected.contains(item.vote_item_id)
                let option = button(item.text, identifier: "vote-option-\(item.vote_item_id)") { [weak self] in
                    self?.model.select(item.vote_item_id)
                }
                let symbol = vote.multiple ? (selected ? "checkmark.square.fill" : "square") : (selected ? "largecircle.fill.circle" : "circle")
                option.configuration?.image = UIImage(systemName: symbol)
                option.configuration?.imagePadding = 10
                option.configuration?.baseForegroundColor = .label
                // 已投票的选项仍保持可读，不采用禁用按钮的浅色文字。
                option.isUserInteractionEnabled = !model.busy && !model.requiresRefresh && vote.canSubmit
                option.accessibilityTraits = selected ? [.button, .selected] : [.button]
                if !option.isUserInteractionEnabled { option.accessibilityTraits.insert(.notEnabled) }
                stack.addArrangedSubview(option)
                if vote.hasVoted, let count = item.count {
                    stack.addArrangedSubview(label("\(count) 票", style: .caption1, color: .secondaryLabel))
                }
            }
            if vote.canSubmit {
                stack.addArrangedSubview(label(vote.isPublic ? "公开投票，选择可被他人查看。提交后不可修改。" : "提交后不可修改。", style: .caption1, color: .secondaryLabel))
                let submit = button("提交投票", identifier: "vote-submit") { [weak self] in self?.confirmSubmission() }
                submit.configuration?.background.backgroundColor = .tertiarySystemFill
                submit.contentHorizontalAlignment = .center
                submit.isEnabled = model.canSubmit && !confirming
                stack.addArrangedSubview(submit)
            }
        }
        if let message = model.message ?? (model.busy ? "正在加载投票…" : (model.vote?.hasVoted == true ? "已投票" : nil)) {
            let status = label(message, style: .footnote, color: .secondaryLabel)
            status.accessibilityIdentifier = "vote-status"
            stack.addArrangedSubview(status)
        }
        setNeedsLayout()
    }

    private func confirmSubmission() {
        guard !confirming, model.canSubmit, let vote = model.vote,
              let controller = owningViewController(), controller.presentedViewController == nil else { return }
        confirming = true
        let choices = vote.items.filter { model.selected.contains($0.vote_item_id) }.map(\.text).joined(separator: "、")
        let alert = UIAlertController(title: "确认提交投票？", message: "已选择：\(choices)\n\(vote.isPublic ? "公开投票，选择可被他人查看。" : "")提交后不可修改。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            self?.confirming = false
            self?.updateContent()
        })
        alert.addAction(UIAlertAction(title: "提交", style: .default) { [weak self] _ in
            guard let self else { return }
            self.confirming = false
            Task { await self.model.submit() }
        })
        controller.present(alert, animated: true)
        updateContent()
    }

    private func owningViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }

}
