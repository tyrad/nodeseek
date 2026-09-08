import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const output = resolve(process.argv[2] ?? '.build/terminal-snapshot');
mkdirSync(output, { recursive: true });
const fixture = JSON.parse(readFileSync(resolve(here, 'post-916971.json'), 'utf8'));
const script = readFileSync(resolve(here, 'node_modules/@xterm/xterm/lib/xterm.js'), 'utf8');
const css = readFileSync(resolve(here, 'node_modules/@xterm/xterm/css/xterm.css'), 'utf8');
const runtime = readFileSync(resolve(here, 'render.js'), 'utf8');

const reports = [...fixture.reports, {
  id: 'long-report',
  title: '长报告完整性验证',
  ansi: Array.from({ length: 160 }, (_, i) => `\x1b[${31 + i % 6}mROW-${String(i + 1).padStart(3, '0')} 中文列 | ${i * 17}\x1b[0m`).join('\n')
}, {
  id: 'controls',
  title: '终端控制字符验证',
  ansi: '\x1b[31mRED\x1b[0m default\n\x1b[42mGREEN BACKGROUND\x1b[0m\n\x1b[1mBOLD\x1b[0m \x1b[4mUNDERLINE\x1b[0m\nbar:     \b|42\n\x1b[38;2;255;128;0mTRUECOLOR\x1b[0m\n\x1b[38;5;196mINDEXED\x1b[0m\n<script>literal & safe</script>'
}];

// JSON 作为数据传入，报告里的标签和脚本不得变成可执行 HTML。
for (const report of reports) {
  const payload = JSON.stringify(report).replaceAll('<', '\\u003c');
  const html = `<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'">
<style>${css}
html,body { margin:0; padding:0; background:#282c34; }
#report { display:inline-block; padding:16px; background:#282c34; }
.xterm-viewport,.xterm-scrollable-element { overflow:hidden !important; }
.xterm-cursor { visibility:hidden; }
</style></head><body><div id="report"><div id="terminal"></div></div>
<script>${script.replaceAll('</script', '<\\/script')}</script>
<script>const report = ${payload};\n${runtime}</script></body></html>`;
  writeFileSync(resolve(output, `${report.id}.html`), html);
}
writeFileSync(resolve(output, 'inputs.json'), JSON.stringify(reports, null, 2));
console.log(`Prepared ${reports.length} offline reports in ${output}`);
