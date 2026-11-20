import test from 'node:test';
import cases from './cases.json' with { type: 'json' };

export function caseTest(id, ...args) {
  if (!Object.hasOwn(cases, id)) throw new Error('用例目录缺少 ' + id);
  if (!process.env.E2E_SELECTED_CASE || process.env.E2E_SELECTED_CASE === id) {
    test('[' + id + '] ' + cases[id].title, ...args);
  }
}
