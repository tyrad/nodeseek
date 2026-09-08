import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const directory = resolve(process.argv[2] ?? '.build/terminal-snapshot');
const inputs = JSON.parse(readFileSync(resolve(directory, 'inputs.json'), 'utf8'));

// 独立核对本次样本使用的 SGR、换行和退格覆盖；不是通用终端解析器。
function expectedLines(ansi) {
  return ansi.replace(/\x1b\[[0-9;]*m/g, '').replaceAll('\r\n', '\n').split('\n').map(line => {
    const cells = [];
    let cursor = 0;
    for (const character of line) {
      if (character === '\b') cursor = Math.max(0, cursor - 1);
      else cells[cursor++] = character;
    }
    return cells.join('').trimEnd();
  });
}

for (const input of inputs) {
  const result = JSON.parse(readFileSync(resolve(directory, input.id + '.json'), 'utf8'));
  assert.deepEqual(result.lines.map(line => line.trimEnd()), expectedLines(input.ansi), `${input.id}: 逐行文本不一致`);
  assert.equal(result.rowCount, result.domRowCount);
  assert.equal(result.afterResizeBaseY, 0);
  assert.ok(Math.abs(result.pixelWidth - result.width * 2) <= 2, '截图宽度必须为 2 倍');
  assert.ok(Math.abs(result.pixelHeight - result.height * 2) <= 2, '截图高度必须为 2 倍');
  assert.ok(result.pngBytes > 1000);
  if (input.id === 'long-report') {
    assert.equal(result.rowCount, 160);
    assert.ok(result.beforeResizeBaseY > 0, '长报告必须实际进入过 scrollback');
    assert.ok(result.lines[159].startsWith('ROW-160'));
  }
  if (input.id === 'controls') {
    const hasStyle = (text, predicate) => result.styles.some(style => style.text.includes(text) && predicate(style));
    assert.ok(hasStyle('RED', s => s.foreground === 'rgb(204, 0, 0)'));
    assert.ok(hasStyle('GREEN BACKGROUND', s => s.background === 'rgb(78, 154, 6)'));
    assert.ok(hasStyle('BOLD', s => Number(s.weight) >= 700));
    assert.ok(hasStyle('UNDERLINE', s => s.decoration.includes('underline')));
    assert.ok(hasStyle('TRUECOLOR', s => s.foreground === 'rgb(255, 128, 0)'));
    assert.ok(hasStyle('INDEXED', s => s.foreground === 'rgb(255, 0, 0)'));
  }
  console.log(`PASS ${input.id}: ${result.rowCount} 行，${result.pixelWidth}×${result.pixelHeight}，${Math.round(result.pngBytes / 1024)} KiB，${result.totalMilliseconds} ms`);
}
