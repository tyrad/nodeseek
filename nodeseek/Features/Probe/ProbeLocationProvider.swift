import CoreLocation
import UIKit

/// 地球页画连线用的位置权限状态。
enum ProbeLocationAuthorization: Equatable {
    case notDetermined
    case authorized
    /// 用户拒绝，或被家长控制等系统限制。
    case denied
}

/// 一次性的大致定位，方便测试替换。
protocol ProbeLocating: AnyObject {
    var authorization: ProbeLocationAuthorization { get }
    /// 本次运行期间最近一次拿到的位置。
    var lastCoordinate: CLLocationCoordinate2D? { get }
    /// 权限变化时回调，例如用户从系统设置里打开定位后回到 App。
    var onAuthorizationChange: (() -> Void)? { get set }
    func requestAuthorization()
    func requestLocation(completion: @escaping (Result<CLLocationCoordinate2D, Error>) -> Void)
}

/// 只要大致位置，拿到一次就停，不持续追踪、不在后台定位。位置只在本机使用。
final class ProbeLocationProvider: NSObject, ProbeLocating, CLLocationManagerDelegate {
    static let shared = ProbeLocationProvider()

    struct TimeoutError: LocalizedError {
        var errorDescription: String? { "定位超时" }
    }

    var onAuthorizationChange: (() -> Void)?
    private(set) var lastCoordinate: CLLocationCoordinate2D?
    private let manager = CLLocationManager()
    private var completions: [(Result<CLLocationCoordinate2D, Error>) -> Void] = []
    private var timeoutWork: DispatchWorkItem?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    var authorization: ProbeLocationAuthorization {
        switch manager.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        default: return .denied
        }
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestLocation(completion: @escaping (Result<CLLocationCoordinate2D, Error>) -> Void) {
        completions.append(completion)
        // 已在定位中时合并到同一次请求。
        guard completions.count == 1 else { return }
        manager.requestLocation()
        let work = DispatchWorkItem { [weak self] in self?.finish(.failure(TimeoutError())) }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, Error>) {
        timeoutWork?.cancel()
        timeoutWork = nil
        if case .success(let coordinate) = result { lastCoordinate = coordinate }
        let pending = completions
        completions = []
        pending.forEach { $0(result) }
    }

    // MARK: - CLLocationManagerDelegate

    // 管理器在主线程创建，系统也在主线程回调。
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        MainActor.assumeIsolated { finish(.success(coordinate)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated {
            AppLog.warning(.service, "probe location failed: \(message)")
            finish(.failure(error))
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { onAuthorizationChange?() }
    }
}
