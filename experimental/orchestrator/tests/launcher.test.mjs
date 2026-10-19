import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, symlink, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { launch, status, stop, verifyPayload, runLauncherCli } from '../launcher.mjs';
import { discoverCodex, defaultStateDir } from '../lib/runtime-discovery.mjs';

test('discovery returns absolute runtime paths and never treats missing bare PATH as Codex', async () => {
  assert.equal(await discoverCodex({ explicit: process.execPath }), await import('node:fs/promises').then((fs) => fs.realpath(process.execPath)));
  await assert.rejects(discoverCodex({ explicit: 'codex' }), /codex_path_must_be_absolute/);
  await assert.rejects(discoverCodex({ env: { PATH: '' } }), /control_room_codex_runtime_missing/);
  assert.notEqual(defaultStateDir(resolve('one')), defaultStateDir(resolve('two')));
  assert.notEqual(defaultStateDir(resolve('one'), { codexHome: '/profile-one' }), defaultStateDir(resolve('one'), { codexHome: '/profile-two' }));
});

test('one-prompt launcher starts, authenticates, reuses and stops one real local UI without model calls', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'chronos-launch-'));
  const workspace = join(directory, 'workspace'), stateDir = join(directory, 'state'); await mkdir(workspace);
  const options = { workspace, stateDir, codex: process.execPath, template: 'research', learningModules: ['outcome_learning'] };
  try {
    const started = await launch(options);
    assert.equal(started.status, 'started'); assert.equal(started.mode, 'paused'); assert.equal(started.activeCount, 0);
    const again = await launch(options); assert.equal(again.status, 'reused'); assert.equal(again.pid, started.pid);
    const running = await status(options); assert.equal(running.pid, started.pid);
    const token = new URLSearchParams(new URL(running.url).hash.slice(1)).get('token');
    const state = await fetch(running.origin + '/api/state', { headers: { 'x-chronos-token': token } }).then((response) => response.json());
    assert.equal(state.connected, false); assert.equal(state.consent.execution, false); assert.equal(state.consent.writes, false);
    assert.deepEqual(state.workflows.map((workflow) => workflow.name), ['Research desk', 'Outcome learning (opt-in)']);
    assert.equal((await fetch(running.origin + '/app.js')).status, 200);
    assert.equal((await fetch(running.origin + '/assets/chronos-mark.png')).status, 200);
    assert.equal((await stop(options)).status, 'stopped');
    assert.equal((await status(options)).status, 'stopped');
    assert.ok((await readFile(join(stateDir, 'queue.json'), 'utf8')).includes('Research desk'));
  } finally { await stop(options).catch(() => {}); }
});

test('state symlinks are rejected before queue state is created', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'chronos-launch-link-'));
  const target = join(directory, 'target'), link = join(directory, 'link'); await mkdir(target);
  await symlink(target, link, process.platform === 'win32' ? 'junction' : 'dir');
  await assert.rejects(launch({ workspace: directory, stateDir: join(link, 'state'), codex: process.execPath }), /control_room_state_link_rejected/);
});

test('repeated owned shutdown tolerates receipt removal without treating absence as corrupt JSON', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'chronos-stop-race-'));
  const workspace = join(directory, 'workspace'), stateDir = join(directory, 'state');
  await mkdir(workspace);
  const options = { workspace, stateDir, codex: process.execPath };
  try {
    for (let attempt = 0; attempt < 12; attempt++) {
      assert.equal((await launch(options)).mode, 'paused');
      assert.equal((await stop(options)).status, 'stopped');
      assert.equal((await status(options)).status, 'stopped');
    }
    await writeFile(join(stateDir, 'session.json'), '{');
    try { await assert.rejects(status(options), /control_room_state_json_invalid/); }
    finally { await rm(join(stateDir, 'session.json'), { force: true }); }
  } finally {
    await stop(options).catch(() => {});
    await rm(directory, { recursive: true, force: true });
  }
});

test('startup reports a bounded native prerequisite code without leaking stderr', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'chronos-start-failure-'));
  const runtimeRoot = join(directory, 'runtime'); await mkdir(runtimeRoot);
  await writeFile(join(runtimeRoot, 'server.mjs'), "console.error('codex_login_required'); process.exitCode = 1;\n");
  await assert.rejects(launch({ workspace: directory, stateDir: join(directory, 'state'), runtimeRoot, codex: process.execPath }), /codex_login_required/);
  await writeFile(join(runtimeRoot, 'server.mjs'), "console.error('private arbitrary detail'); process.exitCode = 1;\n");
  await assert.rejects(launch({ workspace: directory, stateDir: join(directory, 'state'), runtimeRoot, codex: process.execPath }), /control_room_start_failed/);
});

test('packaged payload verification rejects corruption and CLI rejects unknown options', async () => {
  const root = await mkdtemp(join(tmpdir(), 'chronos-payload-'));
  const paths = ['server.mjs', 'launcher.mjs', 'public/app.js', 'public/app.css', 'lib/engine.mjs', 'lib/one.mjs', 'lib/two.mjs', 'lib/three.mjs', 'lib/four.mjs', 'lib/five.mjs'];
  const files = [];
  for (const path of paths) {
    await mkdir(join(root, path, '..'), { recursive: true });
    const bytes = Buffer.from('fixture\n'); await writeFile(join(root, path), bytes);
    files.push({ path, bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') });
  }
  await writeFile(join(root, 'payload.json'), JSON.stringify({ schemaVersion: 1, files }));
  assert.ok(await verifyPayload(root, { required: true }));
  await writeFile(join(root, 'public/app.js'), 'corrupt\n');
  await assert.rejects(verifyPayload(root, { required: true }), /control_room_payload_file_invalid|control_room_payload_hash_mismatch/);
  await assert.rejects(runLauncherCli(['--unknown']), /control_room_arguments_invalid/);
});
