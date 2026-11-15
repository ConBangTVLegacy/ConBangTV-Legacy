// Xuất PNG từ design/icon.html bằng Chrome headless (cần Google Chrome + Node 22+).
//   node design/render.mjs variants [thư mục]   → mọi phương án (1024 / 144 / 114 / 57) để xem trước
//   node design/render.mjs ios <a|b|c>          → Icon*.png + Default*.png vào app/Resources
//   node design/render.mjs web <a|b|c> <thư mục> → logo.png, logo-1024.png, CydiaIcon.png cho trang giới thiệu
// Ảnh có kênh alpha (nền trong suốt); ảnh khởi động Default*.png nền đặc.
import { spawn } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const [mode = 'variants', a1, a2] = process.argv.slice(2);
const v = mode === 'variants' ? 'a' : (a1 || 'a');
const outDir = resolve(mode === 'variants' ? (a1 || 'preview') : mode === 'ios' ? (a2 || join(here, '../app/Resources')) : (a2 || 'web'));
const chrome = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const port = 9341;
const profile = mkdtempSync(join(tmpdir(), 'conbang-icon-'));
const proc = spawn(chrome, ['--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
  '--no-first-run', '--hide-scrollbars', 'about:blank'], { stdio: 'ignore' });

const sleep = ms => new Promise(r => setTimeout(r, ms));
let targets;
for (let i = 0; i < 40 && !targets; i++) {
  try { targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json(); } catch { await sleep(250); }
}
const ws = new WebSocket(targets.find(t => t.type === 'page').webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener('open', r));
let id = 0;
const pending = new Map();
ws.addEventListener('message', ev => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
});
const send = (method, params = {}) => new Promise(r => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
const evaluate = async expr => (await send('Runtime.evaluate', { expression: expr, returnByValue: true })).result.result.value;

await send('Page.enable');
await send('Emulation.setDefaultBackgroundColorOverride', { color: { r: 0, g: 0, b: 0, a: 0 } });
await send('Emulation.setDeviceMetricsOverride', { width: 2100, height: 1000, deviceScaleFactor: 1, mobile: false });
await send('Page.navigate', { url: pathToFileURL(join(here, 'icon.html')).href + `?mode=${mode}&v=${v}` });
for (let i = 0; i < 150 && (await evaluate('document.title')) !== 'ready'; i++) await sleep(200);
if ((await evaluate('document.title')) !== 'ready') { console.error('trang không sẵn sàng (phông Yuji Boku chưa tải?)'); process.exit(1); }

const items = await evaluate(`[...document.querySelectorAll('.asset')].map(d => { const r = d.firstElementChild.getBoundingClientRect(); return { name: d.dataset.name, x: r.x, y: r.y, w: r.width, h: r.height }; })`);
const total = Math.ceil(Math.max(...items.map(i => i.y + i.h)));
await send('Emulation.setDeviceMetricsOverride', { width: 2100, height: total, deviceScaleFactor: 1, mobile: false });
await sleep(500);
mkdirSync(outDir, { recursive: true });
for (const it of items) {
  const r = await send('Page.captureScreenshot', { format: 'png', clip: { x: it.x, y: it.y, width: it.w, height: it.h, scale: 1 }, captureBeyondViewport: true });
  const out = join(outDir, it.name);
  writeFileSync(out, Buffer.from(r.result.data, 'base64'));
  console.log('ghi', out, `${it.w}x${it.h}`);
}
ws.close();
proc.kill();
await sleep(300);
try { rmSync(profile, { recursive: true, force: true }); } catch {}
process.exit(0);
