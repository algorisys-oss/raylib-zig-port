// webdiff/run.mjs: run one browser example in headless Chrome and save its
// final frame.
//
//   node tools/webdiff/run.mjs <build-dir> <name> <out.png> [frames]
//
// <build-dir> holds <name>.js, <name>.wasm and (if the example has resources)
// <name>.data, as emitted by emcc with -sMODULARIZE -sEXPORT_NAME=createExample.
// The directory is served over HTTP (wasm cannot be fetched from file://)
// together with page.html, which freezes the clocks and starts the example.
// The example's shim writes /exdiff.png to MEMFS after N frames; this script
// copies that file out. Exit status: 0 saved, 1 the example failed or timed
// out. The browser log is printed on failure.
//
// WebGL runs on SwiftShader (--use-angle=swiftshader), Chrome's CPU renderer,
// so the result does not depend on the machine's GPU.

import { chromium } from 'playwright';
import { createServer } from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';
import { join, extname, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const [buildDir, name, outPath, frames = '240'] = process.argv.slice(2);
if (!buildDir || !name || !outPath) {
  console.error('usage: run.mjs <build-dir> <name> <out.png> [frames]');
  process.exit(2);
}
const timeoutMs = Number(process.env.WEBDIFF_TIMEOUT_MS || 120000);
const here = dirname(fileURLToPath(import.meta.url));

const types = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.wasm': 'application/wasm',
  '.data': 'application/octet-stream',
};

const server = createServer(async (req, res) => {
  const path = new URL(req.url, 'http://localhost').pathname.slice(1);
  const file = path === 'page.html' ? join(here, 'page.html') : join(buildDir, path);
  try {
    const body = await readFile(file);
    res.writeHead(200, { 'content-type': types[extname(file)] || 'application/octet-stream' });
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end();
  }
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const port = server.address().port;

const browser = await chromium.launch({
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});
let status = 1;
let log = [];
let page = null;
try {
  page = await browser.newPage({ viewport: { width: 1280, height: 960 } });
  page.on('pageerror', (error) => log.push('pageerror: ' + error.message));
  // A crashed tab (out of memory, a runaway loop) never satisfies the wait
  // below and never times out it either: fail it explicitly.
  const crashed = new Promise((_, reject) => page.on('crash', () => reject(new Error('the page crashed'))));
  page.on('console', (msg) => { if (msg.type() === 'error') log.push('console: ' + msg.text()); });
  await page.goto(`http://127.0.0.1:${port}/page.html?ex=${encodeURIComponent(name)}&frames=${frames}`);

  // The example is done when its shim has written the screenshot.
  const handle = await Promise.race([crashed, page.waitForFunction(() => {
    const w = window.webdiff;
    if (w.error) return { error: w.error };
    const fs = w.module && w.module.FS;
    if (fs && fs.analyzePath('/exdiff.png').exists) return { done: true };
    return false;
  }, null, { timeout: timeoutMs, polling: 50 })]);
  const result = await handle.jsonValue();
  log = log.concat(await page.evaluate(() => window.webdiff.log));
  if (result.error) throw new Error(result.error);

  const bytes = await page.evaluate(() => Array.from(window.webdiff.module.FS.readFile('/exdiff.png')));
  await writeFile(outPath, Buffer.from(bytes));
  status = 0;
} catch (error) {
  console.error(`${name}: ${error.message}`);
  // On a timeout the example's own output is the useful part.
  if (page && log.length === 0) {
    log = await page.evaluate(() => (window.webdiff ? window.webdiff.log : [])).catch(() => log);
  }
  for (const line of log) console.error('  | ' + line);
} finally {
  await browser.close();
  server.close();
}
process.exit(status);
