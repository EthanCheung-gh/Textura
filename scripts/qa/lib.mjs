/**
 * QA harness: minimal Chrome DevTools Protocol client (no third-party deps).
 *
 * Usage: see smoke.mjs / flows.mjs. Node 22+ provides global WebSocket/fetch.
 *
 * 截图统一为 3:2（width / height = 1.5，即 width * 2 === height * 3）：
 * 默认视口是原生 3:2 的 1920×1280；非 3:2 的视口（如窄屏 1024×720）由
 * `Page.screenshot()` 自动补白到最近的 3:2，见 `Page.padPngToRatio()`。
 */
import { spawn } from 'node:child_process';
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { setTimeout as sleep } from 'node:timers/promises';

export const CHROME_BIN = process.env.CHROME_BIN || 'google-chrome';
export const BASE_URL = process.env.TEXTURA_BASE_URL || 'http://localhost:1430';

/**
 * 各路由的根选择器。路由级代码分割后，`dataset.route` 会先于懒加载 chunk 就绪，
 * 因此自动化必须等根节点出现，而不是固定 sleep。
 */
export const ROUTE_ROOT = {
  dashboard: '.dash-page',
  calendar: '.cal-page',
  okr: '.okr-page',
  gtd: '.gtd-page',
  gantt: '.gantt-page',
  sop: '.sop-page',
  settings: '.settings-page',
};

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

/**
 * 启动无头 Chrome，默认窗口 1920×1280——原生 3:2，与 README 主截图约定一致。
 * `--force-device-scale-factor=1` 保证窗口栅格 1:1，尺寸即截图像素尺寸。
 */
export async function launchChrome({ port = 9333, profileDir, width = 1920, height = 1280, extraArgs = [] } = {}) {
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
    ...extraArgs,
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

const PNG_SIGNATURE = 0x89504e47;
const PNG_IHDR = 0x49484452;

/**
 * 只读 PNG 头拿宽高：8 字节签名 + 4 字节块长度 + "IHDR" + width/height（big-endian）。
 * 不需要解码像素，避免为了一次比例检查引入解码器。
 */
export function pngSize(buffer) {
  if (buffer.length < 24) throw new Error('PNG payload too short');
  if (buffer.readUInt32BE(0) !== PNG_SIGNATURE || buffer.readUInt32BE(4) !== 0x0d0a1a0a) {
    throw new Error('unexpected screenshot payload: not a PNG');
  }
  if (buffer.readUInt32BE(12) !== PNG_IHDR) throw new Error('unexpected PNG: first chunk is not IHDR');
  const ihdrLength = buffer.readUInt32BE(8);
  if (ihdrLength !== 13) throw new Error(`unexpected PNG: IHDR length ${ihdrLength}, expected 13`);
  const width = buffer.readUInt32BE(16);
  const height = buffer.readUInt32BE(20);
  if (width === 0 || height === 0) {
    throw new Error(`unexpected PNG: zero dimension ${width}×${height}`);
  }
  return { width, height };
}

/** Page-level session with console/exception capture and high-level helpers. */
export class Page {
  constructor(cdp) {
    this.cdp = cdp;
    this.issues = [];
    this.issueSink = [];
    /** freezeClock() 注入脚本的 CDP identifier；null 表示当前没有冻结时钟。 */
    this.clockScriptId = null;
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

  /**
   * 冻结页面里的「今天」：通过 CDP Page.addScriptToEvaluateOnNewDocument 注入 Date 补丁，
   * 对本方法调用之后的每次导航/重载生效（已加载的文档不受影响，所以必须在首次 goto 之前调用）；
   * 并且必须在 `Page.create()` 之后调用——它负责 `Page.enable`，Page 域未开启时注入不会生效。
   *
   * 传入的是**本地时间字符串**（如 `'2026-10-21T12:00:00'`），epoch 在页面内按浏览器时区计算，
   * 避免 Node 与 Chrome 时区不一致导致 `localTodayKey()` 差一天。
   * 撤销见 `clearClock()`（已加载的文档仍需重载才恢复真实时间）。
   *
   * 补丁只替换 `globalThis.Date`，`Date.prototype` 保持原对象不变；`FixedDate extends Date`
   * 让 `Date.parse` / `Date.UTC` 等静态成员经 class 的 `[[Prototype]]` 继承自动保留，
   * 带参数的 `new Date(...)` 仍走原生路径。注意 `Date.now()` 被固定为常量，页面里用
   * `Date.now()` 差值做动画/防抖的逻辑会看到 0 流逝（`setTimeout` / `rAF` 不受影响）。
   *
   * @param {string} localIso 无时区后缀的本地时间字符串，默认触发农历「九月十二」的那一天正午。
   * @returns {Promise<{ identifier: string, localIso: string }>} CDP 注入脚本的 identifier。
   */
  async freezeClock(localIso = '2026-10-21T12:00:00') {
    // 重复调用时先移除旧补丁，避免两条脚本叠加（后注入的会把前一个 FixedDate 当成 RealDate）。
    if (this.clockScriptId) await this.clearClock();

    const source = [
      '(() => {',
      `  const localIso = ${JSON.stringify(localIso)};`,
      '  const RealDate = Date;',
      '  // epoch 在页面内计算：字符串不带时区后缀时按浏览器本地时区解析。',
      '  const FIXED = new RealDate(localIso).getTime();',
      "  if (Number.isNaN(FIXED)) throw new Error('freezeClock: invalid local time string: ' + localIso);",
      '  // class 继承 RealDate：静态成员（parse/UTC）经 [[Prototype]] 自动继承，这里只覆盖 now()。',
      '  class FixedDate extends RealDate {',
      '    constructor(...args) {',
      '      if (args.length === 0) super(FIXED);',
      '      else super(...args);',
      '    }',
      '    static now() {',
      '      return FIXED;',
      '    }',
      '  }',
      '  globalThis.Date = FixedDate;',
      '})();',
    ].join('\n');

    const { identifier } = await this.cdp.send('Page.addScriptToEvaluateOnNewDocument', { source });
    this.clockScriptId = identifier;
    return { identifier, localIso };
  }

  /**
   * 撤销 `freezeClock()`：移除注入脚本，之后的导航/重载恢复真实时间。
   * 未冻结时静默返回 `false`（不抛错），便于在 finally 里无条件调用。
   */
  async clearClock() {
    const identifier = this.clockScriptId;
    if (!identifier) return false;
    this.clockScriptId = null;
    await this.cdp.send('Page.removeScriptToEvaluateOnNewDocument', { identifier });
    return true;
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
      await this.waitRouteRoot(route, timeout);
    }
    return this.issues;
  }

  /** 等待懒加载路由真正挂载（根选择器出现）。 */
  async waitRouteRoot(route, timeout = 20000) {
    const root = ROUTE_ROOT[route];
    if (!root) return;
    await this.waitFor(`!!document.querySelector(${JSON.stringify(root)})`, {
      timeout,
      label: `route root ${root}`,
    });
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
      await this.waitRouteRoot(route);
    }
    return this.issues;
  }

  /**
   * 截图写盘。默认把非 3:2 的截图补白到最近的 3:2（README 截图约定）；
   * 已经 3:2 时直接写 CDP 原始字节，不做任何重新编码。
   * 需要原始（非 3:2）截图时传 `{ pad: false }`。
   */
  async screenshot(path, { pad = true } = {}) {
    const { data } = await this.cdp.send('Page.captureScreenshot', {
      format: 'png',
      fromSurface: true,
      captureBeyondViewport: false,
    });
    const png = pad ? await this.padPngToRatio(data, 3, 2) : data;
    mkdirSync(path.replace(/\/[^/]+$/, ''), { recursive: true });
    writeFileSync(path, Buffer.from(png, 'base64'));
    return path;
  }

  /**
   * 把 PNG base64 补白到 ratioW:ratioH（默认 3:2）。已符合比例时原样返回，字节不变。
   *
   * 补白带颜色延续相邻边缘：取该边缘最近的 8 行/8 列，按列/行取 RGB 中位数，
   * 生成 1px 色带后复制成整条补白带；补白居中，奇数差放在下/右。
   * 全部在页面内用 canvas 完成（零依赖，不引第三方图像库），画完再画原图。
   *
   * 目标尺寸用格点法求解（k = max(ceil(w/ratioW), ceil(h/ratioH))，目标 = ratioW*k × ratioH*k），
   * 保证输出严格落在比例格点上，而不是 round() 后可能差 1px 的近似值。
   * 画完再用 pngSize() 后置校验，任何不符合比例的落盘都变成响亮失败。
   */
  async padPngToRatio(base64, ratioW = 3, ratioH = 2) {
    const { width, height } = pngSize(Buffer.from(base64, 'base64'));
    // 已符合比例：原样返回，字节与 CDP 输出完全一致（不重新编码）
    if (width * ratioH === height * ratioW) return base64;

    // 格点法：取不小于当前尺寸的最小比例格点，保证 targetWidth * ratioH === targetHeight * ratioW
    const k = Math.max(Math.ceil(width / ratioW), Math.ceil(height / ratioH));
    const targetWidth = ratioW * k;
    const targetHeight = ratioH * k;

    const padX = targetWidth - width;
    const padY = targetHeight - height;
    const left = Math.floor(padX / 2);
    const top = Math.floor(padY / 2);
    const right = padX - left;
    const bottom = padY - top;

    const dataUrl = `data:image/png;base64,${base64}`;
    const result = await this.eval(
      `
      const image = new Image();
      image.src = ${JSON.stringify(dataUrl)};
      await image.decode();
      const sw = image.naturalWidth;
      const sh = image.naturalHeight;
      const tw = ${targetWidth};
      const th = ${targetHeight};
      const left = ${left};
      const top = ${top};
      const right = ${right};
      const bottom = ${bottom};

      const sourceCanvas = document.createElement('canvas');
      sourceCanvas.width = sw;
      sourceCanvas.height = sh;
      const sourceCtx = sourceCanvas.getContext('2d', { willReadFrequently: true });
      sourceCtx.drawImage(image, 0, 0);
      const pixels = sourceCtx.getImageData(0, 0, sw, sh).data;

      const median = (values) => {
        const sorted = [...values].sort((a, b) => a - b);
        const mid = sorted.length >> 1;
        return sorted.length % 2 ? sorted[mid] : Math.round((sorted[mid - 1] + sorted[mid]) / 2);
      };
      // 某一列在 y0..y1 行内的中位 RGB（用于上下补白带）
      const columnColor = (x, y0, y1) => {
        const r = [];
        const g = [];
        const b = [];
        for (let y = y0; y <= y1; y += 1) {
          const i = (y * sw + x) * 4;
          r.push(pixels[i]);
          g.push(pixels[i + 1]);
          b.push(pixels[i + 2]);
        }
        return [median(r), median(g), median(b)];
      };
      // 某一行在 x0..x1 列内的中位 RGB（用于左右补白带）
      const rowColor = (y, x0, x1) => {
        const r = [];
        const g = [];
        const b = [];
        for (let x = x0; x <= x1; x += 1) {
          const i = (y * sw + x) * 4;
          r.push(pixels[i]);
          g.push(pixels[i + 1]);
          b.push(pixels[i + 2]);
        }
        return [median(r), median(g), median(b)];
      };

      const out = document.createElement('canvas');
      out.width = tw;
      out.height = th;
      const ctx = out.getContext('2d');
      ctx.imageSmoothingEnabled = false;

      // 水平色带：整宽（边缘外按最近列取样），1px 高，再纵向复制成 top/bottom 高
      const drawHorizontalBand = (y0, y1, destY, destHeight) => {
        if (destHeight <= 0) return;
        const band = new ImageData(tw, 1);
        for (let x = 0; x < tw; x += 1) {
          const sourceX = Math.min(sw - 1, Math.max(0, x - left));
          const [r, g, b] = columnColor(sourceX, y0, y1);
          const i = x * 4;
          band.data[i] = r;
          band.data[i + 1] = g;
          band.data[i + 2] = b;
          band.data[i + 3] = 255;
        }
        const strip = document.createElement('canvas');
        strip.width = tw;
        strip.height = 1;
        strip.getContext('2d').putImageData(band, 0, 0);
        ctx.drawImage(strip, 0, 0, tw, 1, 0, destY, tw, destHeight);
      };
      // 垂直色带：整高，1px 宽，横向复制成 left/right 宽
      const drawVerticalBand = (x0, x1, destX, destWidth) => {
        if (destWidth <= 0) return;
        const band = new ImageData(1, sh);
        for (let y = 0; y < sh; y += 1) {
          const [r, g, b] = rowColor(y, x0, x1);
          const i = y * 4;
          band.data[i] = r;
          band.data[i + 1] = g;
          band.data[i + 2] = b;
          band.data[i + 3] = 255;
        }
        const strip = document.createElement('canvas');
        strip.width = 1;
        strip.height = sh;
        strip.getContext('2d').putImageData(band, 0, 0);
        ctx.drawImage(strip, 0, 0, 1, sh, destX, top, destWidth, sh);
      };

      const edgeRows = Math.min(8, sh);
      const edgeColumns = Math.min(8, sw);
      drawHorizontalBand(0, edgeRows - 1, 0, top);
      drawHorizontalBand(sh - edgeRows, sh - 1, top + sh, bottom);
      drawVerticalBand(0, edgeColumns - 1, 0, left);
      drawVerticalBand(sw - edgeColumns, sw - 1, left + sw, right);
      ctx.drawImage(image, left, top);

      return out.toDataURL('image/png');
    `,
      { timeout: 60000 },
    );

    const prefix = 'data:image/png;base64,';
    if (typeof result !== 'string' || !result.startsWith(prefix)) {
      throw new Error('padPngToRatio: canvas returned no PNG data URL');
    }
    const padded = result.slice(prefix.length);
    // 后置断言：确认落盘尺寸严格满足比例，避免静默写出不合规截图
    const out = pngSize(Buffer.from(padded, 'base64'));
    if (out.width * ratioH !== out.height * ratioW) {
      throw new Error(
        `padPngToRatio: padded screenshot is not ${ratioW}:${ratioH} — ` +
          `expected ${targetWidth}×${targetHeight}, got ${out.width}×${out.height}`,
      );
    }
    return padded;
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
    await page.setViewport(options.width ?? 1920, options.height ?? 1280);
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
