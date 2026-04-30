//
//  FormURLEncoder.swift
//  nodeseek
//
//  Created by Codex on 2026/4/27.
//

import Foundation

enum FormURLEncoder {
    private static let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? value
    }
}
