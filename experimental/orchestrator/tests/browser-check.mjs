import { EventEmitter } from 'node:events';
import { mkdir } from 'node:fs/promises';
import { resolve, join, dirname } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { Orchestrator } from '../lib/engine.mjs';
import { createControlRoom } from '../server.mjs';

if (!process.env.CHRONOS_TEST_DEPS) throw Error('Set CHRONOS_TEST_DEPS');
const { chromium } = await import(pathToFileURL(join(process.env.CHRONOS_TEST_DEPS, 'playwright/index.mjs')).href);
const sourceLink = 'codex://threads/0192f6b8-7b4a-7c50-8c2a-4d3e2f1a9b8c';
class FixtureAdapter extends EventEmitter {
  starts = [];
  async connect() {}
  async close() {}
  async startTask(task) { this.starts.push(task); return { threadId: '0192f6b8-7b4a-7c50-8c2a-4d3e2f1a9b8d', turnId: 'fixture-turn' }; }
  async inspectThread(link) { assert.equal(link, sourceLink); return { title: 'Selected fixture chat', handling: 'fork_on_dispatch' }; }
  async verifyCommand() { return { exitCode: 0, stdout: 'Fixture verifier passed', stderr: '' }; }
  diagnostics() { return { connected: true, activeTurns: 0 }; }
}
const adapter = new FixtureAdapter();
const engine = new Orchestrator({ adapter, prepareWorkspace: async () => ({ cwd: process.cwd(), workspacePath: process.cwd(), kind: 'fixture' }) });
await engine.action({ action: 'add-task', title: 'Accepted research input', instruction: 'Read fixture only.', dependencies: [] });
const source = engine.state.tasks.at(-1); source.state = 'review'; source.summary = 'Accepted external workflow evidence.';
await engine.action({ action: 'accept', taskId: source.id });
const room = await createControlRoom({ engine });
const browser = await chromium.launch({ headless: true, ...(process.env.CHRONOS_BROWSER_CHANNEL ? { channel: process.env.CHRONOS_BROWSER_CHANNEL } : {}) });
const output = resolve(dirname(fileURLToPath(import.meta.url)), '../dist/control-room-browser-check');
await mkdir(output, { recursive: true });
try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('console', (event) => { if (event.type() === 'error' && !event.text().includes('the server responded with a status of 400')) errors.push(event.text()); });
  page.on('dialog', (dialog) => dialog.accept());
  await page.goto(room.url);
  await page.waitForSelector('.workflow-select');
  assert.equal(new URL(page.url()).hash, '');
  await page.screenshot({ path: join(output, 'desktop-template.png'), fullPage: true });
  await page.getByRole('button', { name: 'Connect', exact: true }).click();
  await page.getByLabel('Create from template').selectOption('blank');
  await page.getByRole('button', { name: 'Add stage', exact: true }).click();
  await page.getByLabel('Stage name', { exact: true }).fill('Processing');
  await page.getByLabel('Assignment', { exact: true }).fill('Inspect the accepted evidence and implement the assigned fixture.');
  await page.getByLabel('Workspace access').selectOption('workspace-write');
  await page.getByLabel('Bot slots').fill('2');
  await page.getByLabel('Output routing').selectOption('approval');
  await page.getByLabel('Model', { exact: true }).fill('fixture-model');
  await page.getByLabel('Allow provider web search').check();
  await page.getByLabel('Native check: JSON command arguments').fill('["node","--test"]');
  const processingId = await page.locator('.react-flow__node').first().getAttribute('data-id');
  await page.getByRole('button', { name: 'Add stage', exact: true }).click();
  await page.getByLabel('Stage name', { exact: true }).fill('Review');
  await page.getByLabel('Assignment', { exact: true }).fill('Review the accepted implementation.');
  await page.getByLabel('Output routing').selectOption('approval');
  await page.getByLabel('Add input stage').selectOption(processingId);
  await page.getByRole('button', { name: 'Save', exact: true }).click();
  await page.waitForFunction(() => document.querySelector('.save-state')?.textContent === 'Saved');
  const flow = engine.snapshot().workflows.at(-1);
  assert.equal(flow.nodes[0].kind, 'task'); assert.equal(flow.nodes[0].model, 'fixture-model');
  assert.deepEqual(flow.nodes[0].verificationCommand, ['node', '--test']);
  assert.equal(flow.edges.length, 1);
  await page.getByRole('button', { name: 'Add work item', exact: true }).click();
  await page.locator('#packet-title').fill('Fixture intake');
  await page.locator('#packet-input').fill('Combine accepted evidence into this bounded work item.');
  await page.locator('#packet-link').fill('invalid-link');
  await page.getByRole('button', { name: 'Queue work item', exact: true }).click();
  assert.equal(await page.getByRole('dialog').count(), 1);
  assert.equal(await page.locator('#packet-title').inputValue(), 'Fixture intake');
  await page.locator('#packet-link').fill(sourceLink);
  await page.getByRole('button', { name: 'Check link', exact: true }).click();
  await page.getByText('Thread available: Selected fixture chat').waitFor();
  await page.getByLabel('Accepted research input', { exact: true }).check();
  await page.getByRole('button', { name: 'Queue work item', exact: true }).click();
  await page.waitForSelector('.task-row');
  assert.deepEqual(engine.snapshot().packets[0].sourceTaskIds, [source.id]);
  await page.getByRole('button', { name: 'Permissions', exact: true }).click();
  await page.locator('#write-consent').check();
  await page.getByRole('button', { name: 'Authorize session', exact: true }).click();
  await page.getByRole('button', { name: 'Run', exact: true }).click();
  await page.waitForFunction(() => !!document.querySelector('.task-detail .status-running'));
  assert.equal(adapter.starts.length, 1); assert.equal(adapter.starts[0].policy, 'workspace-write');
  assert.equal(adapter.starts[0].sourceThreadLink, sourceLink); assert.equal(adapter.starts[0].model, 'fixture-model');
  assert.ok(adapter.starts[0].instruction.includes(source.summary));
  adapter.emit('task-event', { taskId: adapter.starts[0].id, kind: 'completed', summary: 'Implemented fixture. Native check follows.', turnId: 'fixture-turn', executionEvidence: { coverage: 'observed_events_only', observedWallMs: 1200, counts: { commandExecution: { started: 1, completed: 1, failed: 0 } }, partial: false } });
  await page.waitForFunction(() => !!document.querySelector('.task-detail .status-review'));
  await page.getByText('Observed execution evidence', { exact: true }).waitFor();
  await page.getByText('1.2 seconds of observed turn wall time.', { exact: false }).waitFor();
  await page.getByRole('button', { name: 'Accept output', exact: true }).click();
  await page.waitForFunction(() => !!document.querySelector('.task-detail .status-accepted'));
  assert.equal(adapter.starts.length, 2);
  adapter.emit('task-event', { taskId: adapter.starts[1].id, kind: 'completed', summary: 'Independent fixture review.', turnId: 'fixture-turn' });
  await page.waitForFunction(() => document.querySelectorAll('.task-row').length === 2);
  await page.locator('.task-row').last().click();
  await page.waitForFunction(() => !!document.querySelector('.task-detail .status-review'));
  await page.getByRole('button', { name: 'Accept output', exact: true }).click();
  await page.waitForFunction(() => !!document.querySelector('.task-detail .status-accepted'));
  await page.getByRole('button', { name: 'Pause', exact: true }).click();
  await page.getByRole('button', { name: 'Workflow', exact: true }).click();
  await page.locator('.stage').first().click();
  await page.getByLabel('Stage name', { exact: true }).fill('Unsaved processing');
  await page.waitForTimeout(2400);
  assert.equal(await page.getByLabel('Stage name', { exact: true }).inputValue(), 'Unsaved processing');
  await page.screenshot({ path: join(output, 'desktop.png'), fullPage: true });
  await page.setViewportSize({ width: 390, height: 844 });
  assert.equal(await page.getByLabel('Stage name', { exact: true }).isVisible(), true);
  await page.screenshot({ path: join(output, 'mobile-inspector.png'), fullPage: true });
  await page.getByRole('button', { name: 'Close stage settings' }).click();
  await page.waitForTimeout(200);
  const mobileStage = await page.locator('.stage').first().boundingBox();
  assert.ok(mobileStage.x >= 0 && mobileStage.x + mobileStage.width <= 390 && mobileStage.y > 250 && mobileStage.y < 750, 'Mobile graph must remain framed, not blank.');
  await page.screenshot({ path: join(output, 'mobile.png'), fullPage: true });
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
  await page.getByRole('button', { name: 'Runtime', exact: true }).click();
  await page.getByText('Control Room memory', { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
  await page.getByRole('button', { name: 'Queues', exact: false }).click();
  await page.getByRole('button', { name: 'Archive Fixture intake' }).click();
  await page.waitForFunction(() => !document.querySelector('.packet-row'));
  await page.reload(); await page.waitForSelector('.workflow-select');
  assert.equal(engine.snapshot().consent.writes, true);
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.getByRole('button', { name: 'Workflow', exact: true }).click();
  await page.getByLabel('Create from template').selectOption('outcome_learning');
  await page.locator('.stage').filter({ hasText: 'Outcome evidence' }).waitFor();
  assert.equal(await page.locator('.stage').count(), 4);
  assert.equal(engine.snapshot().workflows.at(-1).nodes.every((node) => node.policy === 'read-only'), true);
  assert.equal(adapter.starts.length, 2);
  await page.screenshot({ path: join(output, 'outcome-learning.png'), fullPage: true });
  await page.getByLabel('Create from template').selectOption('tool_call_review');
  await page.locator('.stage').filter({ hasText: 'Tool-call evidence' }).waitFor();
  assert.equal(await page.locator('.stage').count(), 4);
  assert.equal(adapter.starts.length, 2);
  const brand = page.locator('.brand img');
  assert.ok(await brand.evaluate((image) => image.complete && image.naturalWidth > 0));
  assert.deepEqual(errors, []);
  await page.getByRole('button', { name: 'Stop Control Room', exact: true }).click();
  await page.getByText('Control Room stopped', { exact: true }).waitFor();
  console.log(JSON.stringify({ result: 'PASS', screenshots: output, fixtureModelTurns: adapter.starts.length, realModelTurns: 0 }));
} catch (error) {
  for (const page of browser.contexts().flatMap((context) => context.pages())) {
    await page.screenshot({ path: join(output, 'failure.png'), fullPage: true }).catch(() => {});
    console.log((await page.locator('body').innerText()).slice(0, 6000));
  }
  throw error;
} finally { await browser.close(); await room.close(); }
