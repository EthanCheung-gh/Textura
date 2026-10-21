/**
 * QA harness: minimal Chrome DevTools Protocol client (no third-party deps).
 *
 * Usage: see smoke.mjs / flows.mjs. Node 22+ provides global WebSocket/fetch.
 */
import { spawn } from 'node:child_process';
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { setTimeout as sleep } from 'node:timers/promises';

export const CHROME_BIN = process.env.CHROME_BIN || 'google-chrome';
export const BASE_URL = process.env.TEXTURA_BASE_URL || 'http://localhost:1430';

export { sleep };

async function waitForHttp(url, timeout = 15000) {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    try {
      const response = await fetch(url);
      if (response.ok) return await response.json();
    } catch {
      /* not ready yet */
    }
    await sleep(120);
  }
  throw new Error(`Chrome debugging endpoint not reachable: ${url}`);
}

export async function launchChrome({ port = 9333, profileDir, width = 1440, height = 900 } = {}) {
  const profile = profileDir || `/tmp/textura-qa-profile-${port}`;
  rmSync(profile, { recursive: true, force: true });
  mkdirSync(profile, { recursive: true });

  const args = [
    '--headless=new',
    '--no-sandbox',
    '--disable-gpu',
    '--disable-dev-shm-usage',
    '--hide-scrollbars',
    '--force-device-scale-factor=1',
    '--no-first-run',
    '--no-default-browser-check',
    '--disable-background-networking',
    '--disable-sync',
    '--disable-extensions',
    '--mute-audio',
    '--metrics-recording-only',
    '--disable-features=Translate,MediaRouter,OptimizationHints',
    `--user-data-dir=${profile}`,
    `--window-size=${width},${height}`,
    `--remote-debugging-port=${port}`,
    'about:blank',
  ];

  const proc = spawn(CHROME_BIN, args, { stdio: ['ignore', 'pipe', 'pipe'] });
  const logChunks = [];
  proc.stdout.on('data', (chunk) => logChunks.push(String(chunk)));
  proc.stderr.on('data', (chunk) => logChunks.push(String(chunk)));

  const version = await waitForHttp(`http://127.0.0.1:${port}/json/version`);
  const list = await waitForHttp(`http://127.0.0.1:${port}/json/list`);
  const page = list.find((target) => target.type === 'page');
  if (!page) throw new Error('no page target in Chrome');

  return {
    proc,
    port,
    profile,
    browserVersion: version.Browser,
    wsUrl: page.webSocketDebuggerUrl,
    logs: () => logChunks.join(''),
    async close() {
      try {
        proc.kill('SIGTERM');
      } catch {
        /* ignore */
      }
      await sleep(300);
      try {
        proc.kill('SIGKILL');
      } catch {
        /* ignore */
      }
      rmSync(profile, { recursive: true, force: true });
    },
  };
}

export class Cdp {
  constructor(ws) {
    this.ws = ws;
    this.seq = 0;
    this.pending = new Map();
    this.listeners = new Map();
    ws.addEventListener('message', (event) => {
      const message = JSON.parse(event.data);
      if (message.id !== undefined) {
        const pending = this.pending.get(message.id);
        if (!pending) return;
        this.pending.delete(message.id);
        if (message.error) pending.reject(new Error(`${message.error.message} (${message.error.code})`));
        else pending.resolve(message.result);
        return;
      }
      for (const listener of this.listeners.get(message.method) ?? []) {
        try {
          listener(message.params);
        } catch (error) {
          console.error('listener error', error);
        }
      }
    });
  }

  static async connect(wsUrl) {
    const ws = new WebSocket(wsUrl);
    await new Promise((resolve, reject) => {
      ws.addEventListener('open', resolve, { once: true });
      ws.addEventListener('error', () => reject(new Error(`websocket failed: ${wsUrl}`)), {
        once: true,
      });
    });
    return new Cdp(ws);
  }

  on(method, listener) {
    const list = this.listeners.get(method) ?? [];
    list.push(listener);
    this.listeners.set(method, list);
  }

  send(method, params = {}, timeout = 30000) {
    const id = ++this.seq;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`CDP timeout: ${method}`));
      }, timeout);
      this.pending.set(id, {
        resolve: (value) => {
          clearTimeout(timer);
          resolve(value);
        },
        reject: (error) => {
          clearTimeout(timer);
          reject(error);
        },
      });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }

  close() {
    try {
      this.ws.close();
    } catch {
      /* ignore */
    }
  }
}

/** Page-level session with console/exception capture and high-level helpers. */
export class Page {
  constructor(cdp) {
    this.cdp = cdp;
    this.issues = [];
    this.issueSink = [];
    this.cdp.on('Runtime.consoleAPICalled', (params) => {
      if (params.type !== 'error' && params.type !== 'warning' && params.type !== 'assert') return;
      const text = params.args
        .map((arg) => arg.value ?? arg.description ?? arg.unserializableValue ?? arg.type)
        .join(' ');
      this.record({ level: params.type === 'assert' ? 'error' : params.type, source: 'console', text });
    });
    this.cdp.on('Runtime.exceptionThrown', ({ exceptionDetails }) => {
      const text =
        exceptionDetails.exception?.description ??
        `${exceptionDetails.text} ${exceptionDetails.exception?.value ?? ''}`;
      this.record({ level: 'error', source: 'uncaught', text: String(text).trim() });
    });
    this.cdp.on('Log.entryAdded', ({ entry }) => {
      if (entry.source === 'network' && /favicon/i.test(`${entry.url ?? ''}${entry.text ?? ''}`)) return;
      if (entry.level === 'error' || entry.level === 'warning') {
        this.record({
          level: entry.level,
          source: `log:${entry.source}`,
          text: `${entry.text}${entry.url ? ` [${entry.url}]` : ''}`,
        });
      }
    });
  }

  static async create(cdp) {
    const page = new Page(cdp);
    await cdp.send('Page.enable');
    await cdp.send('Runtime.enable');
    await cdp.send('Log.enable');
    return page;
  }

  record(issue) {
    this.issues.push({ ...issue, at: Date.now() });
    for (const sink of this.issueSink) sink(issue);
  }

  resetIssues() {
    this.issues = [];
  }

  async setViewport(width, height) {
    await this.cdp.send('Emulation.setDeviceMetricsOverride', {
      width,
      height,
      deviceScaleFactor: 1,
      mobile: false,
      screenWidth: width,
      screenHeight: height,
    });
  }

  async eval(expression, { timeout = 20000 } = {}) {
    const wrapped = `(async () => { ${expression} })()`;
    const result = await this.cdp.send(
      'Runtime.evaluate',
      { expression: wrapped, awaitPromise: true, returnByValue: true, userGesture: true },
      timeout,
    );
    if (result.exceptionDetails) {
      const detail =
        result.exceptionDetails.exception?.description ?? result.exceptionDetails.text ?? 'eval failed';
      throw new Error(`evaluate failed: ${detail}\n--- expression ---\n${expression.slice(0, 600)}`);
    }
    return result.result?.value;
  }

  async waitFor(expression, { timeout = 10000, interval = 100, label = expression } = {}) {
    const start = Date.now();
    let lastError = null;
    while (Date.now() - start < timeout) {
      try {
        const value = await this.eval(`return (${expression});`);
        if (value) return value;
      } catch (error) {
        lastError = error;
      }
      await sleep(interval);
    }
    throw new Error(`timeout waiting for: ${label}${lastError ? ` (last error: ${lastError.message})` : ''}`);
  }

  async goto(url, { route = null, timeout = 15000 } = {}) {
    this.resetIssues();
    await this.cdp.send('Page.navigate', { url });
    await this.waitFor(`document.readyState === 'complete'`, { timeout, label: 'document ready' });
    await this.waitFor(`!!document.querySelector('.shell')`, { timeout, label: 'app shell mounted' });
    if (route) {
      await this.waitFor(
        `document.documentElement.dataset.route === ${JSON.stringify(route)}`,
        { timeout, label: `route ${route}` },
      );
    }
    return this.issues;
  }

  async reload({ route = null } = {}) {
    this.resetIssues();
    await this.cdp.send('Page.reload', { ignoreCache: false });
    await this.waitFor(`document.readyState === 'complete'`, { label: 'reload ready' });
    await this.waitFor(`!!document.querySelector('.shell')`, { label: 'shell after reload' });
    if (route) {
      await this.waitFor(`document.documentElement.dataset.route === ${JSON.stringify(route)}`, {
        label: `route ${route} after reload`,
      });
    }
    return this.issues;
  }

  async screenshot(path) {
    const { data } = await this.cdp.send('Page.captureScreenshot', {
      format: 'png',
      fromSurface: true,
      captureBeyondViewport: false,
    });
    mkdirSync(path.replace(/\/[^/]+$/, ''), { recursive: true });
    writeFileSync(path, Buffer.from(data, 'base64'));
    return path;
  }

  /** Scroll element into view, then return its border box in CSS pixels. */
  async rect(selector, index = 0) {
    return this.eval(`
      const nodes = [...document.querySelectorAll(${JSON.stringify(selector)})];
      const el = nodes[${index}];
      if (!el) return null;
      el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' });
      // wait until the box stops moving (smooth scrolling / layout settling)
      let previous = null;
      for (let attempt = 0; attempt < 20; attempt += 1) {
        await new Promise((resolve) => requestAnimationFrame(resolve));
        const r = el.getBoundingClientRect();
        const box = { x: r.x, y: r.y, width: r.width, height: r.height };
        if (previous && Math.abs(previous.x - box.x) < 0.5 && Math.abs(previous.y - box.y) < 0.5 && box.width > 0) {
          return { ...box, cx: box.x + box.width / 2, cy: box.y + box.height / 2 };
        }
        previous = box;
      }
      const r = el.getBoundingClientRect();
      return { x: r.x, y: r.y, width: r.width, height: r.height, cx: r.x + r.width / 2, cy: r.y + r.height / 2 };
    `);
  }

  async exists(selector) {
    return this.eval(`return !!document.querySelector(${JSON.stringify(selector)});`);
  }

  async text(selector) {
    return this.eval(`
      const el = document.querySelector(${JSON.stringify(selector)});
      return el ? el.textContent.trim() : null;
    `);
  }

  async mouse(type, x, y, { buttons = 0, button = 'none', clickCount = 0 } = {}) {
    await this.cdp.send('Input.dispatchMouseEvent', {
      type,
      x: Math.round(x * 100) / 100,
      y: Math.round(y * 100) / 100,
      button,
      buttons,
      clickCount,
      pointerType: 'mouse',
    });
  }

  async clickAt(x, y) {
    await this.mouse('mouseMoved', x, y, { button: 'none' });
    await this.mouse('mousePressed', x, y, { buttons: 1, button: 'left', clickCount: 1 });
    await this.mouse('mouseReleased', x, y, { buttons: 0, button: 'left', clickCount: 1 });
  }

  async click(selector, index = 0) {
    const rect = await this.rect(selector, index);
    if (!rect) throw new Error(`click target not found: ${selector}`);
    await this.clickAt(rect.cx, rect.cy);
    return rect;
  }

  async drag(selector, dx, dy, { index = 0, steps = 12, settle = 120 } = {}) {
    const rect = await this.rect(selector, index);
    if (!rect) throw new Error(`drag target not found: ${selector}`);
    const startX = rect.cx;
    const startY = rect.cy;
    await this.mouse('mouseMoved', startX, startY, { button: 'none' });
    await sleep(40);
    await this.mouse('mousePressed', startX, startY, { buttons: 1, button: 'left', clickCount: 1 });
    await sleep(80);
    for (let step = 1; step <= steps; step += 1) {
      await this.mouse('mouseMoved', startX + (dx * step) / steps, startY + (dy * step) / steps, {
        buttons: 1,
        button: 'left',
      });
      await sleep(20);
    }
    await sleep(60);
    await this.mouse('mouseReleased', startX + dx, startY + dy, { buttons: 0, button: 'left', clickCount: 1 });
    await sleep(settle);
    return rect;
  }

  async key(key, { modifiers = 0, code = null, vk = 0 } = {}) {
    const base = { key, code: code ?? key, windowsVirtualKeyCode: vk, nativeVirtualKeyCode: vk, modifiers };
    await this.cdp.send('Input.dispatchKeyEvent', { type: 'rawKeyDown', ...base });
    await this.cdp.send('Input.dispatchKeyEvent', { type: 'keyUp', ...base });
  }

  /** Ctrl on Linux/Windows, Meta on macOS. QA runs on Linux → Control. */
  async shortcut(key, { shift = false } = {}) {
    const modifiers = 2 | (shift ? 8 : 0);
    const upper = key.toUpperCase();
    const vk = upper.charCodeAt(0);
    await this.key(key, { modifiers, code: `Key${upper}`, vk });
  }

  async insertText(text) {
    await this.cdp.send('Input.insertText', { text });
  }

  async selectAll() {
    await this.key('a', { modifiers: 2, code: 'KeyA', vk: 65 });
  }

  async typeInto(selector, text, { clear = true } = {}) {
    await this.click(selector);
    if (clear) await this.selectAll();
    await this.insertText(text);
  }

  async pressKey(key, options = {}) {
    await this.key(key, options);
  }

  /** Clear persisted app state and reload into a given route (fresh seed data). */
  async reset(route) {
    await this.goto(`${BASE_URL}/`, { route: null });
    await this.eval(`localStorage.clear(); return true;`);
    await this.goto(`${BASE_URL}/?route=${route}`, { route });
    // 侧栏视图数随版本增长（当前 7：今日/日历/OKR/GTD/甘特/SOP/设置），只断言已渲染。
    await this.waitFor(`document.querySelectorAll('.sidebar-nav .sidebar-link').length >= 6`, {
      label: 'sidebar ready',
    });
    await sleep(350);
  }

  async localStorage() {
    return this.eval(`return { ...localStorage };`);
  }
}

export async function withPage(fn, options = {}) {
  const chrome = await launchChrome(options);
  const cdp = await Cdp.connect(chrome.wsUrl);
  const page = await Page.create(cdp);
  try {
    await page.setViewport(options.width ?? 1440, options.height ?? 900);
    return await fn(page, chrome);
  } finally {
    page.close?.();
    cdp.close();
    await chrome.close();
  }
}

export function parseDateRange(label) {
  const match = label.match(/(\d{4}-\d{2}-\d{2}) 至 (\d{4}-\d{2}-\d{2})/);
  return match ? { start: match[1], end: match[2] } : null;
}

export function diffDays(a, b) {
  return Math.round((Date.parse(`${a}T00:00:00Z`) - Date.parse(`${b}T00:00:00Z`)) / 86400000);
}

/** Report helper: prints a compact JSON line per check. */
export function report(section, name, payload) {
  console.log(`\n### ${section} :: ${name}`);
  console.log(JSON.stringify(payload, null, 2));
}
