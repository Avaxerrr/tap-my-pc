// Install: npm install --prefix artifacts/browser-qa --no-save --package-lock=false playwright@1.65.1
// Run against TapMyPC.Simulator only: node tools/browser-smoke.cjs <pairing-code>
const { chromium } = require('../artifacts/browser-qa/node_modules/playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.TAPMYPC_CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    headless: true, args: ['--disable-gpu', '--no-first-run']
  });
  try {
    const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, ignoreHTTPSErrors: true });
    const page = await context.newPage();
    const errors = []; page.on('pageerror', error => errors.push(error.message));
    const output = path.resolve('artifacts/screenshots'); fs.mkdirSync(output, { recursive: true });
    await page.goto('https://127.0.0.1:45832');
    await page.screenshot({ path: path.join(output, 'phone-pairing.png'), fullPage: true });
    await page.locator('#pair-code').fill(process.argv[2]);
    await page.locator('#pair-form button').click();
    await page.locator('#connection.online').waitFor();
    await page.locator('#volume').fill('57');
    await page.locator('#volume').dispatchEvent('change');
    await page.waitForFunction(() => document.getElementById('volume-value').textContent === '57%' && !document.getElementById('mute').disabled);
    await page.locator('#mute').click();
    await page.route('**/api/v1/audio/mute', async route => {
      await new Promise(resolve => setTimeout(resolve, 800));
      await route.continue();
    });
    // Toggle again under simulated network latency to verify immediate feedback instead of silent waiting.
    await page.waitForFunction(() => document.getElementById('mute').textContent === 'Unmute' && !document.getElementById('mute').disabled);
    await page.locator('#mute').click();
    await page.locator('#action-toast[data-phase=running]').waitFor();
    assert.equal(await page.locator('#mute').isDisabled(), true);
    assert.equal(await page.locator('#remote').getAttribute('aria-busy'), 'true');
    await page.screenshot({ path: path.join(output, 'phone-action-pending.png'), fullPage: true });
    await page.waitForFunction(() => document.getElementById('mute').textContent === 'Mute' && !document.getElementById('mute').disabled);
    await page.unroute('**/api/v1/audio/mute');
    await page.route('**/api/v1/media', route => route.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify({ error: 'Simulated media failure' }) }));
    await page.locator('[data-media=Next]').click();
    await page.locator('#action-toast[data-phase=error]').waitFor();
    assert.match(await page.locator('#action-message').textContent(), /Simulated media failure/);
    await page.unroute('**/api/v1/media');
    await page.locator('#timer-form button').click();
    await page.locator('#confirm-dialog [value=confirm]').click();
    await page.locator('#pending:not([hidden])').waitFor();
    assert.match(await page.locator('#pending-label').textContent(), /Hibernate in/);
    assert.equal(await page.locator('#live-action').isVisible(), true);
    await page.screenshot({ path: path.join(output, 'phone-remote.png'), fullPage: true });
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, 'Mobile page overflows horizontally');
    await page.locator('#cancel-timer').click();
    await page.waitForFunction(() => document.getElementById('pending').hidden);
    assert.equal(await page.locator('#live-action').isVisible(), false);
    await page.locator('[data-power=Shutdown]').click();
    await page.locator('#confirm-dialog [value=cancel]').click();
    assert.equal(await page.locator('#pending').isVisible(), false);
    await page.reload(); await page.locator('#connection.online').waitFor();
    assert.equal(await page.locator('#pairing').isVisible(), false, 'Pairing did not survive reload');
    await page.evaluate(() => {
      localStorage.setItem('pcRemoteToken', localStorage.getItem('tapMyPcToken'));
      localStorage.removeItem('tapMyPcToken');
    });
    await page.reload(); await page.locator('#connection.online').waitFor();
    assert.equal(await page.evaluate(() => !!localStorage.getItem('tapMyPcToken') && localStorage.getItem('pcRemoteToken') === null), true, 'Legacy browser credential did not migrate');
    assert.match(await page.title(), /TapMyPC/);
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.screenshot({ path: path.join(output, 'web-desktop.png'), fullPage: true });
    assert.deepEqual(errors, []);
    console.log('Browser smoke passed: pairing, volume, mute, pending/success/error feedback, disabled controls during latency, timer/countdown, cancellation, confirmation dismissal, reload, responsive layout; no script errors.');
    console.log('Screenshots: ' + output);
    await context.close();
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
