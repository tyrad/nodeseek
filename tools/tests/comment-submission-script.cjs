const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const swift = fs.readFileSync(path.join(__dirname, '../../nodeseek/AppRuntime/Web/AutomationScripts/CommentSubmissionAutomationScript.swift'), 'utf8');
const source = swift.split('"""')[1].replaceAll('\\\\', '\\');

async function run({ body = '{"success":true}', status = 200, rootExists = true, updateModel = true, networkError = false, hang = false, zeroSize = false, noTextarea = false } = {}) {
  let value = '';
  let clicks = 0;
  let apiWrites = 0;
  const editor = {
    tagName: 'TEXTAREA', className: '', value: '', focus() {}, click() {}, dispatchEvent() {},
    getBoundingClientRect: () => ({width: zeroSize ? 0 : 400, height: zeroSize ? 0 : 80}),
  };
  const button = {
    tagName: 'BUTTON', className: 'submit btn', innerText: '发布评论', disabled: false,
    getBoundingClientRect: () => ({width: zeroSize ? 0 : 80, height: zeroSize ? 0 : 40}),
    dispatchEvent() {},
    click() { clicks++; window.fetch('/api/content/new-comment'); },
  };
  const root = {
    tagName: 'DIV', className: 'md-editor', getBoundingClientRect: editor.getBoundingClientRect,
    querySelectorAll: selector => selector.startsWith('textarea') ? (noTextarea ? [] : [editor]) : [button],
  };
  const originalFetch = async () => {
    if (networkError) throw new Error('offline');
    if (hang) return new Promise(() => {});
    return {status, clone: () => ({text: async () => body})};
  };
  const window = {
    fetch: originalFetch, setTimeout, clearTimeout,
    location: {href: 'https://www.nodeseek.com/post-123-1'},
    getComputedStyle: () => ({display: 'block', visibility: 'visible'}),
    editor: {cme: () => ({
      setValue(text) { apiWrites++; if (updateModel) value = text; },
      getValue: () => value,
    })},
  };
  const document = {
    readyState: 'complete',
    querySelector(selector) {
      assert.equal(selector, '#editor', '不得退回全页面编辑器选择器');
      return rootExists ? root : null;
    },
  };
  const context = vm.createContext({
    window, document, commentText: '准确的评论内容', timeoutMs: rootExists ? 100 : 1,
    MouseEvent: class {}, console,
  });
  const result = await vm.runInContext('(async () => {' + source + '})()', context);
  assert.equal(window.fetch, originalFetch, '应恢复 fetch hook');
  return {result, clicks, apiWrites, value};
}

(async () => {
  let outcome = await run();
  assert.equal(outcome.result.ok, true);
  assert.equal(outcome.clicks, 1);
  assert.equal(outcome.apiWrites, 1);
  assert.equal(outcome.value, '准确的评论内容');
  outcome = await run({body: '{"success":false,"message":"请勿重复发布"}'});
  assert.equal(outcome.result.ok, false);
  assert.equal(outcome.result.reason, 'server_error');
  assert.equal(outcome.result.message, '请勿重复发布');
  for (const body of ['<html>验证页面</html>', '{}', 'null', '{"success":"true"}']) {
    outcome = await run({body});
    assert.equal(outcome.result.ok, false);
    assert.equal(outcome.result.reason, 'invalid_response');
  }
  outcome = await run({status: 500});
  assert.equal(outcome.result.ok, false);
  // 非 2xx + HTML 不能落入“结果未知”，要保留状态码。
  for (const status of [401, 403, 429, 502]) {
    outcome = await run({status, body: '<html>拦截页面</html>'});
    assert.equal(outcome.result.ok, false);
    assert.equal(outcome.result.reason, 'server_error', `${status} + HTML 应为 server_error`);
    assert.equal(outcome.result.statusCode, status);
    assert.equal(outcome.clicks, 1, '不得自动重试');
  }
  outcome = await run({rootExists: false});
  assert.equal(outcome.result.reason, 'editor_not_found');
  assert.equal(outcome.clicks, 0);
  outcome = await run({updateModel: false});
  assert.equal(outcome.result.reason, 'fill_failed');
  assert.equal(outcome.clicks, 0);
  outcome = await run({hang: true});
  assert.equal(outcome.result.reason, 'submit_timeout');
  assert.equal(outcome.clicks, 1);
  outcome = await run({networkError: true});
  assert.equal(outcome.result.reason, 'network_error');
  assert.equal(outcome.clicks, 1);
  outcome = await run({zeroSize: true});
  assert.equal(outcome.result.ok, true, '隐藏 WebView 的零尺寸不得阻止提交');
  assert.equal(outcome.apiWrites, 1);
  assert.equal(outcome.clicks, 1);
  outcome = await run({zeroSize: true, noTextarea: true});
  assert.equal(outcome.result.ok, true, 'API 就绪时不依赖内部 textarea');
  assert.equal(outcome.clicks, 1);
  console.log('17 个评论脚本行为场景通过');
})().catch(error => { console.error(error); process.exitCode = 1; });
