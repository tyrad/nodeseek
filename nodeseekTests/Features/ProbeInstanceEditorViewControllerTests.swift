import XCTest
@testable import nodeseek

@MainActor
final class ProbeInstanceEditorViewControllerTests: XCTestCase {
    private final class StubService: ProbeFetching, @unchecked Sendable {
        let nodes: [ProbeNode]
        init(nodes: [ProbeNode]) { self.nodes = nodes }
        func testConnection(baseURL: URL, adapterID: String) async throws -> ProbeConnectionInfo {
            ProbeConnectionInfo(version: "1.6.1", nodes: nodes)
        }
        func snapshot(for instance: ProbeInstance, reloadNodes: Bool) async throws -> ProbeSnapshot {
            ProbeSnapshot(nodes: nodes, statuses: [:], fetchedAt: Date())
        }
        func history(for instance: ProbeInstance, nodeID: String, hours: Int) async throws -> [ProbeHistoryPoint] { [] }
        func forget(instanceID: UUID) async {}
    }

    /// 新增探针时服务器从 0 台变成多台，曾因先单独刷新名称行导致表格行数校验失败而闪退。
    func testSuccessfulConnectionOnNewProbeShowsServersAndFillsName() async throws {
        let suite = "probe-editor-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let nodes = ["a", "b"].map {
            ProbeNode(id: $0, name: $0, region: nil, group: nil, os: nil, cpuCores: nil, memTotal: nil, diskTotal: nil, weight: 0)
        }
        let editor = ProbeInstanceEditorViewController(instance: nil, store: ProbeInstanceStore(defaults: defaults), service: StubService(nodes: nodes))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UINavigationController(rootViewController: editor)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        editor.view.layoutIfNeeded()

        let tableView = try XCTUnwrap(editor.tableView)
        try await Task.sleep(nanoseconds: 200_000_000)
        tableView.layoutIfNeeded()
        XCTAssertEqual(tableView.numberOfRows(inSection: 2), 0)
        // 通过数据源取行，避免依赖窗口是否真正显示。
        let urlCell = try XCTUnwrap(editor.tableView(tableView, cellForRowAt: IndexPath(row: 1, section: 0)) as? ProbeTextFieldCell)
        urlCell.textField.text = "probe.example.com"
        urlCell.textField.sendActions(for: .editingChanged)

        let deadline = Date().addingTimeInterval(5)
        while tableView.numberOfRows(inSection: 2) != 2, Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(tableView.numberOfRows(inSection: 2), 2)
        XCTAssertEqual(editor.navigationItem.rightBarButtonItem?.isEnabled, true)
        tableView.layoutIfNeeded()
        let nameCell = try XCTUnwrap(editor.tableView(tableView, cellForRowAt: IndexPath(row: 2, section: 0)) as? ProbeTextFieldCell)
        XCTAssertEqual(nameCell.textField.text, "probe.example.com")
    }

    func testSingleAdapterTypeRowIsNotSelectable() throws {
        let editor = try makeEditor(service: StubService(nodes: []), engines: [komariEngine()])
        editor.loadViewIfNeeded()
        XCTAssertFalse(editor.tableView(editor.tableView, shouldHighlightRowAt: IndexPath(row: 0, section: 0)))
    }

    func testTypePickerListsAdaptersAndRetestsTheChosenOne() async throws {
        let service = RecordingService()
        let editor = try makeEditor(service: service, engines: [komariEngine(), monitorEngine()])
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UINavigationController(rootViewController: editor)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        editor.view.layoutIfNeeded()

        let tableView = try XCTUnwrap(editor.tableView)
        let typeIndex = IndexPath(row: 0, section: 0)
        XCTAssertTrue(editor.tableView(tableView, shouldHighlightRowAt: typeIndex))
        let typeCell = editor.tableView(tableView, cellForRowAt: typeIndex)
        XCTAssertEqual(typeCell.detailTextLabel?.text, "Komari")
        XCTAssertEqual(typeCell.accessibilityIdentifier, "probe-editor-type")

        editor.tableView(tableView, didSelectRowAt: typeIndex)
        let alert = try XCTUnwrap(editor.presentedViewController as? UIAlertController)
        XCTAssertEqual(alert.actions.compactMap(\.title), ["Komari", "极简探针", "取消"])
        editor.dismiss(animated: false)

        let urlCell = try XCTUnwrap(editor.tableView(tableView, cellForRowAt: IndexPath(row: 1, section: 0)) as? ProbeTextFieldCell)
        urlCell.textField.text = "probe.example.com"
        urlCell.textField.sendActions(for: .editingChanged)
        try await waitUntil { service.adapterIDs == ["komari"] && editor.navigationItem.rightBarButtonItem?.isEnabled == true }

        editor.selectAdapter("monitor")
        XCTAssertEqual(tableView.numberOfRows(inSection: 2), 0)
        XCTAssertEqual(editor.navigationItem.rightBarButtonItem?.isEnabled, false)
        try await waitUntil { service.adapterIDs == ["komari", "monitor"] && editor.navigationItem.rightBarButtonItem?.isEnabled == true }
        let updatedType = editor.tableView(tableView, cellForRowAt: typeIndex)
        XCTAssertEqual(updatedType.detailTextLabel?.text, "极简探针")
        let connection = editor.tableView(tableView, cellForRowAt: IndexPath(row: 0, section: 1))
        XCTAssertEqual(connection.detailTextLabel?.text, "1 台服务器")
        let footer = editor.tableView(tableView, titleForFooterInSection: 0)
        XCTAssertTrue(footer?.contains("公开状态页") == true)
    }

    private func makeEditor(service: ProbeFetching, engines: [ProbeAdapterEngine]) throws -> ProbeInstanceEditorViewController {
        let suite = "probe-editor-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return ProbeInstanceEditorViewController(
            instance: nil,
            store: ProbeInstanceStore(defaults: defaults),
            service: service,
            registry: ProbeAdapterRegistry(engines: engines)
        )
    }

    private func komariEngine() throws -> ProbeAdapterEngine {
        try ProbeAdapterEngine(data: BuiltinAdapterLoader.data(named: "probe-adapter-komari"))
    }

    private func monitorEngine() throws -> ProbeAdapterEngine {
        try ProbeAdapterEngine(data: BuiltinAdapterLoader.data(named: "probe-adapter-monitor"))
    }

    private func waitUntil(timeout: TimeInterval = 5, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(condition())
    }

    private final class RecordingService: ProbeFetching, @unchecked Sendable {
        private(set) var adapterIDs: [String] = []

        func testConnection(baseURL: URL, adapterID: String) async throws -> ProbeConnectionInfo {
            adapterIDs.append(adapterID)
            return ProbeConnectionInfo(
                version: adapterID == "monitor" ? nil : "1.6.1",
                nodes: [ProbeNode(id: "1", name: "n", region: nil, group: nil, os: nil, cpuCores: nil, memTotal: nil, diskTotal: nil, weight: 0)]
            )
        }

        func snapshot(for instance: ProbeInstance, reloadNodes: Bool) async throws -> ProbeSnapshot {
            ProbeSnapshot(nodes: [], statuses: [:], fetchedAt: Date())
        }

        func history(for instance: ProbeInstance, nodeID: String, hours: Int) async throws -> [ProbeHistoryPoint] { [] }
        func forget(instanceID: UUID) async {}
    }
}
