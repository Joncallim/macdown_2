import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
const b = await chromium.launch({ proxy: { server: process.env.HTTPS_PROXY } });
const c = await b.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1280, height: 900 } }); const p = await c.newPage();
await p.goto('file://' + process.cwd() + '/validation.html'); await p.waitForLoadState('networkidle'); await p.evaluate(() => document.fonts.ready); await p.waitForTimeout(300);
const [y0, h] = (process.argv[3] || '0,0').split(',').map(Number);
await p.screenshot(h ? { path: process.argv[2], fullPage: true, clip: { x: 0, y: y0, width: 1280, height: h } } : { path: process.argv[2], fullPage: true }); await b.close();
