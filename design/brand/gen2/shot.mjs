import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
await p.goto('file://' + process.cwd() + '/board.html'); await p.waitForTimeout(400);
await p.screenshot({ path: process.argv[2], fullPage: true }); await b.close();
