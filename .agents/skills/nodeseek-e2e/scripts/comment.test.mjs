import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { caseTest } from './cases.mjs';
import { setTimeout as delay } from 'node:timers/promises';
import { agentFromWebDriverAgent } from './ios-agent.mjs';

const target = 'https://www.nodeseek.com/post-1016685-1';
const postID = '1016685';
const bundle = 'com.mistj.nodeseek';
const { SIMULATOR_ID: device, MIDSCENE_RUN_DIR: out, E2E_MEMBER_USERNAME: account } = process.env;
const sim = (...args) => execFileSync('xcrun', ['simctl', ...args], { encoding: 'utf8' }).trim();

async function wait(check, message, timeout = 40000) {
  const end = Date.now() + timeout;
  do {
    const result = await check();
    if (result) return result;
    await delay(500);
  } while (Date.now() < end);
  throw new Error(message);
}

caseTest('real-comment', { timeout: 600000 }, async () => {
  assert.ok(account, '需要已配置的测试账号');
  const pending = join(out, '..', 'comment-' + postID + '-' + device + '.json');
  const previous = existsSync(pending) && JSON.parse(readFileSync(pending, 'utf8'));
  const state = previous && previous.phase !== 'complete' ? previous : {
    target, account, marker: 'NS-' + randomUUID().slice(0, 8), phase: 'ready',
  };
  assert.equal(state.target, target);
  assert.equal(state.account, account);
  const original = 'NS Connect 回帖功能测试 ' + state.marker;
  const edited = original + '（已验证编辑）';
  function record(phase) {
    state.phase = phase;
    const json = JSON.stringify(state, null, 2) + '\n';
    writeFileSync(pending + '.tmp', json);
    renameSync(pending + '.tmp', pending);
    writeFileSync(join(out, 'comment.json'), json);
    console.log(phase, state.marker, state.editID || '');
  }
  record(state.phase);
  const agent = await agentFromWebDriverAgent({
    wdaHost: '127.0.0.1', wdaPort: Number(process.env.E2E_WDA_PORT), reportFileName: 'real-comment',
  });
  let session = '';
  async function wda(path, body) {
    const response = await fetch('http://127.0.0.1:' + process.env.E2E_WDA_PORT + session + path, {
      method: body === undefined ? 'GET' : 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body), signal: AbortSignal.timeout(45000),
    });
    const data = await response.json();
    assert.ok(response.ok, 'WDA ' + path + ' ' + (data.value?.error || response.status));
    return data;
  }
  async function elements(value) {
    const { value: matches } = await wda('/elements', { using: 'predicate string', value });
    return matches.map(item => item['element-6066-11e4-a52e-4f735466cecf']);
  }
  const find = async name => (await elements('name == ' + JSON.stringify(name)))[0];
  const get = name => wait(() => find(name), '找不到 ' + name);
  const attr = async (id, key) => (await wda('/element/' + id + '/attribute/' + key)).value;
  const press = id => wda('/element/' + id + '/click', {});
  const tap = async name => press(await get(name));
  const type = (id, text) => wda('/element/' + id + '/value', { text });
  const log = join(sim('get_app_container', device, bundle, 'data'), 'Library/Caches/Logs/nodeseek.log');
  const readLog = () => existsSync(log) ? readFileSync(log, 'utf8') : '';
  async function openPost(url = target) {
    assert.match(url, /^https:\/\/www\.nodeseek\.com\/post-1016685-\d+(?:#\d+)?$/);
    execFileSync('xcrun', ['simctl', 'launch', '--terminate-running-process', device, bundle,
      '-nodeSeekDebug.fileLoggingEnabled', 'YES'], { env: { ...process.env, SIMCTL_CHILD_NODESEEK_E2E_DETAIL_URL: url } });
    await tap('post-list-menu-button');
    const identity = await get('post-list-side-menu-name-label');
    await wait(async () => await attr(identity, 'label') === account, '当前账号与测试账号不符', 8000);
    await tap('post-list-side-menu-settings-button');
    await tap('settings-debug-cell');
    const offset = readLog().length;
    await tap('settings-detail-test-cell');
    await wait(() => readLog().slice(offset).includes('帖子详情加载成功，postID=' + postID + ','), '未能确认从固定链接加载指定帖子');
  }
  async function swipe() {
    const { value: { width, height } } = await wda('/window/size');
    await wda('/wda/dragfromtoforduration', { fromX: width * .5, toX: width * .5,
      fromY: height * .82, toY: height * .28, duration: .22 });
  }
  const editor = 'new-discussion-body';
  async function locateReply() {
    if (state.editID) {
      await tap(state.editID);
      const body = await get(editor);
      return { body, value: await attr(body, 'value') };
    }
    const visited = new Set();
    for (let i = 0; i < 35; i++) {
      const buttons = await elements('name BEGINSWITH "post-detail-edit-comment-" AND visible == 1');
      for (const button of buttons.reverse()) {
        const name = await attr(button, 'name');
        if (visited.has(name)) continue;
        visited.add(name);
        await press(button);
        const body = await get(editor);
        const value = await attr(body, 'value');
        if (value === original || value === edited) {
          const match = /^post-detail-edit-comment-(\d+)-(\d+)$/.exec(name);
          assert.ok(match, '无法取得楼层及评论 ID');
          state.editID = name;
          const floor = Number(match[1]);
          state.url = target.replace(/-1$/, '-' + Math.max(1, Math.ceil(floor / 10))) + '#' + floor;
          return { body, value };
        }
        await tap('关闭');
      }
      await swipe();
      if (i === 0) {
        const indicator = await find('post-detail-page-indicator');
        if (indicator && await attr(indicator, 'visible') === 'true') {
          await press(indicator);
          await tap('post-detail-page-picker-last');
        }
      }
    }
    throw new Error('未在自己的评论中找到本轮原文 ' + state.marker);
  }
  try {
    const status = await wda('/status');
    assert.ok(status.sessionId);
    session = '/session/' + status.sessionId;
    await openPost(state.url);
    if (state.phase === 'ready') {
      const reply = await wait(async () => (await find('post-detail-floating-reply-button')) || await find('post-detail-reply-button'), '缺少回复入口');
      await press(reply);
      const body = await get('post-detail-reply-text-view');
      assert.ok(!(await attr(body, 'value')), '回复框必须为空');
      await type(body, original);
      assert.equal(await attr(body, 'value'), original);
      const send = await get('post-detail-reply-send-button');
      const offset = readLog().length;
      record('publish-attempted');
      await press(send);
      await wait(() => {
        const events = readLog().slice(offset);
        assert.ok(!events.includes('Presenter 收到回复提交失败'), '站点拒绝回帖，请查看设备提示');
        return events.includes('Presenter 收到回复提交成功');
      }, '未能确认发送结果，保留标记供续验');
      await openPost();
    }
    const found = await locateReply();
    if (state.phase === 'publish-attempted') {
      assert.equal(found.value, original);
      record('original-verified');
    }
    if (state.phase === 'original-verified') {
      assert.equal(found.value, original);
      await wda('/element/' + found.body + '/clear', {});
      await type(found.body, edited);
      assert.equal(await attr(found.body, 'value'), edited);
      const save = await get('new-discussion-publish-button');
      const offset = readLog().length;
      record('edit-attempted');
      await press(save);
      await wait(() => readLog().slice(offset).includes('编辑评论成功后调度评论页刷新'), '未确认编辑成功，保留标记供续验');
      await openPost(state.url);
      assert.equal((await locateReply()).value, edited);
    } else {
      assert.equal(found.value, edited, '同一评论重读结果与修改后的文本不符');
    }
    await tap('关闭');
    await agent.aiAssert('帖子详情中可见用户「' + account + '」发表的评论，正文有「' + state.marker + '」和「已验证编辑」');
    sim('io', device, 'screenshot', join(out, 'edited-comment.png'));
    record('complete');
  } catch (error) {
    sim('io', device, 'screenshot', join(out, 'comment-failure.png'));
    throw error;
  } finally {
    await agent.destroy();
  }
});
