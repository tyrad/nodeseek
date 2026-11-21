import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parseEnv } from 'node:util';
import { caseTest } from './cases.mjs';
import { agentFromWebDriverAgent } from './ios-agent.mjs';
import { prepareLogin } from './login-form.mjs';
import { assertSidebarAccount, nativeControls, request, simctl, waitFor } from './simulator.mjs';

const { SIMULATOR_ID: device, E2E_WDA_PORT: port, E2E_MEMBER_USERNAME: displayName, MIDSCENE_RUN_DIR: out } = process.env;
const bundle = 'com.mistj.nodeseek';
const id = 'logout-session';
const launch = layout => simctl('launch', '--terminate-running-process', device, bundle,
  '-appNavigationLayout.layout', layout, '-appNavigationLayout.hasConfirmedChoice', 'YES',
  '-appNavigationLayout.tabItems', '(home,notification,collections,me)', '-nodeSeekDebug.fileLoggingEnabled', 'YES');
const shot = suffix => simctl('io', device, 'screenshot', join(out, id + '-' + suffix + '.png'));

caseTest(id, { timeout: 300000 }, async () => {
  const agent = await agentFromWebDriverAgent({ wdaHost: '127.0.0.1', wdaPort: Number(port), reportFileName: id });
  try {
    const ui = await nativeControls();
    const matches = async predicate => (await request(ui.session + '/elements', { using: 'predicate string', value: predicate })).value;
    async function tapTab(title) {
      const button = await waitFor(async () => {
        const { value } = await request(ui.session + '/elements', { using: 'class chain',
          value: '**/XCUIElementTypeTabBar/**/XCUIElementTypeButton[`label == "' + title + '"`]' });
        return value[0]?.['element-6066-11e4-a52e-4f735466cecf'];
      }, '底部栏没有显示' + title);
      await request(ui.session + '/element/' + button + '/click', {});
    }
    const privateRows = () => matches('name BEGINSWITH "user-collection-post-" AND visible == 1');
    async function guestMe() {
      assert.match(await ui.element('me-profile-card', '/attribute/label'), /^未登录/);
      assert.ok(!await ui.find('me-profile-header'), '仍有已登录资料卡');
    }
    async function guestCollection() {
      await tapTab('我的收藏');
      assert.equal((await privateRows()).length, 0, '返回已经看过的收藏标签，仍显示旧账号收藏');
      await ui.get('user-collections-error-view');
      await ui.get('未获取到账号 UID，请重新登录后再试');
      assert.equal((await privateRows()).length, 0);
    }
    const log = join(simctl('get_app_container', device, bundle, 'data'), 'Library/Caches/Logs/nodeseek.log');
    const first = launch('tabs');
    await ui.tap('main-tab-me');
    if (!await ui.find('me-profile-header')) {
      const guest = await ui.get('me-profile-card');
      const { E2E_MEMBER_USERNAME: username, E2E_MEMBER_PASSWORD: password } =
        parseEnv(readFileSync(process.env.E2E_MEMBER_ENV_FILE, 'utf8'));
      assert.ok(username && password, '缺少本机测试凭据');
      const submit = await prepareLogin({ session: ui.session, log, entry: guest, username, password });
      await request(ui.session + '/element/' + submit + '/click', {});
    }
    assert.equal((await ui.element('me-profile-header', '/attribute/label')).split('，')[0], displayName);
    await tapTab('我的收藏');
    await waitFor(async () => (await privateRows()).length > 0, '登录前置条件不满足：收藏标签没有真实记录');
    await ui.tap('main-tab-me');
    await ui.tap('me-settings-button');
    const [cell] = await matches('name == "settings-logout-cell"');
    assert.ok(cell, '设置缺少退出登录入口');
    await request(ui.session + '/element/' + cell['element-6066-11e4-a52e-4f735466cecf'] + '/click', {});
    const confirm = await waitFor(async () => (await matches('type == "XCUIElementTypeButton" AND label == "退出登录" AND visible == 1'))[0], '未出现退出确认按钮');
    await request(ui.session + '/element/' + confirm['element-6066-11e4-a52e-4f735466cecf'] + '/click', {});
    await guestMe();
    shot('guest-me');
    await guestCollection();
    shot('guest-collection');
    await ui.tap('main-tab-me');
    await ui.tap('me-collections-row');
    await ui.get('关闭登录页');
    await waitFor(async () => (await matches('type == "XCUIElementTypeSecureTextField" AND label == "密码" AND visible == 1')).length,
      '退出后重新打开收藏未显示站点登录表单');
    await ui.tap('关闭登录页');
    await guestMe();

    const offset = readFileSync(log).length;
    const second = launch('tabs');
    assert.notEqual(first, second);
    await ui.tap('main-tab-me');
    await guestMe();
    const refreshed = await waitFor(() => readFileSync(log).subarray(offset).toString()
      .match(/账号信息解析完成，loggedIn=(true|false)/), '冷启动后未取得站点账号结果');
    assert.equal(refreshed[1], 'false', '站点在冷启动后恢复了旧登录身份');
    await guestMe();
    await guestCollection();
    await tapTab('通知');
    await ui.get('notification-login-button');
    launch('reading');
    await ui.tap('post-list-menu-button');
    await assertSidebarAccount(ui.session, '未登录');
    assert.equal(await ui.element('post-list-side-menu-account-header-button', '/attribute/label'), '登录账号');
    await agent.aiAssert('首页侧栏账号区域为未登录或提示登录。');
    shot('guest-sidebar');
  } catch (error) {
    shot('failure');
    throw error;
  } finally {
    await agent.destroy();
  }
});
