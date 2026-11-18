import Foundation
final class Provider<T> {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
    @_optimize(none)
    deinit {}
    let transport: Transport
    init(transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) { self.transport = transport }
    func run() async throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:1/mailboxes")!)
        request.timeoutInterval = 1
        request.setValue("Bearer test", forHTTPHeaderField: "Authorization")
        _ = try await transport(request)
    }
}
@main struct Main {
    static func main() async {
        for _ in 0..<100 {
            do { try await Provider<Int>().run() } catch { }
        }
        print("Completed 100 requests")
    }
}
