//
//  AccountPresenterTests.swift
//  nodeseekTests
//

import Testing
@testable import nodeseek

@MainActor
struct AccountPresenterTests {
    @Test func loginCloseReloadsAccount() {
        let interactor = SpyAccountInteractor()
        let router = SpyAccountRouter()
        let presenter = AccountPresenter(interactor: interactor, router: router)

        presenter.didTapLogin()

        #expect(router.navigateToLoginCount == 1)
        #expect(interactor.loadAccountCount == 0)

        router.capturedOnClose?()

        #expect(interactor.loadAccountCount == 1)
    }
}

private final class SpyAccountInteractor: AccountInteractorInput {
    private(set) var loadAccountCount = 0

    func loadAccount() {
        loadAccountCount += 1
    }
}

private final class SpyAccountRouter: AccountRouterProtocol {
    private(set) var navigateToLoginCount = 0
    private(set) var capturedOnClose: (@MainActor () -> Void)?

    func navigateToLogin(onClose: @escaping @MainActor () -> Void) {
        navigateToLoginCount += 1
        capturedOnClose = onClose
    }
}
