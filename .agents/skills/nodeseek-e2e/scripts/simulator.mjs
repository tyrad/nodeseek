import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { setTimeout as delay } from 'node:timers/promises';

const base = 'http://127.0.0.1:' + process.env.E2E_WDA_PORT;

export async function request(path, body) {
  const response = await fetch(base + path, {
    method: body === undefined ? 'GET' : 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(45000),
  });
  // WDA 的错误详情可能包含输入内容。
  assert.ok(response.ok, '本机 WebDriverAgent 操作失败，HTTP ' + response.status);
  return response.json();
}

export function simctl(...args) {
  return execFileSync('xcrun', ['simctl', ...args], { encoding: 'utf8' }).trim();
}

export async function waitFor(check, message) {
  const deadline = Date.now() + 60000;
  do {
    const result = await check();
    if (result) return result;
    await delay(750);
  } while (Date.now() < deadline);
  throw new Error(message);
}

export async function assertSidebarAccount(session, expectedName) {
  assert.ok(expectedName, '缺少测试账号名');
  // UIKit 将头像和昵称合并为一个可访问的按钮，精确读子标签可避免中文识别偏差。
  await waitFor(async () => {
    const { value } = await request(session + '/elements', {
      using: 'predicate string', value: 'name == "post-list-side-menu-name-label"',
    });
    const id = value[0]?.['element-6066-11e4-a52e-4f735466cecf'];
    if (!id) return false;
    const label = await request(session + '/element/' + id + '/attribute/label');
    return label.value === expectedName;
  }, '侧栏登录账号与配置不一致');
}

export async function nativeControls() {
  const { sessionId } = await request('/status');
  assert.ok(sessionId, '未取得当前 WDA 会话');
  const session = '/session/' + sessionId;
  async function find(name) {
    const { value } = await request(session + '/elements', {
      using: 'predicate string', value: 'name == ' + JSON.stringify(name) + ' AND visible == 1',
    });
    return value[0]?.['element-6066-11e4-a52e-4f735466cecf'];
  }
  const get = name => waitFor(() => find(name), '界面没有显示 ' + name);
  const element = async (name, path, payload) =>
    (await request(session + '/element/' + await get(name) + path, payload)).value;
  const tap = name => element(name, '/click', {});
  const readValue = async name => (await element(name, '/attribute/value')) ?? '';
  return { session, find, get, element, tap, value: readValue };
}
