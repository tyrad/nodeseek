import XCTest
#if SWIFT_PACKAGE
@testable import NodeSeekCore
#else
@testable import nodeseek
#endif

/// 三种探针的套餐字段写法不同，统一后的周期、计费方式和显示文案。
final class ProbePlanTests: XCTestCase {
    private let calendar = Calendar.current

    func testBillingCycleUnderstandsAllThreeSpellings() {
        // Komari：天数，-1 为一次性，区间与官方主题一致。
        XCTAssertEqual(ProbeBillingCycle(raw: "30"), .months(1))
        XCTAssertEqual(ProbeBillingCycle(raw: "31"), .months(1))
        XCTAssertEqual(ProbeBillingCycle(raw: "92"), .months(3))
        XCTAssertEqual(ProbeBillingCycle(raw: "365"), .months(12))
        XCTAssertEqual(ProbeBillingCycle(raw: "1095"), .months(36))
        XCTAssertEqual(ProbeBillingCycle(raw: "45"), .days(45))
        XCTAssertEqual(ProbeBillingCycle(raw: "-1"), .once)
        XCTAssertNil(ProbeBillingCycle(raw: "0"), "0 是未填")
        // CF-Server-Monitor：英文名。
        XCTAssertEqual(ProbeBillingCycle(raw: "year"), .months(12))
        XCTAssertEqual(ProbeBillingCycle(raw: "half_year"), .months(6))
        XCTAssertEqual(ProbeBillingCycle(raw: "three_years"), .months(36))
        // 极简探针：命名周期或 Nm。
        XCTAssertEqual(ProbeBillingCycle(raw: "monthly"), .months(1))
        XCTAssertEqual(ProbeBillingCycle(raw: "18m"), .months(18))
        XCTAssertEqual(ProbeBillingCycle(raw: "once"), .once)
        XCTAssertNil(ProbeBillingCycle(raw: "weird"))

        XCTAssertEqual(ProbeBillingCycle.months(12).unit, "年")
        XCTAssertEqual(ProbeBillingCycle.months(24).unit, "2 年")
        XCTAssertEqual(ProbeBillingCycle.months(18).unit, "18 个月")
        XCTAssertEqual(ProbeBillingCycle.days(45).unit, "45 天")
    }

    func testTrafficModeAliasesAndUsage() {
        XCTAssertEqual(ProbeTrafficMode(raw: "total"), .sum)
        XCTAssertEqual(ProbeTrafficMode(raw: "ul"), .up)
        XCTAssertEqual(ProbeTrafficMode(raw: "dl"), .down)
        XCTAssertEqual(ProbeTrafficMode(raw: "MAX"), .max)
        XCTAssertNil(ProbeTrafficMode(raw: ""))
        XCTAssertEqual(ProbeTrafficMode.sum.used(in: 3, out: 4), 7)
        XCTAssertEqual(ProbeTrafficMode.max.used(in: 3, out: 4), 4)
        XCTAssertEqual(ProbeTrafficMode.min.used(in: 3, out: 4), 3)
        XCTAssertEqual(ProbeTrafficMode.up.used(in: 3, out: 4), 4, "上行是出站")
        XCTAssertEqual(ProbeTrafficMode.down.used(in: 3, out: nil), 3)
        XCTAssertNil(ProbeTrafficMode.sum.used(in: 3, out: nil), "缺一项时不显示偏小的数字")
    }

    func testSummaryTextsAndLevels() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 9)))
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: now)! }

        let plan = ProbePlan(expiresAt: day(152), price: 99, currency: "¥", cycle: .months(12),
                             trafficLimit: 500 * 1_073_741_824, trafficMode: .sum, trafficResetDay: 1)
        let metrics = ProbeMetrics(trafficIn: 30 * 1_073_741_824, trafficOut: 26 * 1_073_741_824)
        let summary = try XCTUnwrap(ProbePlanSummary(plan: plan, metrics: metrics, now: now, calendar: calendar))
        XCTAssertEqual(summary.expiry, "152 天后到期")
        XCTAssertEqual(summary.expiryLevel, .normal)
        XCTAssertEqual(summary.price, "¥99/年")
        XCTAssertEqual(summary.traffic?.used, 56 * 1_073_741_824)
        XCTAssertEqual(summary.compact, ["152 天后到期", "¥99/年", "流量 11%"])

        let soon = ProbePlanSummary(plan: ProbePlan(expiresAt: day(3)), metrics: nil, now: now, calendar: calendar)
        XCTAssertEqual(soon?.expiry, "3 天后到期")
        XCTAssertEqual(soon?.expiryLevel, .warning)
        let today = ProbePlanSummary(plan: ProbePlan(expiresAt: day(0)), metrics: nil, now: now, calendar: calendar)
        XCTAssertEqual(today?.expiry, "今天到期")
        let overdue = ProbePlanSummary(plan: ProbePlan(expiresAt: day(-2)), metrics: nil, now: now, calendar: calendar)
        XCTAssertEqual(overdue?.expiry, "已过期 2 天")
        XCTAssertEqual(overdue?.expiryLevel, .critical)
        let longTerm = ProbePlanSummary(plan: ProbePlan(expiresAt: day(365 * 80)), metrics: nil, now: now, calendar: calendar)
        XCTAssertEqual(longTerm?.expiry, "长期有效")

        let over = ProbePlanSummary(plan: ProbePlan(trafficLimit: 4 * 1_099_511_627_776, trafficMode: .sum),
                                    metrics: ProbeMetrics(trafficIn: 3 * 1_099_511_627_776, trafficOut: 3 * 1_099_511_627_776), now: now)
        XCTAssertEqual(over?.traffic?.isOver, true)
        XCTAssertEqual(over?.trafficLevel, .critical)
        XCTAssertEqual(over?.compact, ["流量超出 2.00T"])

        XCTAssertEqual(ProbePlanSummary(plan: ProbePlan(price: -1), metrics: nil)?.price, "免费")
        XCTAssertEqual(ProbePlanSummary(plan: ProbePlan(price: 12, currency: "USD", cycle: .once), metrics: nil)?.price, "$12 一次性")
        XCTAssertEqual(ProbePlanSummary(plan: ProbePlan(price: 49.9, currency: "CAD", cycle: .months(1)), metrics: nil)?.price, "C$49.9/月")
        XCTAssertEqual(ProbePlanSummary(plan: ProbePlan(price: 5, currency: "CHF", cycle: .months(1)), metrics: nil)?.price, "CHF 5/月")
        XCTAssertNil(ProbePlanSummary(plan: ProbePlan(price: 0, currency: "$"), metrics: nil), "价格 0 是未填")
        XCTAssertNil(ProbePlanSummary(plan: nil, metrics: nil))
    }

    func testTagsSplitOnCommonSeparators() {
        XCTAssertEqual(ProbePlan.tags(from: "VPS,AI,落地机"), ["VPS", "AI", "落地机"])
        XCTAssertEqual(ProbePlan.tags(from: "中转;香港 ; "), ["中转", "香港"])
        XCTAssertEqual(ProbePlan.tags(from: ""), [])
    }
}
