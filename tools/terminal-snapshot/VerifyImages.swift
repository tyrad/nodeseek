import Foundation
import ImageIO
import Vision

// 从最终位图识别尾部标记，防止 DOM 完整但截图被安全区或视口裁切。
let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".build/terminal-snapshot")
let expectations = ["basic": "hardware/144", "ip": "ip/22", "long-report": "row-160", "controls": "literal"]
for name in expectations.keys.sorted() {
    let url = directory.appendingPathComponent(name + ".png")
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US", "zh-Hans"]
    request.usesLanguageCorrection = false
    request.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: name == "controls" ? 1 : 0.14)
    try VNImageRequestHandler(url: url).perform([request])
    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: "\n").lowercased().replacingOccurrences(of: " ", with: "")
    guard text.contains(expectations[name]!) else {
        FileHandle.standardError.write(Data("FAIL \(name): 位图末尾缺少标记 \(expectations[name]!)\nOCR: \(text)\n".utf8))
        exit(1)
    }
    print("PASS \(name): 位图末尾识别到 \(expectations[name]!)")
}
