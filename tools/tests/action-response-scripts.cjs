const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.join(__dirname, '../..');
const names = ['PostCollection', 'PostUpvote', 'PostChickenLeg', 'PostDislike', 'CommentUpvote', 'CommentChickenLeg', 'CommentDislike'];
function source(file, index = 1) {
  return fs.readFileSync(path.join(root, file), 'utf8').split('"""')[index].replaceAll('\\\\', '\\');
}
async function run(script, body, status = 200, extra = {}) {
  const post = {getAttribute: () => '123', querySelectorAll: () => []};
  const fetch = async () => ({status, text: async () => body});
  return vm.runInNewContext('(async () => {' + script + '})()', {
    window: {fetch, setTimeout, clearTimeout}, document: {querySelector: () => post},
    timeoutMs: 100, commentID: 123, postID: 123, action: 'add', apiPath: '/test', bodyJSON: '', ...extra,
  });
}
(async () => {
  let count = 0;
  const scripts = names.map(name => source('nodeseek/AppRuntime/Web/AutomationScripts/' + name + 'AutomationScript.swift'));
  scripts.push(source('nodeseek/Features/Notification/NotificationMarkViewedAutomationScript.swift'));
  for (const script of scripts) {
    let timeoutCallback, resolveFetch, calls = 0, cleared = false;
    const pending = run(script, '', 200, {
      window: {
        setTimeout: fn => { timeoutCallback = fn; return 1; },
        clearTimeout: () => { cleared = true; },
        fetch: () => { calls++; return new Promise(resolve => { resolveFetch = resolve; }); },
      },
    });
    timeoutCallback();
    const timedOut = await pending;
    assert.equal(timedOut.reason, 'submit_timeout');
    assert.equal(cleared, true);
    resolveFetch({status: 200, text: async () => '{"success":true}'});
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(timedOut.reason, 'submit_timeout', '迟到的成功响应不能覆盖超时结果');
    assert.equal(calls, 1, '不得自动重试');
    const networkError = await run(script, '', 200, {
      window: {setTimeout, clearTimeout, fetch: async () => {throw new Error('offline');}},
    });
    assert.equal(networkError.reason, 'network_error');
    count += 2;

    for (const body of ['', '<html>challenge</html>', 'null', '[]', '{}', '{"success":"true"}']) {
      const result = await run(script, body);
      assert.equal(result.ok, false);
      assert.equal(result.reason, 'invalid_response');
      count++;
    }
    assert.equal((await run(script, '{"success":true}')).ok, true);
    assert.equal((await run(script, '{"success":false}')).reason, 'server_error');
    assert.equal((await run(script, '{"success":true}', 500)).ok, false);
    count += 3;

    // 非 2xx 不论正文是否为 JSON，都要保留状态码并归为 server_error，交给 Swift 区分明确失败。
    for (const [status, body] of [[401, '<html>login</html>'], [403, '<html>forbidden</html>'], [429, ''], [502, 'null'], [403, '{"message":"denied"}']]) {
      const result = await run(script, body, status);
      assert.equal(result.ok, false);
      assert.equal(result.reason, 'server_error', `${status} ${body} 应为 server_error`);
      assert.equal(result.statusCode, status);
      assert.equal(result.response.success, null);
      count++;
    }
    assert.equal((await run(script, '{"message":"denied"}', 403)).response.message, 'denied');
  }
  const discussion = source('nodeseek/AppRuntime/Web/AutomationScripts/NewDiscussionAutomationScript.swift', 3);
  let cleared = false;
  const result = await run(discussion, '', 200, {
    __config__: {user: {}}, crypto: require('node:crypto').webcrypto,
    AbortController, endpoint: '/test', payload: '{}',
    setTimeout, clearTimeout: timer => {cleared = true; clearTimeout(timer);},
    timeoutMs: 5,
    fetch: async (_, options) => ({
      status: 200,
      text: () => new Promise((resolve, reject) => {
        options.signal.addEventListener('abort', () => reject(Object.assign(new Error('aborted'), {name: 'AbortError'})));
      }),
    }),
  });
  assert.equal(result.reason, 'submit_timeout');
  assert.equal(cleared, true);
  const vote = source('nodeseek/AppRuntime/Web/AutomationScripts/VoteAutomationScript.swift');
  for (const items of [null, {}, [null], [1]]) {
    let calls = 0;
    const outcome = await run(vote, '', 200, {
      AbortController, setTimeout, clearTimeout, URL, TextEncoder,
      location: {href: 'https://www.nodeseek.com/post-1-1', origin: 'https://www.nodeseek.com'},
      navigator: {userAgent: 'test'}, crypto: require('node:crypto').webcrypto,
      operation: 'submit', voteID: 1, ids: [1],
      fetch: async () => {
        calls++;
        return {ok: true, status: 200, text: async () => JSON.stringify({success: true, vote: {id: 1, items}})};
      },
    });
    assert.equal(outcome.reason, 'invalid_response');
    assert.equal(calls, 1, '数据异常时不得发送投票');
    count++;
  }
  console.log(count + 1 + ' action response scenarios passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
