import UIKit
import XCTest
@testable import nodeseek

@MainActor
final class KeyboardDismissCoordinatorTests: XCTestCase {
    private final class EditingDelegate: NSObject, UITextFieldDelegate {
        var allowsEnd = false
        func textFieldShouldEndEditing(_ textField: UITextField) -> Bool { allowsEnd }
    }

    func testFocusCompositionAndEndEditingValidation() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.endEditing(true); window.isHidden = true }
        let root = controller.view!
        let field = UITextField(frame: CGRect(x: 20, y: 100, width: 250, height: 44))
        root.addSubview(field)
        let coordinator = KeyboardDismissCoordinator(rootView: root, backgrounds: [root])
        XCTAssertFalse(coordinator.shouldDismiss(from: root))
        XCTAssertTrue(field.becomeFirstResponder())
        XCTAssertTrue(coordinator.shouldDismiss(from: root))
        XCTAssertFalse(coordinator.shouldDismiss(from: field))
        // 组合文字未上屏时点空白同样收起，文字由系统上屏保留。
        field.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0))
        XCTAssertTrue(coordinator.shouldDismiss(from: root))
        let delegate = EditingDelegate()
        field.delegate = delegate
        coordinator.dismissKeyboard()
        XCTAssertTrue(field.isFirstResponder)
        delegate.allowsEnd = true
        coordinator.dismissKeyboard()
        XCTAssertFalse(field.isFirstResponder)
        XCTAssertNil(field.markedTextRange)
        XCTAssertEqual(field.text, "中文")
    }

    func testStateBackgroundReplacementAndButtonHitTesting() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let state = UIView(frame: root.bounds)
        let button = UIButton(frame: CGRect(x: 20, y: 20, width: 100, height: 44))
        root.addSubview(state)
        state.addSubview(button)
        let coordinator = KeyboardDismissCoordinator(rootView: root, backgrounds: [root])
        XCTAssertFalse(coordinator.acceptsBackground(state))
        coordinator.register(state)
        XCTAssertTrue(coordinator.acceptsBackground(state))
        XCTAssertTrue(root.hitTest(CGPoint(x: 200, y: 200), with: nil) === state)
        XCTAssertTrue(root.hitTest(CGPoint(x: 30, y: 30), with: nil) === button)
        XCTAssertFalse(coordinator.acceptsBackground(button))
        coordinator.unregister(state)
        XCTAssertFalse(coordinator.acceptsBackground(state))
    }

    func testOnlyExplicitBackgroundIsAccepted() {
        let root = UIView()
        let scroll = UIScrollView()
        let field = UITextField()
        let button = UIButton()
        let text = UITextView()
        let cell = UITableViewCell()
        root.addSubview(scroll)
        [field, button, text, cell].forEach(scroll.addSubview)
        let coordinator = KeyboardDismissCoordinator(rootView: root, backgrounds: [root, scroll])
        XCTAssertTrue(coordinator.acceptsBackground(root))
        XCTAssertTrue(coordinator.acceptsBackground(scroll))
        [field, button, text, cell, cell.contentView].forEach {
            XCTAssertFalse(coordinator.acceptsBackground($0))
        }
        let tap = root.gestureRecognizers?.first
        XCTAssertEqual(tap?.cancelsTouchesInView, false)
        XCTAssertEqual(tap?.delaysTouchesBegan, false)
        XCTAssertEqual(tap?.delaysTouchesEnded, false)
    }

    func testDetachedBackgroundAndAccidentallyRegisteredInputsAreRejected() {
        let root = UIView()
        let detached = UIView()
        let field = UITextField()
        let text = UITextView()
        root.addSubview(field)
        root.addSubview(text)
        let coordinator = KeyboardDismissCoordinator(rootView: root, backgrounds: [detached, field, text])
        [detached, field, text].forEach {
            XCTAssertFalse(coordinator.acceptsBackground($0))
        }
    }

    func testCoordinatorDoesNotRetainPage() {
        weak var releasedRoot: UIView?
        var coordinator: KeyboardDismissCoordinator?
        autoreleasepool {
            let root = UIView()
            releasedRoot = root
            coordinator = KeyboardDismissCoordinator(rootView: root, backgrounds: [root])
        }
        XCTAssertNil(releasedRoot)
        XCTAssertNotNil(coordinator)
    }
}
