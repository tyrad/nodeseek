//
//  WebRequestFingerprint.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation
import Darwin

enum WebRequestFingerprint {
    nonisolated static var userAgent: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osToken = os.patchVersion > 0
            ? "\(os.majorVersion)_\(os.minorVersion)_\(os.patchVersion)"
            : "\(os.majorVersion)_\(os.minorVersion)"
        let safariVersion = "\(os.majorVersion).0"
        let isPad = isPadDevice
        let platformToken = isPad ? "iPad" : "iPhone"
        let cpuToken = isPad ? "CPU OS" : "CPU iPhone OS"
        return "Mozilla/5.0 (\(platformToken); \(cpuToken) \(osToken) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(safariVersion) Mobile/15E148 Safari/604.1"
    }

    nonisolated static var acceptLanguage: String {
        let preferred = Locale.preferredLanguages
            .map { $0.replacingOccurrences(of: "_", with: "-") }
            .filter { $0.isEmpty == false }

        guard preferred.isEmpty == false else { return "en-US,en;q=0.9" }

        return preferred.prefix(3).enumerated().map { index, language in
            guard index > 0 else { return language }
            let quality = max(0.1, 1.0 - Double(index) * 0.1)
            return "\(language);q=\(String(format: "%.1f", quality))"
        }.joined(separator: ",")
    }

    nonisolated static let referer = "https://www.nodeseek.com/"
    nonisolated static let htmlAccept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    nonisolated static let imageAccept = "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8"

    nonisolated private static var isPadDevice: Bool {
        modelIdentifier.lowercased().hasPrefix("ipad")
    }

    nonisolated private static var modelIdentifier: String {
        if let simulatorModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
           simulatorModel.isEmpty == false {
            return simulatorModel
        }

        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in
                String(cString: ptr)
            }
        }
        return machine
    }

    nonisolated static func applyHTMLHeaders(to request: inout URLRequest) {
        applyCommonHeaders(to: &request)
        request.setValue(htmlAccept, forHTTPHeaderField: "Accept")
    }

    nonisolated static func applyImageHeaders(to request: inout URLRequest) {
        applyCommonHeaders(to: &request)
        request.setValue(imageAccept, forHTTPHeaderField: "Accept")
    }

    nonisolated private static func applyCommonHeaders(to request: inout URLRequest) {
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        request.setValue(referer, forHTTPHeaderField: "Referer")
    }
}
