import Foundation

struct StardustReceiptStatus {
    let paid: Bool
    let count: Int
    let total: Int

    /// 在当前站点会话里读取流水和浏览者身份。此处只读，付款始终在官网确认页完成。
    @MainActor
    static func load(_ receipt: StardustReceipt) async throws -> Self? {
        let result = try await withHiddenWebViewPageActionLoader(logMessage: "读取星辰收款流水") { loader in
            try Task.checkCancellation()
            return try await loader.runPageAutomationScript(
                pageURL: NodeSeekSite.baseURL, source: readScript,
                arguments: ["memberID": receipt.memberID, "refID": receipt.referenceID],
                timeoutInterval: 15, actionName: "星辰收款", reusesLoadedPage: false
            )
        }
        if result["guest"] as? Bool == true { return nil }
        guard let paid = result["paid"] as? Bool, result["ok"] as? Bool == true, let count = result["count"] as? Int,
              let total = result["total"] as? Int else {
            if let message = result["message"] as? String { throw UserContentClientError.rejected(message) }
            throw UserContentClientError.unsuccessfulResponse
        }
        return Self(paid: paid, count: count, total: total)
    }

    static let readScript = """
    const query = new URLSearchParams({member_id: memberID, ref_id: refID});
    const timer = new AbortController();
    const deadline = setTimeout(() => timer.abort(), timeoutMs);
    async function read(params) {
        const response = await fetch('/api/stardust/list?' + params, {cache: 'no-store', signal: timer.signal});
        if (!response.ok) throw new Error('HTTP ' + response.status);
        const page = await response.json();
        if (page.success !== true || !Array.isArray(page.records)) throw new Error(page.message || 'Invalid stardust ledger');
        return page;
    }
    try {
        if (!window.__config__) throw new Error('Missing site configuration');
        const viewer = window.__config__.user?.member_id;
        if (!(Number.isSafeInteger(viewer) && viewer > 0)) return {guest: true};
        const personal = new URLSearchParams(query);
        personal.set('peer_id', viewer);
        const paid = (await read(personal)).records.length > 0;
        let count = 0, total = 0;
        let before = Infinity;
        while (true) {
            const page = await read(query);
            count += page.records.length;
            for (const record of page.records) {
                if (!Number.isSafeInteger(record.diff)) throw new Error('Invalid stardust amount');
                if (record.diff > 0) total += record.diff;
            }
            if (!page.exist_more) break;
            if (!(Number.isSafeInteger(page.cursor) && page.cursor > 0 && page.cursor < before)) throw new Error('Invalid stardust cursor');
            before = page.cursor;
            query.set('before_id', before);
        }
        return {ok: true, count, total, paid};
    } catch (error) {
        return {ok: false, message: error.message};
    } finally {
        clearTimeout(deadline);
    }
    """
}
