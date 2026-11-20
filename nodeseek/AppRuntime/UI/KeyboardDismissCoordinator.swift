import UIKit
import WebKit

/// 页面显式指定可收起键盘的背景；不把背景的子控件视为可点击空白。
@MainActor
final class KeyboardDismissCoordinator: NSObject, UIGestureRecognizerDelegate {
    private weak var rootView: UIView?
    private let backgrounds: NSHashTable<UIView>
    private let tap = UITapGestureRecognizer()

    init(rootView: UIView, backgrounds: [UIView]) {
        self.rootView = rootView
        self.backgrounds = NSHashTable<UIView>.weakObjects()
        super.init()
        backgrounds.forEach { self.backgrounds.add($0) }
        tap.addTarget(self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        rootView.addGestureRecognizer(tap)
    }

    func acceptsBackground(_ view: UIView) -> Bool {
        guard let rootView, backgrounds.contains(view),
              view === rootView || view.isDescendant(of: rootView),
              !(view is UIControl), !(view is UITextView) else { return false }
        return true
    }

    func register(_ background: UIView) {
        backgrounds.add(background)
    }

    func unregister(_ background: UIView) {
        backgrounds.remove(background)
    }

    func shouldDismiss(from view: UIView) -> Bool {
        guard acceptsBackground(view), let rootView else { return false }
        // 点空白即表示要收起，组合文字不拦截，收起时先上屏。
        return focusedInput(in: rootView) != nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let view = touch.view else { return false }
        return shouldDismiss(from: view)
    }

    private func focusedInput(in view: UIView) -> UITextInput? {
        // 不遍历网页内部私有输入控件。
        guard !(view is WKWebView) else { return nil }
        if view.isFirstResponder, let input = view as? UITextInput { return input }
        for child in view.subviews {
            if let input = focusedInput(in: child) { return input }
        }
        return nil
    }

    @objc func dismissKeyboard() {
        // 手势识别期间焦点可能已改变；先把组合文字上屏，避免丢字，再按输入框的结束编辑校验收起。
        guard let rootView, let input = focusedInput(in: rootView) else { return }
        input.unmarkText()
        rootView.endEditing(false)
    }
}
