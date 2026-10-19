import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, readFile, readdir, rm, mkdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { stop } from '../launcher.mjs';

const repo = resolve(fileURLToPath(new URL('../../..', import.meta.url)));
const payloadRoot = join(repo, 'plugins/chronos/skills/chronos-control-room/scripts/runtime');
const entrypoint = join(repo, 'plugins/chronos/skills/chronos-control-room/scripts/launch.mjs');

test('committed plugin payload is self-contained, hashed, and free of developer paths', async () => {
  const record = JSON.parse(await readFile(join(payloadRoot, 'payload.json'), 'utf8'));
  const manifest = JSON.parse(await readFile(join(repo, 'plugins/chronos/.codex-plugin/plugin.json'), 'utf8'));
  assert.equal(record.schemaVersion, 1);
  assert.equal(record.pluginVersion, manifest.version);
  assert.ok(record.files.length >= 10);
  for (const file of record.files) {
    assert.match(file.path, /^[A-Za-z0-9._/-]+$/);
    assert.ok(!file.path.includes('node_modules'));
    const bytes = await readFile(join(payloadRoot, file.path));
    assert.equal(bytes.length, file.bytes, file.path);
    assert.equal(createHash('sha256').update(bytes).digest('hex'), file.sha256, file.path);
    assert.doesNotMatch(bytes.toString('utf8'), /[A-Z]:\\Users\\[^'"`\r\n]+|scratch-workspaces/i, file.path);
  }
  const topLevel = await readdir(payloadRoot);
  assert.deepEqual(topLevel.filter((name) => name === 'node_modules' || name === '.git'), []);
});

test('packaged one-prompt entrypoint launches and reuses an isolated paused room', async () => {
  const root = await mkdtemp(join(tmpdir(), 'chronos-packaged-'));
  const workspace = join(root, 'workspace');
  const stateDir = join(root, 'state');
  await mkdir(workspace);
  const args = [entrypoint, '--workspace', workspace, '--state-dir', stateDir, '--codex', process.execPath];
  const result = await new Promise((resolveResult, reject) => {
    const child = spawn(process.execPath, args, { cwd: repo, windowsHide: true });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.once('error', reject);
    child.once('close', (code) => {
      if (code !== 0) return reject(new Error(`entrypoint_failed:${stderr || stdout}`));
      try { resolveResult(JSON.parse(stdout.trim().split(/\r?\n/).at(-1))); } catch { reject(new Error(`entrypoint_invalid_output:${stdout}`)); }
    });
  });
  try {
    assert.equal(result.ok, true);
    assert.equal(result.mode, 'paused');
    assert.equal(result.activeCount, 0);
    const reused = await import('../launcher.mjs').then(({ launch }) => launch({ workspace, stateDir, codex: process.execPath }));
    assert.equal(reused.status, 'reused');
  } finally {
    await stop({ workspace, stateDir, codex: process.execPath });
    await rm(root, { recursive: true, force: true });
  }
});
