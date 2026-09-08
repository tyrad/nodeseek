import AsyncDisplayKit
import UIKit

final class DetailMagicTabsNode: ASDisplayNode, ThemeRefreshableNode {
    let tabs: RenderedMagicTabsBlock
    private let makeContent: ([RenderedContentBlock], @escaping ([URL], Int) -> Void, @escaping () -> Void) -> [ASDisplayNode]
    let onImageTapped: ([URL], Int) -> Void
    var galleryTask: Task<Void, Never>?
    var galleryRequestID: UUID?
    var galleryLoadingView: DetailGalleryLoadingView?
    private let onLayoutInvalidated: () -> Void
    private let tabStrip = ASScrollNode()
    private let contentScroll = ASScrollNode()
    private var buttons: [ASButtonNode] = []
    private var sectionNodes: [Int: [ASDisplayNode]] = [:]
    private(set) var selectedIndex = 0
    private static let selections = NSCache<NSString, NSNumber>()
    private let themeObserver = ThemeTraitObserver()

    init(tabs: RenderedMagicTabsBlock, makeContent: @escaping ([RenderedContentBlock], @escaping ([URL], Int) -> Void, @escaping () -> Void) -> [ASDisplayNode], onImageTapped: @escaping ([URL], Int) -> Void, onLayoutInvalidated: @escaping () -> Void) {
        self.tabs = tabs
        self.makeContent = makeContent
        self.onImageTapped = onImageTapped
        self.onLayoutInvalidated = onLayoutInvalidated
        super.init()
        automaticallyManagesSubnodes = true
        style.flexGrow = 1
        style.flexShrink = 1
        tabStrip.automaticallyManagesSubnodes = true
        tabStrip.automaticallyManagesContentSize = true
        tabStrip.scrollableDirections = [.left, .right]
        tabStrip.style.height = ASDimension(unit: .points, value: 46)
        contentScroll.automaticallyManagesSubnodes = true
        contentScroll.automaticallyManagesContentSize = true
        contentScroll.scrollableDirections = [.up, .down]
        contentScroll.accessibilityIdentifier = "detail-magic-tab-content"
        contentScroll.layoutSpecBlock = { [weak self] _, _ in
            let stack = ASStackLayoutSpec.vertical()
            stack.spacing = 10
            if let self { stack.children = self.sectionNodes[self.selectedIndex] ?? [] }
            return stack
        }
        buttons = tabs.sections.enumerated().map { index, section in
            let button = ASButtonNode()
            button.accessibilityIdentifier = "detail-magic-tab-\(index)"
            button.accessibilityLabel = section.title
            button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            button.addTarget(self, action: #selector(tabTapped(_:)), forControlEvents: .touchUpInside)
            return button
        }
        tabStrip.layoutSpecBlock = { [weak self] _, _ in
            let stack = ASStackLayoutSpec.horizontal()
            stack.spacing = 4
            stack.children = self?.buttons ?? []
            return stack
        }
        if !tabs.sections.isEmpty { sectionNodes[0] = makeSectionContent(at: 0) }
        updateButtons()
    }

    override func didLoad() {
        super.didLoad()
        themeObserver.install(on: self)
        tabStrip.view.showsHorizontalScrollIndicator = false
        contentScroll.view.contentInsetAdjustmentBehavior = .never
        contentScroll.view.alwaysBounceVertical = false
        Self.selections.countLimit = 128
        if let saved = Self.selections.object(forKey: tabs.id as NSString) {
            selectTab(saved.intValue)
        }
    }

    @objc private func tabTapped(_ sender: ASButtonNode) {
        guard let index = buttons.firstIndex(where: { $0 === sender }) else { return }
        selectTab(index)
    }

    func selectTab(_ index: Int) {
        guard tabs.sections.indices.contains(index), index != selectedIndex else { return }
        cancelGalleryPreparation()
        selectedIndex = index
        Self.selections.setObject(NSNumber(value: index), forKey: tabs.id as NSString)
        if sectionNodes[index] == nil { sectionNodes[index] = makeSectionContent(at: index) }
        updateButtons()
        contentScroll.invalidateCalculatedLayout()
        contentScroll.setNeedsLayout()
        if contentScroll.isNodeLoaded { contentScroll.view.setContentOffset(.zero, animated: false) }
        invalidateCalculatedLayout()
        setNeedsLayout()
        onLayoutInvalidated()
    }

    private func updateButtons() {
        let traits = isNodeLoaded ? view.traitCollection : UITraitCollection.current
        for (index, button) in buttons.enumerated() {
            let selected = index == selectedIndex
            // Texture 缓存富文本绘制结果，使用当前视图的颜色值确保切换主题会触发更新。
            let color = (selected ? UIColor.label : UIColor.secondaryLabel).resolvedColor(with: traits)
            button.setAttributedTitle(NSAttributedString(string: tabs.sections[index].title, attributes: [
                .font: UIFont.systemFont(ofSize: 15, weight: selected ? .semibold : .regular),
                .foregroundColor: color,
                .underlineStyle: selected ? NSUnderlineStyle.single.rawValue : 0
            ]), for: .normal)
            button.accessibilityTraits = selected ? [.button, .selected] : [.button]
        }
    }

    func applyCurrentTheme() { updateButtons() }

    private func makeSectionContent(at index: Int) -> [ASDisplayNode] {
        makeContent(tabs.sections[index].blocks, { [weak self] urls, imageIndex in
            self?.openGallery(sectionIndex: index, imageURLs: urls, imageIndex: imageIndex)
        }, { [weak self] in
            guard let self, self.selectedIndex == index || index == 0 else { return }
            // 子图加载后必须同时作废分栏尺寸，否则整行重排仍会复用占位高度。
            self.contentScroll.invalidateCalculatedLayout()
            self.contentScroll.setNeedsLayout()
            self.invalidateCalculatedLayout()
            self.setNeedsLayout()
            self.onLayoutInvalidated()
        })
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        // 以第一栏（NQ 的基本信息）作为统一高度，长报告在栏内滚动。
        let reference = ASStackLayoutSpec.vertical()
        reference.spacing = 10
        reference.children = sectionNodes[0] ?? []
        let width = constrainedSize.max.width.isFinite ? constrainedSize.max.width : 320
        let referenceSize = reference.layoutThatFits(ASSizeRange(
            min: CGSize(width: width, height: 0),
            max: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )).size
        // 限制外层视口，不能限制 ASScrollNode 自身的内容测量高度。
        let viewport = ASWrapperLayoutSpec(layoutElement: contentScroll)
        viewport.style.height = ASDimension(unit: .points, value: max(44, ceil(referenceSize.height)))
        let stack = ASStackLayoutSpec.vertical()
        stack.spacing = 10
        stack.children = [tabStrip, viewport]
        return stack
    }
}
