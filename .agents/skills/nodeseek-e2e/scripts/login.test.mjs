import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { once } from 'node:events';
import { fileURLToPath } from 'node:url';
import { prepareLogin } from './login-form.mjs';
import { caseTest } from './cases.mjs';
import { request, simctl, waitFor } from './simulator.mjs';
import { parseEnv } from 'node:util';
import { agentFromWebDriverAgent } from './ios-agent.mjs';

const env = process.env;
const bundle = 'com.mistj.nodeseek';

const checkProfile = env.E2E_LOGIN_ME === '1';
const id = checkProfile ? 'login-me' : 'member-login';

caseTest(id, async () => {
  const { E2E_MEMBER_USERNAME: username, E2E_MEMBER_PASSWORD: password } =
    parseEnv(readFileSync(env.E2E_MEMBER_ENV_FILE, 'utf8'));
  assert.ok(username?.trim() && password, 'memberEnvFile 需要提供测试用户名和密码');
  const displayName = env.E2E_MEMBER_USERNAME || username;
  const agent = await agentFromWebDriverAgent({
    wdaHost: '127.0.0.1', wdaPort: Number(env.E2E_WDA_PORT), reportFileName: id,
  });
  const artifact = name => join(env.MIDSCENE_RUN_DIR, name);
  let recording, finishedRecording;
  try {
    const { sessionId } = await request('/status');
    assert.ok(sessionId, '未取得当前 WDA 会话');
    const session = '/session/' + sessionId;
    async function find(predicate) {
      const { value } = await request(session + '/elements', { using: 'predicate string', value: predicate });
      return value[0]?.['element-6066-11e4-a52e-4f735466cecf'];
    }
    const button = label => find('type == "XCUIElementTypeButton" AND label == "' + label + '"');
    const click = id => request(session + '/element/' + id + '/click', {});
    async function assertIdentity() {
      await agent.aiAct('打开首页左上角账号侧栏；若侧栏已经打开，保持原处。');
      const label = await waitFor(() => find('name == "post-list-side-menu-name-label"'), '侧栏缺少账号名');
      const actual = await request(session + '/element/' + label + '/attribute/label');
      assert.ok(actual.value === displayName, '侧栏账号与本机配置不一致');
      assert.ok(await button('账号信息'), '侧栏仍未登录');
    }

    const data = simctl('get_app_container', env.SIMULATOR_ID, bundle, 'data');
    const log = join(data, 'Library/Caches/Logs/nodeseek.log');
    const launch = () => simctl('launch', '--terminate-running-process', env.SIMULATOR_ID, bundle,
      '-nodeSeekDebug.fileLoggingEnabled', 'YES');
    const first = launch();
    const byId = id => find('name == "' + id + '"');
    const rect = async id => (await request(session + '/element/' + id + '/rect')).value;
    let guest, card, screen;
    if (checkProfile) {
      await agent.aiAct('进入多 Tab 布局，若首次选择布局则选多 Tab 并保留默认栏目，关闭新功能介绍。点底部「我的」停在本页，不登录。');
      const guestCard = await byId('me-profile-card');
      assert.ok(guestCard, '游客「我的」缺少资料卡');
      const label = await request(session + '/element/' + guestCard + '/attribute/label');
      assert.match(label.value ?? '', /^未登录/);
      card = await rect(guestCard);
      screen = (await request(session + '/window/size')).value;
      simctl('io', env.SIMULATOR_ID, 'screenshot', artifact('me-guest.png'));
      await click(await byId('main-tab-notification'));
      guest = await waitFor(() => byId('notification-login-button'), '通知页未出现游客登录入口');
    } else {
      await agent.aiAct('使用阅读模式进入首页，再打开左上角账号侧栏。若有新功能介绍，点继续。停在账号侧栏，不进入登录页。');
      guest = await button('登录账号');
      assert.ok(guest, '前置条件未满足：需要处于游客状态的阅读模式测试设备');
    }
    const submit = await prepareLogin({ session, log, entry: guest, username, password });
    if (checkProfile) {
      recording = spawn('xcrun', ['simctl', 'io', env.SIMULATOR_ID, 'recordVideo', '--codec=h264', artifact('me-open.mov')]);
      finishedRecording = once(recording, 'close');
      let recorderStatus = '';
      recording.stderr.on('data', part => { recorderStatus += part; });
      await waitFor(() => recording.exitCode === null && recorderStatus.includes('Recording started'), '录屏未就绪');
    }
    await click(submit);
    await waitFor(async () => !(await button('关闭登录页')), '提交一次后登录页未自动关闭，请检查凭据或站点验证');
    if (checkProfile) {
      // 在点击前启动录屏。WDA 等待界面稳定和 AI 推理的耗时不能用来估算首帧。
      const me = await byId('main-tab-me');
      assert.ok(me, '登录关闭后未回到带「我的」标签的界面');
      await click(me);
      const header = await waitFor(() => byId('me-profile-header'), '我的页未恢复已登录资料卡');
      const identity = (await request(session + '/element/' + header + '/attribute/label')).value;
      assert.equal(identity?.split('，')[0], displayName, '我的资料卡账号错误');
      simctl('io', env.SIMULATOR_ID, 'screenshot', artifact('me-member.png'));
      recording.kill('SIGINT');
      await finishedRecording;
      recording = null;
      execFileSync('python3', [fileURLToPath(new URL('./profile-frames.py', import.meta.url)),
        env.MIDSCENE_RUN_DIR, JSON.stringify(card), JSON.stringify(screen)], { stdio: 'inherit' });
      return;
    }
    await assertIdentity();
    const second = launch();
    assert.notEqual(first, second, '未启动新进程');
    await assertIdentity();
  } finally {
    if (recording && recording.exitCode === null && recording.signalCode === null) {
      recording.kill('SIGINT');
      await finishedRecording;
    }
    await agent.destroy();
  }
});
