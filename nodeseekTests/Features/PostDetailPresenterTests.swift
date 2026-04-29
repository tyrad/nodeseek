//
//  PostDetailPresenterTests.swift
//  nodeseekTests
//

import Testing
@testable import nodeseek

@MainActor
struct PostDetailPresenterTests {
    @Test func loginCloseReloadsPostDetail() {
        let interactor = SpyPostDetailInteractor()
        let router = SpyPostDetailRouter()
        let presenter = PostDetailPresenter(interactor: interactor, router: router)

        presenter.didTapLogin()

        #expect(router.navigateToLoginCount == 1)
        #expect(interactor.loadPostDetailCount == 0)

        router.capturedOnClose?()

        #expect(interactor.loadPostDetailCount == 1)
    }
}

private final class SpyPostDetailInteractor: PostDetailInteractorInput {
    private(set) var loadPostDetailCount = 0

    func loadPostDetail() {
        loadPostDetailCount += 1
    }
}

private final class SpyPostDetailRouter: PostDetailRouterProtocol {
    private(set) var navigateToLoginCount = 0
    private(set) var capturedOnClose: (@MainActor () -> Void)?

    func navigateToLogin(onClose: @escaping @MainActor () -> Void) {
        navigateToLoginCount += 1
        capturedOnClose = onClose
    }
}
