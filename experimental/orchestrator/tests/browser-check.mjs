import { EventEmitter } from 'node:events';
import { mkdir } from 'node:fs/promises';
import { resolve, join, dirname } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { Orchestrator } from '../lib/engine.mjs';
import { createControlRoom } from '../server.mjs';

if (!process.env.CHRONOS_TEST_DEPS) throw new Error('Set CHRONOS_TEST_DEPS to a local Playwright node_modules directory.');
const { chromium } = await import(pathToFileURL(join(process.env.CHRONOS_TEST_DEPS, 'playwright/index.mjs')).href);
class FixtureAdapter extends EventEmitter {
  async connect() {}
  diagnostics() { return { effectivePolicy: this.effectivePolicy || null }; }
  async close() { this.effectivePolicy = null; }
  async interruptTask() { if (this.task) setImmediate(() => this.emit('task-event', { taskId: this.task.id, kind: 'interrupted', turnId: 'fixture-turn' })); }
  async startTask(task) { this.task = task; this.effectivePolicy = { model: 'fixture-model', sandbox: 'readOnly', approvalPolicy: 'never' }; return { threadId: 'fixture-thread', turnId: 'fixture-turn' }; }
}
const adapter = new FixtureAdapter(), engine = new Orchestrator({ adapter });
const room = await createControlRoom({ engine });
const browser = await chromium.launch({ headless: true, ...(process.env.CHRONOS_BROWSER_CHANNEL ? { channel: process.env.CHRONOS_BROWSER_CHANNEL } : {}) });
const output = resolve(dirname(fileURLToPath(import.meta.url)), '../dist/control-room-browser-check'); await mkdir(output, { recursive: true });
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  const errors = []; page.on('pageerror', (error) => errors.push(error.message));
  await page.goto(room.url); await page.waitForSelector('#runtime');
  assert.equal(await page.locator('#mode').isDisabled(), true);
  await page.getByRole('button', { name: 'Add task', exact: true }).click();
  await page.locator('#title').fill('Review dependency boundaries and acceptance controls for the long-form operational release workflow');
  await page.locator('#instruction').fill('Inspect the queue and identify missing acceptance gates. Report findings only; do not modify files. '.repeat(12));
  await page.getByRole('button', { name: 'Add to queue' }).click();
  await page.reload();
  await page.waitForSelector('#runtime');
  assert.equal(await page.locator('.task-item').count(), 1);
  await page.locator('.task-item').first().click();
  await page.getByRole('button', { name: 'Connect', exact: true }).click();
  await page.waitForFunction(() => document.querySelector('#connection').textContent === 'Connected');
  await page.locator('#mode').click(); await page.locator('#consent-check').check();
  await page.getByRole('button', { name: 'Authorize', exact: true }).click();
  await page.waitForFunction(() => document.querySelector('#detail-state').textContent === 'running');
  adapter.emit('task-event', { taskId: adapter.task.id, kind: 'completed', turnId: 'fixture-turn', summary: 'Fixture result: dependent tasks wait for explicit human acceptance.' });
  await page.waitForFunction(() => document.querySelector('#detail-state').textContent === 'review');
  assert.match(await page.locator('#detail-summary').textContent(), /human acceptance/);
  assert.match(await page.locator('#runtime-policy').textContent(), /fixture-model.*readOnly.*never/);
  await page.screenshot({ path: join(output, 'desktop.png'), fullPage: true });
  await page.getByRole('button', { name: 'Accept result' }).click();
  await page.waitForFunction(() => document.querySelector('#detail-state').textContent === 'accepted');
  await page.getByRole('button', { name: 'New task' }).click();
  await page.locator('#title').fill('Cancel recovery fixture');
  await page.locator('#instruction').fill('Verify cancellation is explicit.');
  await page.getByRole('button', { name: 'Add to queue' }).click();
  await page.locator('.task-item').last().click();
  await page.waitForFunction(() => document.querySelector('#detail-title').textContent === 'Cancel recovery fixture');
  page.once('dialog', dialog => dialog.accept());
  await page.getByRole('button', { name: 'Cancel task' }).click();
  await page.waitForFunction(() => document.querySelector('#detail-state').textContent === 'cancelled');
  page.once('dialog', dialog => dialog.accept());
  await page.getByRole('button', { name: 'Remove' }).click();
  await page.waitForFunction(() => document.querySelectorAll('.task-item').length === 1);
  await page.getByRole('button', { name: 'New task' }).click();
  await page.locator('#title').fill('Stopped worker recovery fixture');
  await page.locator('#instruction').fill('Wait for the explicit recovery check.');
  await page.getByRole('button', { name: 'Add to queue' }).click();
  await page.locator('.task-item').last().click();
  await page.waitForFunction(() => document.querySelector('#detail-state').textContent === 'running');
  adapter.emit('error', new Error('fixture_runtime_lost'));
  await page.waitForFunction(() => document.querySelector('#detail-state').textContent === 'blocked');
  page.once('dialog', dialog => { assert.match(dialog.message(), /previous worker has stopped/); dialog.accept(); });
  await page.getByRole('button', { name: 'Cancel task' }).click();
  await page.waitForFunction(() => document.querySelector('#detail-state').textContent === 'cancelled');
  page.once('dialog', dialog => dialog.accept());
  await page.getByRole('button', { name: 'Remove', exact: true }).click();
  await page.waitForFunction(() => document.querySelectorAll('.task-item').length === 1);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({ path: join(output, 'mobile.png'), fullPage: true });
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
  assert.equal(overflow, false); assert.deepEqual(errors, []);
  assert.equal(engine.snapshot().tasks[0].state, 'accepted');
  page.once('dialog', dialog => dialog.accept());
  await page.getByRole('button', { name: 'Shut down', exact: true }).click();
  await page.waitForFunction(() => document.querySelector('#connection').textContent === 'Stopped');
  await page.waitForTimeout(2200);
  assert.deepEqual(errors, []);
  console.log(JSON.stringify({ result: 'PASS', browser: 'Chromium', desktop: '1440x1000', mobile: '390x844', overflow: false, modelTurns: 0, protocol: 'simulated_fixture', screenshots: output }));
} finally { await browser.close(); await room.close(); }
