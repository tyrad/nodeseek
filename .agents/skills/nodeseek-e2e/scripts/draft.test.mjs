import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { caseTest } from './cases.mjs';
import { agentFromWebDriverAgent } from './ios-agent.mjs';
import { assertSidebarAccount, nativeControls, simctl, waitFor } from './simulator.mjs';

const env = process.env;
const bundle = 'com.mistj.nodeseek';

async function checkDraft(report) {
  const title = '本机草稿 ' + randomUUID().slice(0, 8);
  const body = '第一行：中文草稿\n第二行：NodeSeek ' + title;
  const agent = await agentFromWebDriverAgent({
    wdaHost: '127.0.0.1', wdaPort: Number(env.E2E_WDA_PORT), reportFileName: report,
  });
  try {
    const { session, find, get, element, tap, value } = await nativeControls();
    const heading = 'new-discussion-title';
    const content = 'new-discussion-body';
    let lastPID;
    async function coldOpenComposer() {
      const launch = simctl('launch', '--terminate-running-process', env.SIMULATOR_ID, bundle);
      const pid = Number(launch.split(': ').at(-1));
      assert.ok(pid > 0 && pid !== lastPID, '需要在新进程中验证草稿');
      lastPID = pid;
      await tap('post-list-menu-button');
      await get('post-list-side-menu-account-header-button');
      await assertSidebarAccount(session, env.E2E_MEMBER_USERNAME);
      await tap('post-list-side-menu-new-discussion-button');
      await get(content);
    }
    async function assertBlank() {
      assert.ok(!await find('恢复') && !await find('上次的草稿'), '检测到已有草稿');
      assert.equal(await value(heading), '');
      assert.equal(await value(content), '');
    }
    await coldOpenComposer();
    await assertBlank();
    await element(heading, '/value', { text: title });
    await element(content, '/value', { text: body });
    assert.equal(await value(heading), title);
    assert.equal(await value(content), body);
    if (report === 'draft-save') {
      await tap('关闭');
      await tap('保存草稿并关闭');
      await waitFor(async () => !await find(content), '保存后未退出编辑器');
    } else {
      await get('已存本机');
      const observed = Date.now();
      if (report === 'draft-autosave-idle') await delay(2000);
      writeFileSync(join(env.MIDSCENE_RUN_DIR, report + '-timing.json'), JSON.stringify({
        title, status: '已存本机', millisecondsFromStatusToRelaunch: Date.now() - observed,
      }, null, 2));
    }

    await coldOpenComposer();
    await tap('恢复');
    assert.equal(await value(heading), title, '恢复后的标题与写入值不同');
    assert.equal(await value(content), body, '恢复后的正文与换行必须完整保留');
    await agent.aiAssert('发帖编辑器中，标题以「本机草稿」开头，正文可见「第一行」和「第二行」两行文字。');
    simctl('io', env.SIMULATOR_ID, 'screenshot', join(env.MIDSCENE_RUN_DIR, report + '-restored.png'));

    await tap('关闭');
    await tap('放弃草稿');
    await waitFor(async () => !await find(content), '放弃草稿后未退出编辑器');
    await coldOpenComposer();
    await assertBlank();
    await tap('关闭');
    await waitFor(async () => !await find(content), '空白编辑器未关闭');
  } catch (error) {
    simctl('io', env.SIMULATOR_ID, 'screenshot', join(env.MIDSCENE_RUN_DIR, report + '-failure.png'));
    throw error;
  } finally {
    await agent.destroy();
  }
}

caseTest('draft-save', () => checkDraft('draft-save'));
caseTest('draft-autosave', () => checkDraft('draft-autosave'));
caseTest('draft-autosave-idle', () => checkDraft('draft-autosave-idle'));
