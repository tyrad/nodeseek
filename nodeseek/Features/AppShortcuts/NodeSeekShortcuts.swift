import AppIntents
import Foundation

@available(iOS 16, *)
struct NodeSeekShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CheckInIntent(), phrases: ["Check in with \(.applicationName)"],
                    shortTitle: "Daily check-in", systemImageName: "calendar.badge.checkmark")
        AppShortcut(intent: ProbeStatusIntent(), phrases: ["Check probe status in \(.applicationName)"],
                    shortTitle: "Probe status", systemImageName: "server.rack")
        AppShortcut(intent: DictatePostDraftIntent(), phrases: ["Take a note with \(.applicationName)"],
                    shortTitle: "Dictate a post draft", systemImageName: "waveform")
    }
}

@available(iOS 16, *)
struct CheckInIntent: AppIntent {
    static var title: LocalizedStringResource { "Daily check-in" }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog: IntentDialog
        switch await AutoCheckInModule.checkInFromSiri() {
        case .alreadyCheckedIn, .skipped("completed_today"):
            dialog = "You already checked in today."
        case .submitted(let message):
            if let message, !message.isEmpty {
                dialog = "\(message)"
            } else {
                dialog = "Checked in for today."
            }
        case .skipped("not_logged_in"):
            dialog = "Sign in to NS Connect first."
        default:
            dialog = "Check-in could not be confirmed. Try again in NS Connect."
        }
        return .result(dialog: dialog)
    }
}

@available(iOS 16, *)
struct ProbeStatusIntent: AppIntent {
    static var title: LocalizedStringResource { "Probe status" }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = ProbeInstanceStore.shared
        guard !store.instances.isEmpty else { return .result(dialog: "Add a probe in NS Connect first.") }
        let data = await ProbeWidgetLoader.load(store: store, service: ProbeService.shared)
        let entries = data.entries
        guard !entries.isEmpty else { return .result(dialog: "No node status is available.") }

        let fresh = entries.filter { !$0.isStale }
        var sentences = fresh.filter { $0.server.availability == .offline }.map { entry in
            if let date = entry.server.status?.sampledAt {
                return String(localized: "\(entry.displayName) is offline. Last report: \(date.formatted()).")
            }
            if let date = store.snapshot(for: entry.instanceID)?.fetchedAt {
                return String(localized: "\(entry.displayName) is offline. Last checked: \(date.formatted()).")
            }
            return String(localized: "\(entry.displayName) is offline.")
        }
        if sentences.isEmpty, !fresh.isEmpty {
            let online = fresh.filter { $0.server.availability == .online }.count
            sentences.append(String(localized: "Online: \(online)."))
        }
        if fresh.contains(where: { $0.server.availability == .unknown }) ||
            store.instances.contains(where: { store.snapshot(for: $0.id) == nil }) {
            sentences.append(String(localized: "Some statuses are unavailable."))
        }
        if fresh.count != entries.count, let date = data.updatedAt {
            sentences.append(String(localized: "Cached data as of \(date.formatted())."))
        }
        return .result(dialog: "\(sentences.joined(separator: " "))")
    }
}

@available(iOS 16, *)
struct DictatePostDraftIntent: AppIntent {
    static var title: LocalizedStringResource { "Dictate a post draft" }

    @Parameter(title: "Draft text", requestValueDialog: "What would you like to write?")
    var body: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw $body.needsValueError("What would you like to write?")
        }
        let saved = try await Self.save(body, in: UserDefaultsNewDiscussionDraftStore()) {
            try await $body.requestConfirmation(for: body, dialog: "Replace your existing post draft?")
        }
        return .result(dialog: saved ? "Draft saved." : "Your existing draft was kept.")
    }

    @MainActor
    static func save(_ body: String, in store: NewDiscussionDraftStoring,
                     confirm: () async throws -> Bool) async rethrows -> Bool {
        // 已打开的编辑器可能有尚未自动保存的输入。
        guard NewDiscussionRouter.activeDraftEditor == nil else { return false }
        let previous = store.load()
        if previous?.hasContent == true {
            guard try await confirm(), store.load() == previous,
                  NewDiscussionRouter.activeDraftEditor == nil else { return false }
        }
        store.save(NewDiscussionDraft(content: body))
        return true
    }
}
