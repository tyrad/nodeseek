import SceneKit
import UIKit

// MARK: - 陆地掩码

/// 1° 精度的陆地掩码（360×180，按行从北到南，每格 1 bit），由 echarts 的世界轮廓（Apache-2.0）栅格化而来，不含南极。
nonisolated enum ProbeLandMask {
    static func isLand(latitude: Double, longitude: Double) -> Bool {
        let row = min(max(Int(90 - latitude), 0), 179)
        let col = min(max(Int(longitude + 180), 0), 359)
        let index = row * 360 + col
        return bits[index >> 3] >> UInt8(index & 7) & 1 == 1
    }

    private static let bits: [UInt8] = Array(Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) ?? Data(count: 8100))

    private static let encoded = """
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAfwAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/P8/AOD//z8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD0//+B
/////3/7AAAAAAAAAAAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPAH+F/+//////8PAAAAAAAAADAAAQAAAB8AAAAAAAAAAAAA
AAAAAAAAAAAAAPD//wf4//////8BAACANz8AAAAAAAAAAP4AAAAAAAAAAAAAAAAAAAAAAAA4+Azn//D//////38AAACA/wMAAAAA
AAAAAAAfAAAAAAAAAAAAAAAAAAAAAIAYBDAyP0D+//////8AAAAAPAoAAAAAAAAAAAAYAAAAAAAAAAAAAAAAAAAAAFjAkPPRH4D/
/////z8AAAAAAAAAAAAA4AAAAAD/HwAAAAAAAAAAAAAAAAAAAAD/Az/fDwAA/P////8AAAAAAAAAAADABwAAwP//PwAA4FsAAAAA
AAAAAAAAAAQMAAAwAAAA8P////8BAAAAAAAAAABwAAAA+P//FwAAAAAAAAAAAAAAAAAAAP8BhvMxfwAA8P///2cAAAAAAAAAAAAc
AADg//9/3AcJAAcAAAAAAAAAAAAAgN9vxyecxwAA4P///zcAAAAAAAAAAAAGAJ7i//////8fAB8AAAAAAwAAAAAAAMf/D2L8/wsA
oP///z8AAAAAAAAAAAAPAG/+//////8fe/8HAAAAAADwDwAAAAD4P/D4/+8AwP7/fwAAAAAAANgDAAAAgN9/////////////DwAA
AAD+//+BvI7/H9aBAf8AwP7//w8AAAAAoP8PAAAAD9//////////////348/A8D///////8DB8zNA/wAgP///wAAAAAA6P//AwF6
//79////////////////HwD//////////+/vh/EPwP//BwAAAAAA8P//H/H//9///////////////////4Hw//////////+fAfw/
gP//AQAAAAAA/v+/H/////P/////////////////8fD///////////9XAPwZgP8PANA/AAAA/+N/8P//////////////////////
QAD4///////////Pw/gHAP4PAMA/AACA//F//v////////////////////8fAAP8///////////BAHAGAP4HAAADAACw//z/////
//////////////////9/AID//////////38AQ4AJAPwDAAAAAAD8H/7/////////////////////f/5fAMD//////////z8AwA8A
APgDAAAAAAD+H/z/////////////////////Mf8BAID/7/z//////x8AwD8AAMAAAAAAAAT+Pzz+//////////////////9/wG8A
AAD8AwD//////x8AwD8IAAAAAAAAAAC+P2D///////////////////8xYAAAAACACwD4/////38AwP8eAAAAAAAAgAGcH/T/////
/////////////wEAOAAAAADADgDA/////38AgP8/AAAAAAAA4ANAX3T//////////////////wAAfgAAAAAwAABA//////8PgP8/
AAAAAAAAgAFwHv7/////////////////PwAAfwAAAAAAAABA//////9/wP//AAAAAAAAgAPwAv7/////////////////DwAAPwAA
AIAAAAAA/P//////8///AwAAAAAAMAcgcv//////////////////HwAAHwAAAAAAAACA9P//////4///DwAAAAAAPA7o////////
/////////////wEADwAAAAAAAAAA8f//////4///DwAAAAAAPD/+/////////////////////wUABwAAAAAAAAAA4P//////5///
FwAAAAAAAB///////////////////////wUAAgAAAAAAAAAAoP//////////CAAAAAAAgMH//////////////////////w0AAAAA
AAAAAAAAYP////////8xLAAAAAAAAPT//////////////////////wwAAAAAAAAAAAAAAP///////38PfAAAAAAAgP//////////
/////////////wQAAAAAAAAAAAAAAP3///////8HQAAAAAAAAP7/////////////////////fwQAAAAAAAAAAAAAAP////////+X
AAAAAAAAAPz////3/B/+////////////PwgAAAAAAAAAAAAAAP////////9/AAAAAAAAAPj//P9j/A/+////////////HwAAAAAA
AAAAAAAAAP////////8MAAAAAAAAAPj/+P8B/Mf/////////////DwQAAAAAAAAAAAAAAP///////z8AAAAAAAAAcPzH4/8B8I//
////////////Bx4AAAAAAAAAAAAAAP///////x8AAAAAAAAA+H+gg/8AwA/+//////////9/AAwAAAAAAAAAAAAAAP///////x8A
AAAAAAAA+D8ADv/w4B/8//////////8/AAAAAAAAAAAAAAAAAP///////wMAAAAAAAAA+A8wuA/+/z/+/////////98fAAMAAAAA
AAAAAAAAAP///////wMAAAAAAAAA+E8wEIf//x/+/////////2cGAAMAAAAAAAAAAAAAAP7//////wEAAAAAgAAA+A8AEMb//x/8
/////////wMOAAEAAAAAAAAAAAAAAPz//////wAAAAAAAAAA+AcABoT//z/8/////////zcYgAEAAAAAAAAAAAAAAPz//////wAA
AAAAAAAAQMB/AAA2/////////////x8Y8AEAAAAAAAAAAAAAAPj//////wEAAAAAAAAAQPh/AAAA/////////////w8Y/gAAAAAA
AAAAAAAAAPj/////fwAAAAAAAAAA4P8/AAAA/////////////w+EGwAAAAAAAAAAAAAAAMD/////HwAAAAAAAAAA8P9/AACA////
/////////x/AAwAAAAAAAAAAAAAAAID/////BwAAAAAAAAAA+P//BwaA/////////////x+AAAAAAAAAAAAAAAAAAID9////BwAA
AAAAAAAA/P//D3/A/////////////x9AAAAAAAAAAAAAAAAAAAD5////BwAAAAAAAAAA/P//f////////////////x8AAAAAAAAA
AAAAAAAAAAD2/z8CBgAAAAAAAAAA/P/////v/4///////////z8AAAAAAAAAAAAAAAAAAAD0/w8ABgAAAAAAAAAA/v///////4//
/////////z8AAAAAAAAAAAAAAAAAAADu/wcADgAAAAAAAACA//////8//x/+/////////x8AAAAAAAAAAAAAAAAAAACI/wcADAAA
AAAAAADA//////8//z/g/////////w8AAAAAAAAAAAAAAAAAAACQ/wcACAAAAAAAAADg//////9//j+A/////////w8AAAAAAAAA
AAAAAAAAAAAQ/wMAAAAAAAAAAADg//////9//n8YgP///////yMAAAAAAAAAAAAAAAAAAABA/gMAAAAAAAAAAADw////////+P9/
AP///////xEAAAAAAAAAAAAAAAAAAAAA/AMAHQAAAAAAAADw////////+P//APz/////PxAAAAAAAAAAAAAAAAAAAAAA+AMIYAAA
AAAAAAD4////////+f9/AOz/B///BAAAAAAAAAAAAAAAAAAAAAAA+AccgAEAAAAAAADw////////8f9/AOD/B/5/AAAAAAAAAAAA
AAAAAQAAAAAA+A8OADgAAAAAAADw////////4f8/AOD/Afw/BgAAAAAAAAAAAAAAAAAAAAAA8J8OAPwAAAAAAADw////////4/8f
AOD/APw/AgAAAAAAAAAAAAAAAAAAAAAAgP8PAAAAAAAAAADw////////x/8HAOB/APh/ADAAAAAAAAAAAAAAAAAAAAAAAP4PAAAA
AAAAAADw////////h/8BAOA/AMz/ADAAAAAAAAAAAAAAAAAAAAAAAID/AAAAAAAAAAD4////////j/8AAMAPAMD/ATAAAAAAAAAA
AAAAAAAAAAAAAAD/AQAAAAAAAAD4////////nx8AAMAPAMD/ATAAAAAAAAAAAAAAAAAAAAAAAAD8AAAAAAAAAADw////////vwcA
AIAPAMD+AdAAAAAAAAAAAAAAAAAAAAAAAADgAAAAAAAAAAD4////////fwACAIAPAID8AQABAAAAAAAAAAAAAAAAAAAAAADAAAgA
AAAAAADg////////f0AAAAAPAID4AUADAAAAAAAAAAAAAAAAAAAAAADAAe8TAAAAAADg/////////34AAAAPAEBwAAgAAAAAAAAA
AAAAAAAAAAAAAAAAE+9/AAAAAADA/////////38AAAAXAEAgAAQCAAAAAAAAAAAAAAAAAAAAAAAAz///AAAAAACA/////////z8A
AAASAMAAAIADAAAAAAAAAAAAAAAAAAAAAAAAyP//AQAAAAAA/////////z8AAAAwAIAAAAAHAAAAAAAAAAAAAAAAAAAAAAAAgP//
AwAAAAAA/n///////x8AAAAwAAADAAMDAAAAAAAAAAAAAAAAAAAAAAAAwP//fwAAAAAA/A/+/////x8AAAAAAAgHAAcAAAAAAAAA
AAAAAAAAAAAAAAAAgP///wAAAAAAEADk/////w8AAAAAADAGwAcAAAAAAAAAAAAAAAAAAAAAAAAAgP///wEAAAAAAADA/////wcA
AAAAAGAG4AEAAAAAAAAAAAAAAAAAAAAAAAAAwP///wEAAAAAAADA/////wMAAAAAAMAM+AMQAAAAAAAAAAAAAAAAAAAAAAAA4P//
/wMAAAAAAADA/////wEAAAAAAIAL/gMQAAAAAAAAAAAAAAAAAAAAAAAA8P///wEAAAAAAADg////fwAAAAAAAIAH/vMQAAAAAAAA
AAAAAAAAAAAAAAAA8P///w4AAAAAAADg////PwAAAAAAAAAX/gMIAQAAAAAAAAAAAAAAAAAAAAAA+P//f3cAAAAAAADg////PwAA
AAAAAAAO/DkIAwAAAAAAAAAAAAAAAAAAAAAA+P///3sAAAAAAADA////HwAAAAAAAAB+/DkA8AEAAAAAAAAAAAAAAAAAAAAA+P//
//8fAAAAAACA////DwAAAAAAAAA8gChE/A8AAAAAAAAAAAAAAAAAAAAA+P////8/AAAAAAAA////BwAAAAAAAAA4AAAA8B8AAAAA
AAAAAAAAAAAAAAAA+P//////AQAAAAAA////BwAAAAAAAAAwAAgAwD8NAAAAAAAAAAAAAAAAAAAA8P//////AQAAAAAA/v//BwAA
AAAAAADAAAAAhP+AAAAAAAAAAAAAAAAAAAAA8P//////AQAAAAAA/v//BwAAAAAAAACAHwCAwH8AAAAAAAAAAAAAAAAAAAAA4P//
////AQAAAAAA/v//BwAAAAAAAAAAgJ8EAMcAAAAAAAAAAAAAAAAAAAAAwP//////AAAAAAAA/v//DwAAAAAAAAAAAAgBAIAFAAAA
AAAAAAAAAAAAAAAAwP//////AAAAAAAA/P//DwAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAgP////9/AAAAAAAA/P//DwAA
AAAAAAAAAABAAQQgAAAAAAAAAAAAAAAAAAAAgP////8/AAAAAAAA/v//DyAAAAAAAAAAAACAHwQAAAAAgAAAAAAAAAAAAAAAAP//
//8fAAAAAAAA/v//HyAAAAAAAAAAAADADwwAAAAAAAAAAAAAAAAAAAAAAP////8fAAAAAAAA////HzAAAAAAAAAAAADMDxwAAAAA
AAAAAAAAAAAAAAAAAP7///8fAAAAAAAA////DzwAAAAAAAAAAAD/DxwAAAAAAAAAAAAAAAAAAAAAAPj///8fAAAAAAAA////Dz8A
AAAAAAAAAID/vx4AAAiAAAAAAAAAAAAAAAAAAOD///8fAAAAAAAA////Ax8AAAAAAAAAAMD//z4AAAAAAAAAAAAAAAAAAAAAAMD/
//8PAAAAAAAA////AR8AAAAAAAAAAMD//z8AAAAAAAAAAAAAAAAAAAAAAMD///8PAAAAAAAA/v9/AB8AAAAAAAAAAOD///8AAAAA
AAAAAAAAAAAAAAAAAMD///8PAAAAAAAA/v9/AB8AAAAAAAAAAPz///8BAAEAAAAAAAAAAAAAAAAAAMD///8HAAAAAAAA/P9/gA8A
AAAAAAAAgP////8BAAIAAAAAAAAAAAAAAAAAAMD///8DAAAAAAAA/P//gA8AAAAAAAAAwP////8DAAAAAAAAAAAAAAAAAAAAAMD/
/38AAAAAAAAA/P9/AA8AAAAAAAAAwP////8HAAAAAAAAAAAAAAAAAAAAAOD//x8AAAAAAAAA+P9/AAcAAAAAAAAA4P////8PAAAA
AAAAAAAAAAAAAAAAAOD//wcAAAAAAAAA+P8fAAIAAAAAAAAAwP////8fAAAAAAAAAAAAAAAAAAAAAOD//wcAAAAAAAAA+P8fAAAA
AAAAAAAA4P////8fAAAAAAAAAAAAAAAAAAAAAOD//wcAAAAAAAAA+P8fAAAAAAAAAAAAwP////8/AAAAAAAAAAAAAAAAAAAAAOD/
/wcAAAAAAAAA8P8PAAAAAAAAAAAAwP////8/AAAAAAAAAAAAAAAAAAAAAOD//wMAAAAAAAAA4P8HAAAAAAAAAAAAgP////8fAAAA
AAAAAAAAAAAAAAAAAPD//wMAAAAAAAAA4P8HAAAAAAAAAAAAgP////8fAAAAAAAAAAAAAAAAAAAAAPD//wAAAAAAAAAAwP8DAAAA
AAAAAAAAAP////8fAAAAAAAAAAAAAAAAAAAAAOD//wAAAAAAAAAAwP8BAAAAAAAAAAAAAP8D/P8PAAAAAAAAAAAAAAAAAAAAAPD/
fQAAAAAAAAAAwH8AAAAAAAAAAAAAgP8A2P8HAAAAAAAAAAAAAAAAAAAAAPD/OwAAAAAAAAAAgAAAAAAAAAAAAAAAAAcA6P8HAAAA
AAAAAAAAAAAAAAAAAPj/BwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAwP8DAAACAAAAAAAAAAAAAAAAAPj/BwAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAP8DAAAEAAAAAAAAAAAAAAAAAPz/BwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP8DAAAIAAAAAAAAAAAAAAAAAPz/
AwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGgAAAA4AAAAAAAAAAAAAAAAAPg/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAc
AAAAAAAAAAAAAAAAAPw/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAYAAAAAAAAAAAAAAAAAPwHAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAOAAAAADAAAAAAAAAAAAAAAAAPgPAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAOAAAIADAAAAAAAAAAAAAAAAAPgH
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAMABAAAAAAAAAAAAAAAAAPoHAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHAA
AAAAAAAAAAAAAAAAAP4BAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHgAAAAAAAAAAAAAAAAAAP4BAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAADAAAAAAAAAAAAAAAAAAAPwDAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP0B
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPwAAAAAAAAAAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAH4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHwAAwAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAANQA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAANADAACAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
"""
}

// MARK: - 几何

/// 坐标与几何计算不绑主线程：SceneKit 的自定义动作在渲染线程回调。
nonisolated enum ProbeGlobeMath {
    /// 经纬度转单位球面坐标：经度 0 朝 +z，东经朝 +x，北纬朝 +y。与 SCNSphere 的默认贴图方向一致。
    static func point(latitude: Double, longitude: Double, radius: Float = 1) -> SIMD3<Float> {
        let lat = latitude * .pi / 180, lon = longitude * .pi / 180
        return SIMD3(Float(cos(lat) * sin(lon)), Float(sin(lat)), Float(cos(lat) * cos(lon))) * radius
    }

    /// 等距点阵贴图：每行按纬度圈长短放点，横向再拉宽 1/cos(纬度)，贴到球上后点是圆的、间距均匀。
    static func dotTexture(fill: UIColor, dot: UIColor, width: Int = 3072) -> UIImage {
        let size = CGSize(width: width, height: width / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        // SceneKit 不认宽色域/高位深的贴图格式，会直接断言崩溃，这里固定 8 位 sRGB。
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.setFillColor(fill.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            cg.setFillColor(dot.cgColor)
            let step = 1.25
            let radius = size.height * 0.34 / 180
            var latitude = 90 - step / 2
            while latitude > -90 {
                let scale = cos(latitude * .pi / 180)
                let count = Int((360 / step * scale).rounded())
                if scale > 0.08, count > 0 {
                    for i in 0..<count {
                        let longitude = -180 + (Double(i) + 0.5) * 360 / Double(count)
                        guard ProbeLandMask.isLand(latitude: latitude, longitude: longitude) else { continue }
                        let x = (longitude + 180) / 360 * size.width
                        let y = (90 - latitude) / 180 * size.height
                        let rx = radius / scale
                        cg.fillEllipse(in: CGRect(x: x - rx, y: y - radius, width: rx * 2, height: radius * 2))
                    }
                }
                latitude -= step
            }
        }
    }
}

extension ProbeGlobeMath {
    /// 两点之间沿大圆走、中间拱起的弧线，距离越远拱得越高。
    nonisolated static func arc(from a: SIMD3<Float>, to b: SIMD3<Float>, segments: Int = 64) -> [SIMD3<Float>] {
        let angle = acos(min(max(simd_dot(simd_normalize(a), simd_normalize(b)), -1), 1))
        guard angle > 0.001 else { return [a, b] }
        return (0...segments).map { step in
            let t = Float(step) / Float(segments)
            let p = (sin((1 - t) * angle) * a + sin(t * angle) * b) / sin(angle)
            return simd_normalize(p) * (1.01 + sin(.pi * t) * angle * 0.1)
        }
    }

    /// 小光点沿弧线跑过去，渐显渐隐，跑完歇一会儿再来。
    nonisolated static func travel(along points: [SIMD3<Float>], duration: TimeInterval) -> SCNAction {
        let move = SCNAction.customAction(duration: duration) { node, elapsed in
            let t = min(max(Double(elapsed) / duration, 0), 1)
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            let position = eased * Double(points.count - 1)
            let index = min(Int(position), points.count - 2)
            let fraction = Float(position - Double(index))
            node.simdPosition = simd_mix(points[index], points[index + 1], SIMD3(repeating: fraction))
            node.opacity = CGFloat(sin(.pi * t))
        }
        return .repeatForever(.sequence([move, .wait(duration: 1.2)]))
    }

    /// 圆环往外扩散并淡出，再复位重来。复位的回调在渲染线程执行，所以放在这里。
    nonisolated static func ripple() -> SCNAction {
        .repeatForever(.sequence([
            .group([.scale(to: 3.2, duration: 1.6), .fadeOut(duration: 1.6)]),
            .run { node in
                node.scale = SCNVector3(1, 1, 1)
                node.opacity = 1
            },
        ]))
    }
}

/// CADisplayLink 会强引用 target，用弱引用中转，视图释放后自动停止。
/// 球后面的径向渐变光晕：球内部被遮住，只有球外的一圈从淡灰渐隐到透明。
private final class ProbeGlobeHaloView: UIView {
    /// 光晕半径相对球半径的倍数。
    static let scale: CGFloat = 1.16

    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        guard let gradient = layer as? CAGradientLayer else { return }
        gradient.type = .radial
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        let edge = NSNumber(value: Double(1 / Self.scale) - 0.02)
        gradient.colors = [
            UIColor.black.withAlphaComponent(0.12).cgColor,
            UIColor.black.withAlphaComponent(0.12).cgColor,
            UIColor.black.withAlphaComponent(0.04).cgColor,
            UIColor.black.withAlphaComponent(0).cgColor,
        ]
        gradient.locations = [0, edge, NSNumber(value: Double(edge) + 0.07), 1]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class ProbeWeakTarget: NSObject {
    weak var view: ProbeGlobeView?
    init(_ view: ProbeGlobeView) { self.view = view }

    @objc func tick(_ link: CADisplayLink) {
        guard let view else { link.invalidate(); return }
        view.stepInertia(link)
    }
}

// MARK: - 地球视图

/// 单色点阵地球：陆地由小点拼成，每个国家一个状态色的点，异常的会一圈圈往外扩散。
/// 慢慢自转；在球上拖动可自由旋转、甩动有惯性，双指缩放、双击复原。深色模式是深色球，浅色模式是带光照的白球。
final class ProbeGlobeView: UIView, UIGestureRecognizerDelegate {
    struct Marker: Equatable {
        /// 城市或国家的唯一键，例如 “city:洛杉矶”、“country:US”。
        var id: String
        /// 所属国家，点选时按国家展开列表。
        var country: String
        var latitude: Double
        var longitude: Double
        var count: Int
        var health: ProbeCountryGroup.Health
    }

    var onSelect: ((String) -> Void)?

    private let sceneView = SCNView()
    private let scene = SCNScene()
    /// tilt 负责俯仰，spin 负责绕地轴转动；标记点挂在 spin 下，跟着地球一起转。
    private let tilt = SCNNode()
    private let spin = SCNNode()
    private let markerRoot = SCNNode()
    /// “你的位置”和连线。
    private let linkRoot = SCNNode()
    private var markers: [Marker] = []
    private var userCoordinate: (latitude: Double, longitude: Double)?
    private var resumeWork: DispatchWorkItem?
    private var hasFocused = false
    private let cameraNode = SCNNode()
    /// 惯性转动：松手时的角速度（弧度/秒），逐帧衰减。
    private var inertia: SIMD2<Float> = .zero
    private var inertiaLink: CADisplayLink?
    private var pinchStartDistance: Float = 0

    private static let defaultDistance: Float = 4.2
    private static let closestDistance: Float = 2.2
    /// 俯仰上限，留一点余量，避免转过头上下颠倒。
    private static let maxPitch: Float = 80 * .pi / 180

    private static let spinKey = "spin"
    private static let spinSeconds: TimeInterval = 90
    /// 深色模式：深色球、灰点；浅色模式：纯白球、深灰点，加光照、边缘压暗和外圈光晕。两张贴图各生成一次。
    private static let darkTexture = ProbeGlobeMath.dotTexture(fill: UIColor(white: 0.09, alpha: 1), dot: UIColor(white: 0.42, alpha: 1))
    private static let lightTexture = ProbeGlobeMath.dotTexture(
        fill: .white,
        dot: UIColor(red: 0x6E / 255, green: 0x6E / 255, blue: 0x73 / 255, alpha: 1)
    )
    /// 浅色模式下越靠近球的边缘越往浅灰过渡：点阵渐隐，轮廓也和同样偏白的页面背景分开。
    private static let lightRimShader = """
    float rim = 1.0 - saturate(dot(_surface.normal, _surface.view));
    _surface.diffuse.rgb = mix(_surface.diffuse.rgb, float3(0.84, 0.84, 0.86), pow(rim, 2.2) * 0.8);
    """
    private let sphereMaterial = SCNMaterial()
    private let lights = SCNNode()
    /// 浅色模式下垫在球后面的一圈淡灰光晕，略偏右下，像左上来光的投影。
    private let shadowView = ProbeGlobeHaloView()
    private var appliedStyle: UIUserInterfaceStyle?
    private var isDark: Bool { traitCollection.userInterfaceStyle == .dark }

    override init(frame: CGRect) {
        super.init(frame: frame)
        sceneView.scene = scene
        sceneView.backgroundColor = .clear
        sceneView.antialiasingMode = .multisampling4X
        sceneView.preferredFramesPerSecond = 60
        sceneView.isPlaying = true
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.accessibilityIdentifier = "probe-globe"
        shadowView.isUserInteractionEnabled = false
        addSubview(shadowView)
        addSubview(sceneView)
        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: bottomAnchor),
            sceneView.leadingAnchor.constraint(equalTo: leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        let camera = SCNCamera()
        camera.fieldOfView = 30
        cameraNode.camera = camera
        cameraNode.simdPosition = SIMD3(0, 0, Self.defaultDistance)
        scene.rootNode.addChildNode(cameraNode)
        sceneView.pointOfView = cameraNode

        scene.rootNode.addChildNode(tilt)
        tilt.addChildNode(spin)
        let sphere = SCNSphere(radius: 1)
        sphere.segmentCount = 96
        sphere.materials = [sphereMaterial]
        spin.addChildNode(SCNNode(geometry: sphere))
        // 浅色模式的光照：环境光加左上方一盏柔光，亮面接近纯白不过曝，背光面略暗，看出体积。标记点都是 constant，不受影响。
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 700
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 380
        key.simdEulerAngles = SIMD3(-0.5, -0.4, 0)
        lights.addChildNode(ambient)
        lights.addChildNode(key)
        scene.rootNode.addChildNode(lights)
        spin.addChildNode(markerRoot)
        spin.addChildNode(linkRoot)
        // 默认先看东亚。
        orient(latitude: 25, longitude: 115, animated: false)
        startSpinning()

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        sceneView.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        sceneView.addGestureRecognizer(pinch)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        sceneView.addGestureRecognizer(doubleTap)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.require(toFail: doubleTap)
        sceneView.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyAppearanceIfNeeded()
        updateShadowFrame()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyAppearanceIfNeeded()
    }

    /// 深浅色切换时换贴图、光照和投影，并按新配色重画标记与连线。
    private func applyAppearanceIfNeeded() {
        let style = traitCollection.userInterfaceStyle
        guard style != appliedStyle else { return }
        appliedStyle = style
        sphereMaterial.diffuse.contents = isDark ? Self.darkTexture : Self.lightTexture
        sphereMaterial.lightingModel = isDark ? .constant : .lambert
        lights.isHidden = isDark
        sphereMaterial.shaderModifiers = isDark ? nil : [.surface: Self.lightRimShader]
        shadowView.isHidden = isDark
        rebuildMarkers()
    }

    private func updateShadowFrame() {
        let radius = sphereScreenRadius
        let haloRadius = radius * ProbeGlobeHaloView.scale
        let offset = radius * 0.03
        shadowView.frame = CGRect(x: bounds.midX - haloRadius + offset, y: bounds.midY - haloRadius + offset * 1.5,
                                  width: haloRadius * 2, height: haloRadius * 2)
    }

    /// 第一次有数据时转到机器最多的国家。
    func setMarkers(_ markers: [Marker]) {
        guard markers != self.markers else { return }
        self.markers = markers
        rebuildMarkers()
        if !hasFocused, let busiest = markers.max(by: { $0.count < $1.count }) {
            hasFocused = true
            orient(latitude: busiest.latitude, longitude: busiest.longitude, animated: false)
        }
    }

    private func rebuildMarkers() {
        markerRoot.childNodes.forEach { $0.removeFromParentNode() }
        for marker in markers { addMarker(marker) }
        rebuildLinks()
    }

    /// 转到某个国家（机器最多的那个点），停一会儿再继续自转。
    func focus(country: String) {
        guard let marker = markers.filter({ $0.country == country }).max(by: { $0.count < $1.count }) else { return }
        focus(latitude: marker.latitude, longitude: marker.longitude)
    }

    /// 设置“你的位置”，从这里向每个点拉弧线；传 nil 去掉位置和连线。
    func setUserLocation(latitude: Double, longitude: Double) {
        userCoordinate = (latitude, longitude)
        rebuildLinks()
    }

    func clearUserLocation() {
        userCoordinate = nil
        rebuildLinks()
    }

    func focusOnUser() {
        guard let userCoordinate else { return }
        focus(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
    }

    private func focus(latitude: Double, longitude: Double) {
        stopInertia()
        pauseSpinning()
        orient(latitude: latitude, longitude: longitude, animated: true)
        scheduleResume(after: 5)
    }

    /// 页面不可见时停掉渲染，省电。
    func setActive(_ active: Bool) {
        if !active { stopInertia() }
        sceneView.isPlaying = active
        scene.isPaused = !active
    }

    // MARK: - 标记

    private func addMarker(_ marker: Marker) {
        let color = color(for: marker.health)
        let position = ProbeGlobeMath.point(latitude: marker.latitude, longitude: marker.longitude)
        // 机器越多点越大，封顶免得盖住邻国。
        let size = CGFloat(0.018 + 0.004 * Float(min(marker.count, 6)))
        let dot = SCNSphere(radius: size)
        dot.segmentCount = 16
        dot.firstMaterial?.lightingModel = .constant
        dot.firstMaterial?.diffuse.contents = color
        let dotNode = SCNNode(geometry: dot)
        dotNode.simdPosition = position * 1.008
        markerRoot.addChildNode(dotNode)

        markerRoot.addChildNode(makeRing(color: color, radius: size * 1.9, at: position * 1.004))
        guard marker.health == .offline || marker.health == .alert else { return }
        let ripple = makeRing(color: color, radius: size * 1.9, at: position * 1.004)
        ripple.runAction(ProbeGlobeMath.ripple())
        markerRoot.addChildNode(ripple)
    }

    // MARK: - 连线

    private func rebuildLinks() {
        linkRoot.childNodes.forEach { $0.removeFromParentNode() }
        guard let userCoordinate else { return }
        let origin = ProbeGlobeMath.point(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        // 深色球上用白点，白球上用黑点。
        let white: UIColor = isDark ? .white : .black
        let me = SCNSphere(radius: 0.02)
        me.segmentCount = 16
        me.firstMaterial?.lightingModel = .constant
        me.firstMaterial?.diffuse.contents = white
        let meNode = SCNNode(geometry: me)
        meNode.simdPosition = origin * 1.008
        linkRoot.addChildNode(meNode)
        linkRoot.addChildNode(makeRing(color: white, radius: 0.04, at: origin * 1.004))
        for (index, marker) in markers.enumerated() {
            let target = ProbeGlobeMath.point(latitude: marker.latitude, longitude: marker.longitude)
            // 和自己在同一个地方（例如本地机房）就不拉线。
            guard simd_distance(origin, target) > 0.02 else { continue }
            let points = ProbeGlobeMath.arc(from: origin, to: target)
            let color = color(for: marker.health)
            // 1 像素的线在白球上偏淡，浅色模式几乎不透明。
            linkRoot.addChildNode(makeLine(points, color: color.withAlphaComponent(isDark ? 0.55 : 0.9)))
            let traveller = SCNSphere(radius: 0.008)
            traveller.segmentCount = 12
            traveller.firstMaterial?.lightingModel = .constant
            traveller.firstMaterial?.diffuse.contents = color
            let travellerNode = SCNNode(geometry: traveller)
            travellerNode.simdPosition = points[0]
            travellerNode.opacity = 0
            // 错开起跑时间，避免所有光点同时出发。
            travellerNode.runAction(.sequence([.wait(duration: Double(index % 6) * 0.35), ProbeGlobeMath.travel(along: points, duration: 2)]))
            linkRoot.addChildNode(travellerNode)
        }
    }

    private func makeLine(_ points: [SIMD3<Float>], color: UIColor) -> SCNNode {
        let source = SCNGeometrySource(vertices: points.map { SCNVector3($0.x, $0.y, $0.z) })
        var indices: [Int32] = []
        for index in 0..<(points.count - 1) { indices += [Int32(index), Int32(index + 1)] }
        let geometry = SCNGeometry(sources: [source], elements: [SCNGeometryElement(indices: indices, primitiveType: .line)])
        geometry.firstMaterial?.lightingModel = .constant
        geometry.firstMaterial?.diffuse.contents = color
        geometry.firstMaterial?.writesToDepthBuffer = false
        return SCNNode(geometry: geometry)
    }

    private func makeRing(color: UIColor, radius: CGFloat, at position: SIMD3<Float>) -> SCNNode {
        let torus = SCNTorus(ringRadius: radius, pipeRadius: 0.0025)
        torus.ringSegmentCount = 48
        torus.firstMaterial?.lightingModel = .constant
        torus.firstMaterial?.diffuse.contents = color
        let node = SCNNode(geometry: torus)
        node.simdPosition = position
        // 圆环的轴（y）对准地表法线，环就平贴在地面上。
        node.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(position))
        return node
    }

    /// 状态色按当前深浅色模式取值；SceneKit 不会自动解析动态颜色。
    private func color(for health: ProbeCountryGroup.Health) -> UIColor {
        let color: UIColor
        switch health {
        case .online: color = .systemGreen
        case .alert: color = .systemOrange
        case .offline: color = .systemRed
        case .unknown: color = .systemGray
        }
        return color.resolvedColor(with: traitCollection)
    }

    // MARK: - 转动

    private func orient(latitude: Double, longitude: Double, animated: Bool) {
        // 把该经度转到正面：绕 y 转 -经度；走最短的方向，避免绕一大圈。
        let target = Float(-longitude * .pi / 180)
        var delta = (target - spin.simdEulerAngles.y).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        let pitch = min(max(Float(latitude * .pi / 180), -Self.maxPitch), Self.maxPitch)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.6 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        spin.simdEulerAngles.y += delta
        tilt.simdEulerAngles.x = pitch
        SCNTransaction.commit()
    }

    private func startSpinning() {
        guard spin.action(forKey: Self.spinKey) == nil else { return }
        spin.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: Self.spinSeconds)), forKey: Self.spinKey)
    }

    private func pauseSpinning() {
        resumeWork?.cancel()
        spin.removeAction(forKey: Self.spinKey)
    }

    private func scheduleResume(after seconds: TimeInterval) {
        resumeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.startSpinning() }
        resumeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// 手指移动一个视图宽度约转半圈；放大后转得慢一些，跟手。
    private var radiansPerPoint: Float {
        let zoom = Self.defaultDistance / max(cameraNode.simdPosition.z, Self.closestDistance)
        return .pi / Float(max(sceneView.bounds.width, 1)) / zoom
    }

    private func rotate(by delta: SIMD2<Float>) {
        spin.simdEulerAngles.y += delta.x
        tilt.simdEulerAngles.x = min(max(tilt.simdEulerAngles.x + delta.y, -Self.maxPitch), Self.maxPitch)
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            stopInertia()
            pauseSpinning()
        case .changed:
            let translation = pan.translation(in: sceneView)
            pan.setTranslation(.zero, in: sceneView)
            // 往下拖时北半球转向自己，和摸着真地球仪的方向一致。
            rotate(by: SIMD2(Float(translation.x), Float(translation.y)) * radiansPerPoint)
        case .ended, .cancelled, .failed:
            let velocity = pan.velocity(in: sceneView)
            startInertia(SIMD2(Float(velocity.x), Float(velocity.y)) * radiansPerPoint)
        default:
            break
        }
    }

    private func startInertia(_ velocity: SIMD2<Float>) {
        stopInertia()
        guard simd_length(velocity) > 0.3 else {
            scheduleResume(after: 3)
            return
        }
        inertia = velocity
        let link = CADisplayLink(target: ProbeWeakTarget(self), selector: #selector(ProbeWeakTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        inertiaLink = link
    }

    fileprivate func stepInertia(_ link: CADisplayLink) {
        let dt = Float(min(link.targetTimestamp - link.timestamp, 1.0 / 30))
        rotate(by: inertia * dt)
        // 每秒衰减到约 8%，大约一秒内停下。
        inertia *= pow(0.08, dt)
        guard simd_length(inertia) < 0.05 else { return }
        stopInertia()
        scheduleResume(after: 3)
    }

    private func stopInertia() {
        inertiaLink?.invalidate()
        inertiaLink = nil
        inertia = .zero
    }

    @objc private func handlePinch(_ pinch: UIPinchGestureRecognizer) {
        switch pinch.state {
        case .began:
            pinchStartDistance = cameraNode.simdPosition.z
            stopInertia()
            pauseSpinning()
        case .changed:
            let distance = pinchStartDistance / Float(max(pinch.scale, 0.01))
            cameraNode.simdPosition.z = min(max(distance, Self.closestDistance), Self.defaultDistance)
            updateShadowFrame()
        case .ended, .cancelled, .failed:
            scheduleResume(after: 3)
        default:
            break
        }
    }

    @objc private func handleDoubleTap() {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.35
        cameraNode.simdPosition.z = Self.defaultDistance
        SCNTransaction.commit()
        UIView.animate(withDuration: 0.35) { self.updateShadowFrame() }
    }

    @objc private func handleTap(_ tap: UITapGestureRecognizer) {
        let point = tap.location(in: sceneView)
        // 小点不好点中，按屏幕距离找最近的、在正面的标记。
        var best: (marker: Marker, distance: CGFloat)?
        for marker in markers {
            let local = ProbeGlobeMath.point(latitude: marker.latitude, longitude: marker.longitude)
            let world = markerRoot.simdConvertPosition(local, to: nil)
            guard world.z > 0.15 else { continue }
            let projected = sceneView.projectPoint(SCNVector3(world.x, world.y, world.z))
            let distance = hypot(CGFloat(projected.x) - point.x, CGFloat(projected.y) - point.y)
            if distance < 32, distance < (best?.distance ?? .infinity) { best = (marker, distance) }
        }
        guard let best else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        focus(latitude: best.marker.latitude, longitude: best.marker.longitude)
        onSelect?(best.marker.country)
    }

    // MARK: - UIGestureRecognizerDelegate

    /// 只在球面上开始的拖动才转地球；从球外的空白处开始拖，留给外层列表滚动。
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer is UIPanGestureRecognizer, gestureRecognizer.view === sceneView else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        let point = gestureRecognizer.location(in: sceneView)
        let center = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
        return hypot(point.x - center.x, point.y - center.y) <= sphereScreenRadius + 12
    }

    /// 球在屏幕上的半径：透视下轮廓半径 = 半高 / tan(半视角) / sqrt(距离² - 1)。
    private var sphereScreenRadius: CGFloat {
        let distance = Double(cameraNode.simdPosition.z)
        let halfFOV = Double(cameraNode.camera?.fieldOfView ?? 30) / 2 * .pi / 180
        return sceneView.bounds.height / 2 / CGFloat(tan(halfFOV) * sqrt(max(distance * distance - 1, 0.01)))
    }
}
