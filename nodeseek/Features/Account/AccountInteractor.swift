//
//  AccountInteractor.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

class AccountInteractor: AccountInteractorInput {
    
    // MARK: - Properties
    weak var presenter: AccountInteractorOutput?
    private let service: NodeSeekService
    
    // MARK: - Initialization
    init(service: NodeSeekService = NodeSeekService()) {
        self.service = service
    }
    
    // MARK: - Methods
    func loadAccount() {
        Task {
            do {
                let result = try await service.loadAccount()
                await MainActor.run {
                    switch result {
                    case .value(let account):
                        presenter?.didLoadAccount(account)
                    case .challenge:
                        presenter?.didLoadAccount(AccountResponse(displayName: "游客", isLoggedIn: false))
                    }
                }
            } catch {
                await MainActor.run {
                    presenter?.didFailLoadAccount(error: error.localizedDescription)
                }
            }
        }
    }
}
