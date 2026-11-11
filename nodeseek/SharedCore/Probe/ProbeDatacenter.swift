import Foundation

/// 内置机房城市字典里的一条（`probe-datacenters.json`）。
nonisolated struct ProbeDatacenter: Codable, Equatable, Sendable {
    var city: String
    var country: String
    var lat: Double
    var lon: Double
    /// 机场或城市代码，例如 LAX；名字里作为独立的词出现才算命中。
    var codes: [String]
    /// 其他写法：英文按整词匹配（不分大小写），中文直接在名字里找。
    var names: [String]
}

/// 一台服务器推断出的位置：国家一定有（否则归“未知地区”），城市可能没有。
nonisolated struct ProbeServerLocation: Equatable, Sendable {
    var country: String?
    var city: ProbeDatacenter?

    var coordinate: (latitude: Double, longitude: Double)? {
        if let city { return (city.lat, city.lon) }
        return country.flatMap(ProbeGeo.coordinate(for:))
    }
}

/// 从服务器名字、分组名里认出机房城市；认不出时按面板的国旗定位到国家。
nonisolated struct ProbeDatacenterDirectory: Sendable {
    let cities: [ProbeDatacenter]
    private let byCode: [String: ProbeDatacenter]

    static let resourceName = "probe-datacenters"

    /// 名字里只写了国家代码时（例如 “HK-01”）用来推断国家。只认大写，避免把 in、us、de 这类单词当成国家；
    /// 不含 CN，因为 “CN2” 线路名太常见。
    private static let countryTokens: Set<String> = [
        "HK", "SG", "JP", "US", "KR", "TW", "MO", "DE", "GB", "UK", "FR", "NL", "RU", "CA", "AU", "IN",
        "TH", "VN", "MY", "PH", "ID", "TR", "BR", "ZA", "AE", "IT", "ES", "CH", "SE", "FI", "PL",
    ]

    init(cities: [ProbeDatacenter]) {
        self.cities = cities
        var byCode: [String: ProbeDatacenter] = [:]
        for city in cities {
            for code in city.codes where byCode[code.uppercased()] == nil { byCode[code.uppercased()] = city }
        }
        self.byCode = byCode
    }

    init(data: Data) throws {
        struct File: Decodable { var cities: [ProbeDatacenter] }
        self.init(cities: try JSONDecoder().decode(File.self, from: data).cities)
    }

    /// App 内置的字典；读不到时为空，所有服务器退回按国家定位。
    static let builtin: ProbeDatacenterDirectory = {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let directory = try? ProbeDatacenterDirectory(data: data) else {
            return ProbeDatacenterDirectory(cities: [])
        }
        return directory
    }()

    func locate(_ entry: ProbeListEntry) -> ProbeServerLocation {
        let node = entry.server.node
        let regionCountry = ProbeGeo.countryCode(from: node.region)
        let texts = [entry.displayName, node.name, node.group].compactMap { $0 }
        if let city = city(in: texts, country: regionCountry) {
            return ProbeServerLocation(country: regionCountry ?? city.country, city: city)
        }
        if regionCountry == nil, let inferred = country(in: texts) {
            return ProbeServerLocation(country: inferred, city: nil)
        }
        return ProbeServerLocation(country: regionCountry, city: nil)
    }

    /// 依次在每段文字里找城市；和面板国旗不是同一个国家的不采用（例如国旗 🇫🇷 时不把 FRA 当法兰克福）。
    func city(in texts: [String], country: String?) -> ProbeDatacenter? {
        for text in texts {
            for candidate in matches(in: text) where country == nil || candidate.country == country {
                return candidate
            }
        }
        return nil
    }

    private func matches(in text: String) -> [ProbeDatacenter] {
        let tokens = Self.tokens(in: text)
        var found: [ProbeDatacenter] = tokens.compactMap { byCode[$0.uppercased()] }
        let spaced = " " + tokens.map { $0.lowercased() }.joined(separator: " ") + " "
        let lowered = text.lowercased()
        for city in cities where !found.contains(city) {
            let hit = city.names.contains { name in
                // 中文直接找子串；英文要求整词，避免 lima 命中 climate。
                name.unicodeScalars.contains { $0.value > 0x2E80 } ? lowered.contains(name) : spaced.contains(" \(name) ")
            }
            if hit { found.append(city) }
        }
        return found
    }

    private func country(in texts: [String]) -> String? {
        for text in texts {
            for token in Self.tokens(in: text) where token.count == 2 && Self.countryTokens.contains(token) {
                // 只认原文就是大写的写法。
                if let code = ProbeGeo.countryCode(from: token) { return code }
            }
        }
        return nil
    }

    /// 按非字母数字切词，再在字母和数字、英文和中文之间切开：“US-LAX2洛杉矶” → US、LAX、2、洛杉矶。
    static func tokens(in text: String) -> [String] {
        enum Kind { case digit, ascii, other }
        var tokens: [String] = []
        var current = ""
        var currentKind = Kind.other
        func flush() {
            if !current.isEmpty { tokens.append(current) }
            current = ""
        }
        for character in text {
            guard character.isLetter || character.isNumber else { flush(); continue }
            let kind: Kind = character.isNumber ? .digit : character.isASCII ? .ascii : .other
            if !current.isEmpty, kind != currentKind { flush() }
            current.append(character)
            currentKind = kind
        }
        flush()
        return tokens
    }
}
