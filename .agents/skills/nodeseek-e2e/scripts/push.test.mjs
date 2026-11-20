import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { caseTest } from './cases.mjs';
import { agentFromWebDriverAgent } from './ios-agent.mjs';
import { assertSidebarAccount, nativeControls, request, simctl, waitFor } from './simulator.mjs';

const bundle = 'com.mistj.nodeseek';
const { SIMULATOR_ID: device, MIDSCENE_RUN_DIR: out, E2E_WDA_PORT: port } = process.env;
const home = 'post-list-menu-button';
const target = 'post-detail-edit-comment-18-14299736';
const screenshot = name => simctl('io', device, 'screenshot', join(out, name + '.png'));

async function matching(ui, predicate) {
  const { value } = await request(ui.session + '/elements', { using: 'predicate string', value: predicate });
  return value[0]?.['element-6066-11e4-a52e-4f735466cecf'];
}

async function prepare(ui) {
  simctl('launch', '--terminate-running-process', device, bundle);
  await ui.tap(home);
  await assertSidebarAccount(ui.session, process.env.E2E_MEMBER_USERNAME);
  await ui.tap('post-list-side-menu-settings-button');
  const settings = await waitFor(() => matching(ui, 'name == "settings-push-notification-cell"'), '未找到推送设置');
  await request(ui.session + '/element/' + settings + '/click', {});
  await ui.get('push-notification-status-cell');
  if (await ui.find('push-notification-enable-cell')) {
    await ui.tap('push-notification-enable-cell');
    const allow = await waitFor(() => matching(ui, 'type == "XCUIElementTypeButton" AND (label == "Allow" OR label == "允许")'), '系统没有出现允许通知按钮');
    await request(ui.session + '/element/' + allow + '/click', {});
    await waitFor(async () => !await ui.find('push-notification-enable-cell'), '通知权限未生效');
  }
  assert.ok(!await ui.find('push-notification-system-settings-cell'), '专用设备的系统通知权限已被拒绝');
  simctl('launch', '--terminate-running-process', device, bundle);
  await ui.get(home);
}

async function openFromNotification(ui, agent, id, mode) {
  await request('/wda/homescreen', {});
  if (mode === 'cold') simctl('terminate', device, bundle);
  const title = 'NS-E2E-' + randomUUID().slice(0, 8);
  const settings = application => request(ui.session + '/appium/settings', { settings: { defaultActiveApplication: application } });
  await settings('com.apple.springboard');
  try {
    execFileSync('xcrun', ['simctl', 'push', device, bundle, '-'], { input: JSON.stringify({
      aps: { alert: { title, body: '回归验证 · 第 18 楼' }, sound: 'default' },
      type: 'reply', post_id: '1016685', floor: '18', url: 'https://www.nodeseek.com/post-1016685-2#18',
    }) });
    const banner = () => matching(ui, 'name == "NotificationShortLookView" AND label CONTAINS ' + JSON.stringify(title) + ' AND visible == 1');
    let notification;
    for (let i = 0; i < 6 && !notification; i++) {
      notification = await banner();
      if (!notification) await delay(250);
    }
    if (!notification) {
      const { value: { width, height } } = await request(ui.session + '/window/size');
      await request(ui.session + '/wda/dragfromtoforduration', { fromX: width * .35, toX: width * .35, fromY: 1, toY: height * .85, duration: .45 });
      notification = await waitFor(banner, '系统通知中心未显示本轮推送 ' + title);
    }
    const { value: rect } = await request(ui.session + '/element/' + notification + '/rect');
    screenshot(id + '-notification');
    execFileSync('axe', ['tap', '--udid', device, '--tap-style', 'physical',
      '-x', String(Math.round(rect.x + rect.width / 2)), '-y', String(Math.round(rect.y + rect.height / 2))]);
  } finally {
    await settings('auto');
  }
  await ui.get(target);
  await agent.aiAssert('当前详情中可见第 18 楼的评论，正文包含 NS-f6b80106。');
  screenshot(id + '-detail');
  await ui.tap('BackButton');
  await ui.get(home);
  assert.ok(!await ui.find(target), '只返回一次后仍然停留在推送详情');
  screenshot(id + '-returned');
}

for (const mode of ['warm', 'cold']) {
  const id = 'push-' + mode;
  caseTest(id, { timeout: 180000 }, async () => {
    const agent = await agentFromWebDriverAgent({ wdaHost: '127.0.0.1', wdaPort: Number(port), reportFileName: id });
    try {
      const ui = await nativeControls();
      await prepare(ui);
      await openFromNotification(ui, agent, id, mode);
      if (mode === 'warm') await openFromNotification(ui, agent, id + '-second', mode);
    } catch (error) {
      screenshot(id + '-failure');
      throw error;
    } finally {
      await agent.destroy();
    }
  });
}
