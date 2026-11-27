import Foundation

/// 收款人和流水编号来自指令，与发帖人、楼层编号无关。
nonisolated struct StardustReceipt: Equatable, Sendable {
    let memberID: Int
    let referenceID: Int
    let amount: Int
    let note: String
    let oneTime: Bool
    let sourceURL: URL

    init?(url: URL) {
        guard url.scheme?.lowercased() == "nsapp", url.host?.lowercased() == "stardust-receive",
              url.path.isEmpty, url.fragment == nil, url.user == nil, url.password == nil, url.port == nil,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func field(_ name: String) -> String? {
            let matches = items.filter { $0.name == name }
            return matches.count == 1 ? matches[0].value : nil
        }
        func positiveInteger(_ name: String) -> Int? {
            guard let value = field(name), value.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int(value), number > 0, number <= 9_007_199_254_740_991 else { return nil }
            return number
        }
        guard let memberID = positiveInteger("member_id"), let referenceID = positiveInteger("ref_id"),
              let amount = positiveInteger("diff"), let note = field("description"),
              let flag = field("onetime"), let oneTime = Bool(flag) else { return nil }
        self.memberID = memberID
        self.referenceID = referenceID
        self.amount = amount
        self.note = note
        self.oneTime = oneTime
        self.sourceURL = url
    }

    private var ledgerQuery: [URLQueryItem] {
        [.init(name: "member_id", value: String(memberID)), .init(name: "ref_id", value: String(referenceID))]
    }

    var ledgerURL: URL { webURL(path: "stardust/list", query: ledgerQuery) }
    var paymentURL: URL {
        webURL(path: "stardust/payment", query: ledgerQuery + [
            .init(name: "diff", value: String(amount)), .init(name: "onetime", value: String(oneTime)),
            .init(name: "description", value: note)
        ])
    }

    private func webURL(path: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents(url: NodeSeekSite.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        // 网页的 URLSearchParams 会把未转义的加号当作空格。
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    func matchesPayment(_ url: URL) -> Bool {
        let expected = paymentURL
        guard url.scheme == expected.scheme, url.host == expected.host, url.path == expected.path,
              url.user == nil, url.password == nil, url.port == nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let fields = URLComponents(url: expected, resolvingAgainstBaseURL: false)?.queryItems else { return false }
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%20")
        guard let items = components.queryItems else { return false }
        return fields.allSatisfy { field in items.filter { $0.name == field.name } == [field] }
    }
}
