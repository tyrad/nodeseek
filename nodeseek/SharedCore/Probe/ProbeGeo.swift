import Foundation

/// 探针里的地区（国旗 🇭🇰 或国家代码 JP）转成国家代码，再查国家的大致坐标。只精确到国家。
nonisolated enum ProbeGeo {
    /// 认不出或坐标表里没有的地区返回 nil，归到“未知地区”。
    static func countryCode(from region: String?) -> String? {
        guard let raw = region?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        // 国旗由两个“区域指示符”拼成，分别对应 A–Z。
        let indicators = raw.unicodeScalars.filter { (0x1F1E6...0x1F1FF).contains($0.value) }
        let code: String
        if indicators.count >= 2 {
            code = String(String.UnicodeScalarView(indicators.prefix(2).compactMap { Unicode.Scalar($0.value - 0x1F1E6 + 65) }))
        } else {
            let letters = raw.uppercased()
            guard letters.count == 2, letters.unicodeScalars.allSatisfy({ (65...90).contains($0.value) }) else { return nil }
            code = letters == "UK" ? "GB" : letters
        }
        return coordinates[code] == nil ? nil : code
    }

    static func coordinate(for code: String) -> (latitude: Double, longitude: Double)? {
        coordinates[code].map { ($0.0, $0.1) }
    }

    static func flag(for code: String) -> String {
        String(String.UnicodeScalarView(code.unicodeScalars.compactMap { Unicode.Scalar($0.value - 65 + 0x1F1E6) }))
    }

    /// 中文国家名；港澳台用简称，系统名称太长。
    static func displayName(for code: String) -> String {
        let short = ["HK": "香港", "MO": "澳门", "TW": "台湾"]
        if let name = short[code] { return name }
        return Locale(identifier: "zh_Hans").localizedString(forRegionCode: code) ?? code
    }

    /// 国家中心点（纬度, 经度）。由 echarts 世界轮廓（Apache-2.0）的最大陆块求重心得到；
    /// 地图上没有轮廓的小地方手工补齐，俄罗斯、美国等大国改用机房常见的位置。
    private static let coordinates: [String: (Double, Double)] = [
        "AD": (42.51, 1.52), "AE": (23.9, 54.3), "AF": (33.84, 66), "AG": (17.08, -61.81),
        "AL": (41.14, 20.05), "AM": (40.3, 44.91), "AO": (-12.33, 17.56), "AR": (-35.18, -65.16),
        "AS": (-14.31, -170.7), "AT": (47.58, 14.13), "AU": (-33.87, 151.21), "AW": (12.52, -69.97),
        "AX": (60.24, 19.94), "AZ": (40.33, 47.66), "BA": (44.18, 17.77), "BB": (13.19, -59.54),
        "BD": (23.91, 90.22), "BE": (50.63, 4.64), "BF": (12.27, -1.76), "BG": (42.77, 25.22),
        "BH": (26.07, 50.55), "BI": (-3.36, 29.88), "BJ": (9.64, 2.33), "BM": (32.3, -64.78),
        "BN": (4.51, 114.58), "BO": (-16.71, -64.69), "BR": (-23.55, -46.63), "BS": (24.71, -78.03),
        "BT": (27.41, 90.4), "BW": (-22.18, 23.79), "BY": (53.52, 28.03), "BZ": (17.18, -88.72),
        "CA": (43.65, -79.38), "CD": (-2.88, 23.64), "CF": (6.56, 20.46), "CG": (-0.84, 15.22),
        "CH": (46.8, 8.2), "CI": (7.62, -5.57), "CL": (-35.7, -71.3), "CM": (5.69, 12.74),
        "CN": (31.23, 121.47), "CO": (3.91, -73.08), "CR": (9.97, -84.19), "CU": (21.62, -78.94),
        "CV": (15.12, -23.6), "CW": (12.17, -68.98), "CY": (34.91, 32.97), "CZ": (49.72, 15.33),
        "DE": (51.08, 10.38), "DJ": (11.76, 42.56), "DK": (56.25, 9.37), "DM": (15.41, -61.37),
        "DO": (18.9, -70.53), "DZ": (28.16, 2.62), "EC": (-1.44, -78.39), "EE": (58.68, 25.84),
        "EG": (26.5, 29.86), "EH": (24.73, -13.1), "ER": (15.36, 38.82), "ES": (40.4, -3.56),
        "ET": (8.62, 39.61), "FI": (64.5, 26.29), "FJ": (-17.82, 177.98), "FK": (-51.74, -58.78),
        "FM": (6.92, 158.16), "FO": (62.17, -6.86), "FR": (46.61, 2.46), "GA": (-0.59, 11.79),
        "GB": (53.92, -2.49), "GD": (12.12, -61.68), "GE": (42.17, 43.51), "GG": (49.45, -2.58),
        "GH": (7.95, -1.22), "GI": (36.14, -5.35), "GL": (74.71, -41.35), "GM": (13.45, -15.44),
        "GN": (10.43, -10.94), "GQ": (1.56, 10.48), "GR": (39.48, 22.58), "GT": (15.7, -90.36),
        "GU": (13.44, 144.79), "GW": (12.07, -14.92), "GY": (4.79, -58.99), "HK": (22.32, 114.17),
        "HN": (14.82, -86.61), "HR": (45.15, 16.47), "HT": (18.91, -72.68), "HU": (47.17, 19.4),
        "ID": (-0.19, 114.01), "IE": (53.18, -8.13), "IL": (31.45, 35), "IM": (54.24, -4.55),
        "IN": (22.36, 79.33), "IQ": (33.04, 43.75), "IR": (32.58, 54.27), "IS": (64.99, -18.54),
        "IT": (43.52, 12.15), "JE": (49.21, -2.13), "JM": (18.16, -77.32), "JO": (31.24, 36.76),
        "JP": (36.65, 137.99), "KE": (0.6, 37.79), "KG": (41.46, 74.54), "KH": (12.72, 104.91),
        "KI": (1.87, -157.36), "KM": (-11.65, 43.33), "KN": (17.36, -62.78), "KP": (40.15, 127.2),
        "KR": (36.45, 127.87), "KW": (29.31, 47.57), "KY": (19.31, -81.29), "KZ": (48.16, 67.27),
        "LA": (18.51, 103.74), "LB": (33.91, 35.86), "LC": (13.89, -60.96), "LI": (47.14, 9.52),
        "LK": (7.63, 80.69), "LR": (6.45, -9.32), "LS": (-29.58, 28.23), "LT": (55.33, 23.9),
        "LU": (49.61, 6.13), "LV": (56.85, 24.92), "LY": (27.03, 18), "MA": (31.95, -6.25),
        "MC": (43.73, 7.42), "MD": (47.18, 28.45), "ME": (42.79, 19.22), "MG": (-19.38, 46.7),
        "MH": (7.13, 171.18), "MK": (41.59, 21.69), "ML": (17.35, -3.54), "MM": (21.24, 96.49),
        "MN": (46.82, 103.06), "MO": (22.2, 113.55), "MP": (15.2, 145.76), "MR": (20.25, -10.36),
        "MS": (16.75, -62.19), "MT": (35.9, 14.51), "MU": (-20.2, 57.5), "MV": (3.2, 73.22),
        "MW": (-13.22, 34.29), "MX": (23.93, -102.49), "MY": (3.62, 114.72), "MZ": (-17.29, 35.53),
        "NA": (-22.13, 17.22), "NC": (-21.32, 165.48), "NE": (17.42, 9.39), "NG": (9.6, 8.09),
        "NI": (12.84, -85.04), "NL": (52.29, 5.64), "NO": (64.23, 13.91), "NP": (28.25, 83.92),
        "NR": (-0.52, 166.93), "NU": (-19.04, -169.86), "NZ": (-43.97, 170.54), "OM": (20.58, 56.1),
        "PA": (8.53, -80.15), "PE": (-9.15, -74.39), "PF": (-17.66, -149.42), "PG": (-6.61, 144.26),
        "PH": (15.97, 121.41), "PK": (29.27, 68.7), "PL": (52.12, 19.39), "PM": (46.92, -56.34),
        "PR": (18.22, -66.59), "PS": (31.97, 35.25), "PT": (39.65, -7.98), "PW": (7.51, 134.58),
        "PY": (-23.22, -58.4), "QA": (25.31, 51.18), "RE": (-21.11, 55.53), "RO": (45.85, 24.97),
        "RS": (44.02, 20.8), "RU": (55.75, 37.62), "RW": (-1.99, 29.93), "SA": (24.12, 44.53),
        "SB": (-9.63, 160.16), "SC": (-4.68, 55.49), "SD": (15.99, 29.94), "SE": (62.83, 16.74),
        "SG": (1.35, 103.82), "SH": (-15.97, -5.73), "SI": (46.11, 14.8), "SK": (48.7, 19.47),
        "SL": (8.56, -11.78), "SM": (43.94, 12.46), "SN": (14.36, -14.47), "SO": (6.07, 45.85),
        "SR": (4.12, -55.91), "SS": (7.3, 30.24), "ST": (0.22, 6.61), "SV": (13.75, -88.89),
        "SY": (35.03, 38.53), "SZ": (-26.55, 31.48), "TC": (21.8, -72.27), "TD": (15.33, 18.65),
        "TG": (8.51, 0.96), "TH": (15.12, 101.01), "TJ": (38.53, 71), "TL": (-8.81, 125.91),
        "TM": (39.11, 59.38), "TN": (34.12, 9.55), "TO": (-21.18, -175.2), "TR": (38.99, 35.42),
        "TT": (10.43, -61.29), "TV": (-7.11, 177.65), "TW": (23.7, 120.96), "TZ": (-6.28, 34.79),
        "UA": (49, 31.39), "UG": (1.28, 32.37), "US": (39, -98), "UY": (-32.8, -56.02),
        "UZ": (41.76, 63.13), "VA": (41.9, 12.45), "VC": (13.27, -61.19), "VE": (7.12, -66.18),
        "VI": (17.75, -64.75), "VN": (16.66, 106.31), "VU": (-15.25, 166.86), "WS": (-13.76, -172.1),
        "YE": (15.93, 47.55), "ZA": (-29.01, 25.16), "ZM": (-13.46, 27.77), "ZW": (-19.01, 29.85),
    ]
}

/// 按国家汇总的一组服务器，地球页上的一个点、列表里的一行。
nonisolated struct ProbeCountryGroup: Equatable, Sendable {
    /// 按严重程度排列，数值越小越需要先看。
    enum Health: Int, Comparable, Sendable {
        case offline, alert, unknown, online

        static func < (lhs: Health, rhs: Health) -> Bool { lhs.rawValue < rhs.rawValue }

        init(_ entry: ProbeListEntry) {
            if entry.isStale { self = .unknown; return }
            switch entry.server.availability {
            case .offline: self = .offline
            case .unknown: self = .unknown
            case .online: self = entry.isAlerting ? .alert : .online
            }
        }
    }

    /// nil 表示没有填地区或认不出的服务器。
    let code: String?
    let entries: [ProbeListEntry]

    var id: String { code ?? "unknown" }
    var health: Health { entries.map(Health.init).min() ?? .unknown }
    var offlineCount: Int { entries.filter { Health($0) == .offline }.count }
    var alertCount: Int { entries.filter { Health($0) == .alert }.count }

    /// 有问题的国家在前，其次机器多的在前；“未知地区”始终最后。
    /// 国家优先取面板国旗，没有时从名字推断（见 `ProbeDatacenterDirectory.locate`）。
    static func groups(from entries: [ProbeListEntry], directory: ProbeDatacenterDirectory = .builtin) -> [ProbeCountryGroup] {
        let grouped = Dictionary(grouping: entries) { directory.locate($0).country }
        let groups = grouped.map { ProbeCountryGroup(code: $0.key, entries: $0.value.sorted { $0.panelIndex < $1.panelIndex }) }
        return groups.sorted { lhs, rhs in
            if (lhs.code == nil) != (rhs.code == nil) { return rhs.code == nil }
            if lhs.health != rhs.health { return lhs.health < rhs.health }
            if lhs.entries.count != rhs.entries.count { return lhs.entries.count > rhs.entries.count }
            return lhs.id < rhs.id
        }
    }
}
