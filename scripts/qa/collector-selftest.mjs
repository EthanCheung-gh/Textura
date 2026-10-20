/**
 * Proves the console/exception collector is live: injects one console.error,
 * one console.warn and one uncaught exception, then expects all three to be seen.
 */
import { BASE_URL, sleep, withPage } from './lib.mjs';

await withPage(async (page) => {
  await page.goto(`${BASE_URL}/?route=dashboard`, { route: 'dashboard' });
  await sleep(500);
  await page.eval(`
    console.error('QA-CONSOLE-PROBE');
    console.warn('QA-WARN-PROBE');
    setTimeout(() => { throw new Error('QA-UNCAUGHT-PROBE'); }, 0);
    return true;
  `);
  await sleep(800);
  const seen = page.issues.map((issue) => `${issue.level}:${issue.text}`);
  console.log(JSON.stringify(seen, null, 2));
  const ok =
    seen.some((line) => line.startsWith('error:') && line.includes('QA-CONSOLE-PROBE')) &&
    seen.some((line) => line.startsWith('warning:') && line.includes('QA-WARN-PROBE')) &&
    seen.some((line) => line.includes('QA-UNCAUGHT-PROBE'));
  console.log(ok ? 'COLLECTOR-OK' : 'COLLECTOR-BROKEN');
  if (!ok) process.exitCode = 1;
});
