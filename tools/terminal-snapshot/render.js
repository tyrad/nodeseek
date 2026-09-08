// 此文件只运行在本地离线验证页，不读取原站的终端私有状态。
(async () => {
  const started = performance.now();
  const frame = () => new Promise(resolve => requestAnimationFrame(resolve));
  const host = document.getElementById('terminal');
  const term = new Terminal({
    cols: 100, rows: 50, scrollback: 2000,
    allowProposedApi: true, convertEol: true, disableStdin: true,
    cursorBlink: false, fontFamily: 'Menlo, monospace', fontSize: 14,
    lineHeight: 1.25,
    theme: {
      background: '#282c34', foreground: '#ffffff',
      black: '#2e3436', red: '#cc0000', green: '#4e9a06', yellow: '#c4a000',
      blue: '#3465a4', magenta: '#75507b', cyan: '#06989a', white: '#d3d7cf',
      brightBlack: '#555753', brightRed: '#ef2929', brightGreen: '#8ae234',
      brightYellow: '#fce94f', brightBlue: '#729fcf', brightMagenta: '#ad7fa8',
      brightCyan: '#34e2e2', brightWhite: '#eeeeec'
    }
  });
  try {
    term.open(host);
    await document.fonts.ready;
    await new Promise(resolve => term.write(report.ansi, resolve));
    const buffer = term.buffer.active;
    const rowCount = buffer.baseY + buffer.cursorY + 1;
    if (rowCount > 1000) throw new Error('报告超过验证程序的 1000 行限制');
    const lines = Array.from({ length: rowCount }, (_, i) => buffer.getLine(i).translateToString(true));
    const beforeResizeBaseY = buffer.baseY;

    // 先保留完整 scrollback，再扩展终端自身的 rows；只放大 WebView 不会展开终端。
    term.resize(term.cols, rowCount);
    term.scrollToTop();
    const rendered = new Promise(resolve => {
      const listener = term.onRender(() => { listener.dispose(); resolve(); });
    });
    term.refresh(0, term.rows - 1);
    await rendered;
    await frame();
    await frame();
    const after = Array.from({ length: rowCount }, (_, i) => term.buffer.active.getLine(i).translateToString(true));
    if (JSON.stringify(lines) !== JSON.stringify(after) || term.buffer.active.baseY !== 0) {
      throw new Error('扩展终端后内容发生变化');
    }
    const screen = host.querySelector('.xterm-screen');
    host.style.width = `${screen.getBoundingClientRect().width}px`;
    const rect = document.getElementById('report').getBoundingClientRect();
    const width = Math.ceil(rect.width), height = Math.ceil(rect.height);
    if (width * height * 4 > 24_000_000) throw new Error('2 倍截图超过 2400 万像素限制');
    const rows = Array.from(host.querySelectorAll('.xterm-rows > div'));
    if (rows.length !== rowCount) throw new Error(`DOM 行数不匹配：${rows.length}/${rowCount}`);
    const styles = Array.from(host.querySelectorAll('.xterm-rows span')).map(e => {
      const s = getComputedStyle(e);
      return { text: e.textContent, foreground: s.color, background: s.backgroundColor,
        weight: s.fontWeight, decoration: s.textDecorationLine };
    });
    window.snapshotResult = {
      id: report.id, title: report.title, width, height, rowCount,
      domRowCount: rows.length, beforeResizeBaseY, afterResizeBaseY: term.buffer.active.baseY,
      lines, styles, renderMilliseconds: Math.round(performance.now() - started)
    };
  } catch (error) {
    window.snapshotResult = { error: String(error) };
  }
})();
