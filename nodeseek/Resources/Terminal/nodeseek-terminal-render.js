// 只处理本地传入的原文，不执行报告中的脚本，也不加载外部资源。
window.renderTerminalReport = async function (ansi) {
  const frame = () => new Promise(resolve => requestAnimationFrame(resolve));
  const term = new Terminal({
    cols: 100, rows: 50, scrollback: 2000, allowProposedApi: true,
    convertEol: true, disableStdin: true, cursorBlink: false,
    fontFamily: 'Menlo, monospace', fontSize: 14, lineHeight: 1.25,
    theme: {
      background: '#282c34', foreground: '#ffffff',
      black: '#2e3436', red: '#cc0000', green: '#4e9a06', yellow: '#c4a000',
      blue: '#3465a4', magenta: '#75507b', cyan: '#06989a', white: '#d3d7cf',
      brightBlack: '#555753', brightRed: '#ef2929', brightGreen: '#8ae234',
      brightYellow: '#fce94f', brightBlue: '#729fcf', brightMagenta: '#ad7fa8',
      brightCyan: '#34e2e2', brightWhite: '#eeeeec'
    }
  });
  const host = document.getElementById('terminal');
  term.open(host);
  await document.fonts.ready;
  await new Promise(resolve => term.write(ansi, resolve));
  const buffer = term.buffer.active;
  const count = buffer.baseY + buffer.cursorY + 1;
  if (count > 1000 || buffer.length >= 2050) throw new Error('报告过长，请前往网页查看');
  const lines = Array.from({length:count}, (_, i) => buffer.getLine(i).translateToString(true));
  term.resize(100, count);
  term.scrollToTop();
  const rendered = new Promise(resolve => {
    const subscription = term.onRender(() => { subscription.dispose(); resolve(); });
  });
  term.refresh(0, count - 1);
  await rendered;
  await frame();
  await frame();
  if (term.buffer.active.baseY !== 0) throw new Error('终端内容未完整展开');
  const after = Array.from({length:count}, (_, i) => term.buffer.active.getLine(i).translateToString(true));
  if (JSON.stringify(lines) !== JSON.stringify(after)) throw new Error('终端内容校验失败');
  host.style.width = host.querySelector('.xterm-screen').getBoundingClientRect().width + 'px';
  const rect = document.getElementById('report').getBoundingClientRect();
  return {width: Math.ceil(rect.width), height: Math.ceil(rect.height), text: lines.join('\n'), rows:count};
};
