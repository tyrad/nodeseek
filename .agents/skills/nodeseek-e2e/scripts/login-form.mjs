import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { request, waitFor } from './simulator.mjs';

const loginURL = 'https://www.nodeseek.com/signIn.html';

// 凭据仅通过本机 WDA 填入站点登录表单，供录屏用例在提交前启动录制。
export async function prepareLogin({ session, log, entry, username, password }) {
  async function find(predicate) {
    const { value } = await request(session + '/elements', { using: 'predicate string', value: predicate });
    return value[0]?.['element-6066-11e4-a52e-4f735466cecf'];
  }
  const button = label => find('type == "XCUIElementTypeButton" AND label == "' + label + '"');
  const click = id => request(session + '/element/' + id + '/click', {});
  const offset = existsSync(log) ? readFileSync(log).length : 0;
  await click(entry);
  function officialFormLoaded() {
    if (!existsSync(log)) return false;
    const records = readFileSync(log).subarray(offset).toString();
    const last = [...records.matchAll(/BaseWebView didFinish: title=登录 NodeSeek, url=(\S+)/g)].at(-1);
    return last?.[1] === loginURL;
  }
  await waitFor(officialFormLoaded, '应用未确认加载 NodeSeek 官方登录地址');
  const secure = await waitFor(() => find('type == "XCUIElementTypeSecureTextField" AND label == "密码"'),
    '官方页面未显示密码表单，请检查网络或站点验证');
  const user = await find('type == "XCUIElementTypeTextField" AND label == "用户名/邮箱"');
  assert.ok(user, '官方页面缺少用户名输入框');
  assert.ok(officialFormLoaded(), '填写前页面地址已变化');
  await request(session + '/element/' + user + '/value', { text: username });
  await waitFor(async () => {
    const entered = await request(session + '/element/' + user + '/attribute/value');
    return entered.value === username;
  }, '用户名输入结果不符');
  assert.ok(officialFormLoaded(), '密码输入前页面地址已变化');
  await request(session + '/element/' + secure + '/value', { text: password });
  // WebKit 输入框聚焦会缩放页面，键盘也可能挡住提交按钮。
  const done = await button('完成') || await button('Done');
  if (done) await click(done);
  if (await find('label CONTAINS "Cloudflare 安全质询"')) {
    await waitFor(() => find('type == "XCUIElementTypeStaticText" AND (label == "成功！" OR label == "Success!")'),
      '站点等待人工验证，未提交登录');
  }
  const submit = await button('登录');
  assert.ok(submit && officialFormLoaded(), '提交前未找到官方登录表单的按钮');
  return submit;
}
