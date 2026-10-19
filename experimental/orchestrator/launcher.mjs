import { mkdir, open, readFile, lstat, realpath, unlink } from 'node:fs/promises';
import { dirname, join, parse, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';
import { randomUUID, createHash } from 'node:crypto';
import { discoverCodex, defaultStateDir, pathIdentity } from './lib/runtime-discovery.mjs';

const runtimeRoot = dirname(fileURLToPath(import.meta.url));
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
const fail = (code) => { throw new Error(code); };
async function noLinks(path) {
  let current = resolve(path);
  while (current !== parse(current).root) {
    const item = await lstat(current).catch((error) => error.code === 'ENOENT' ? null : Promise.reject(error));
    if (item?.isSymbolicLink()) fail('control_room_state_link_rejected');
    current = dirname(current);
  }
}
async function readJson(path, maximum = 16384) {
  await noLinks(path);
  const item = await lstat(path).catch((error) => error.code === 'ENOENT' ? null : Promise.reject(error));
  if (!item) return null;
  if (!item.isFile() || item.nlink !== 1 || item.size > maximum) fail('control_room_state_file_invalid');
  try { return JSON.parse(await readFile(path, 'utf8')); } catch { fail('control_room_state_json_invalid'); }
}
function alive(pid) {
  if (!Number.isInteger(pid) || pid < 1) fail('control_room_owner_invalid');
  try { process.kill(pid, 0); return true; } catch (error) { if (error.code === 'ESRCH') return false; fail('control_room_owner_uncertain'); }
}
export async function verifyPayload(root = runtimeRoot, { required = false } = {}) {
  const manifest = await readJson(join(root, 'payload.json'), 65536);
  if (!manifest) { if (required) fail('control_room_payload_missing'); return null; }
  if (manifest.schemaVersion !== 1 || !Array.isArray(manifest.files) || manifest.files.length < 10 || manifest.files.length > 256) fail('control_room_payload_invalid');
  const seen = new Set();
  for (const file of manifest.files) {
    if (typeof file.path !== 'string' || !/^[a-zA-Z0-9_./-]+$/.test(file.path) || file.path.split('/').some((part) => !part || part === '.' || part === '..') || file.path.startsWith('/') || !/^[a-f0-9]{64}$/.test(file.sha256) || seen.has(file.path)) fail('control_room_payload_invalid');
    seen.add(file.path);
    const path = join(root, file.path); await noLinks(path);
    const item = await lstat(path).catch(() => null);
    if (!item?.isFile() || item.nlink !== 1 || item.size !== file.bytes || item.size > 8 * 1048576) fail('control_room_payload_file_invalid');
    if (createHash('sha256').update(await readFile(path)).digest('hex') !== file.sha256) fail('control_room_payload_hash_mismatch');
  }
  for (const path of ['server.mjs', 'launcher.mjs', 'public/app.js', 'public/app.css', 'lib/engine.mjs']) if (!seen.has(path)) fail('control_room_payload_incomplete');
  return manifest;
}

async function resolveOptions(options) {
  if (Number(process.versions.node.split('.')[0]) < 22) fail('control_room_node_22_required');
  if (!options.workspace) fail('workspace_required');
  const workspace = await realpath(resolve(options.workspace)).catch(() => fail('workspace_directory_required'));
  if (!(await lstat(workspace)).isDirectory()) fail('workspace_directory_required');
  return { ...options, workspace, stateDir: resolve(options.stateDir || defaultStateDir(workspace)) };
}
async function acquireLaunchLock(directory) {
  const lock = join(directory, '.launch.lock'), gate = join(directory, '.launch.recovery');
  let gateHandle;
  try { gateHandle = await open(gate, 'wx', 0o600); } catch (error) { if (error.code === 'EEXIST') fail('control_room_launch_in_progress'); throw error; }
  try {
    let handle;
    try { handle = await open(lock, 'wx', 0o600); }
    catch (error) {
      if (error.code !== 'EEXIST') throw error;
      const old = await readJson(lock);
      if (!old || alive(old.pid)) fail('control_room_launch_in_progress');
      await unlink(lock); handle = await open(lock, 'wx', 0o600);
    }
    await handle.writeFile(JSON.stringify({ pid: process.pid, startedAt: new Date().toISOString() }));
    return async () => { await handle.close(); await unlink(lock).catch(() => {}); };
  } finally { await gateHandle.close(); await unlink(gate).catch(() => {}); }
}
function validateSession(data, options) {
  if (!data || data.schemaVersion !== 1 || data.protocol !== 'chronos-control-room' || typeof data.workspace !== 'string' || pathIdentity(data.workspace) !== pathIdentity(options.workspace) || pathIdentity(data.queueFile || '') !== pathIdentity(join(options.stateDir, 'queue.json')) || !/^[a-f0-9-]{36}$/.test(data.instanceId)) fail('control_room_session_invalid');
  const origin = new URL(data.origin), url = new URL(data.url);
  if (origin.protocol !== 'http:' || origin.hostname !== '127.0.0.1' || !origin.port || origin.pathname !== '/' || origin.username || origin.password || origin.search || origin.hash || url.origin !== origin.origin || url.pathname !== '/' || url.search) fail('control_room_session_invalid');
  const token = new URLSearchParams(url.hash.slice(1)).get('token');
  if (!/^[a-f0-9]{64}$/.test(token)) fail('control_room_session_invalid');
  return { ...data, token };
}
async function request(session, action) {
  const response = await fetch(session.origin + (action ? '/api/actions' : '/api/state'), { method: action ? 'POST' : 'GET', signal: AbortSignal.timeout(1500), headers: { 'x-chronos-token': session.token, ...(action ? { Origin: session.origin, 'Content-Type': 'application/json' } : {}) }, ...(action ? { body: JSON.stringify(action) } : {}) });
  if (!response.ok) fail('control_room_session_rejected');
  return response.json();
}
async function inspect(options) {
  const data = await readJson(join(options.stateDir, 'session.json'));
  if (!data) return null;
  const session = validateSession(data, options);
  if (!alive(session.pid)) return null;
  let state;
  try { state = await request(session); } catch { fail('control_room_existing_process_unreachable'); }
  if (state.runtime?.instanceId !== session.instanceId) fail('control_room_session_identity_mismatch');
  return { session, state };
}
const receipt = (found, status) => ({ ok: true, status, url: found.session.url, origin: found.session.origin, pid: found.session.pid, workspace: found.session.workspace, mode: found.state.mode, activeCount: found.state.activeCount });
async function startupFailure(directory) {
  const path = join(directory, 'launcher.stderr.log');
  const item = await lstat(path).catch(() => null);
  if (!item?.isFile() || item.isSymbolicLink() || item.nlink !== 1 || item.size > 16384) return 'control_room_start_failed';
  const code = (await readFile(path, 'utf8')).trim().split(/\r?\n/).at(-1) || '';
  return /^(?:codex|control_room|workspace|state|supervision|setup)_[a-z0-9_]{1,80}$/.test(code) ? code : 'control_room_start_failed';
}

export async function launch(options = {}) {
  const payload = await verifyPayload(options.runtimeRoot || runtimeRoot, { required: options.requirePayload === true });
  const packageId = payload ? createHash('sha256').update(JSON.stringify(payload)).digest('hex') : null;
  const settings = await resolveOptions(options);
  await noLinks(settings.stateDir); await mkdir(settings.stateDir, { recursive: true, mode: 0o700 }); await noLinks(settings.stateDir);
  const reuse = (found) => { if (packageId && found.session.packageId !== packageId) fail('control_room_running_version_differs'); return receipt(found, 'reused'); };
  let found = await inspect(settings); if (found) return reuse(found);
  const unlock = await acquireLaunchLock(settings.stateDir);
  try {
    found = await inspect(settings); if (found) return reuse(found);
    const codex = await discoverCodex({ explicit: settings.codex });
    const instanceId = randomUUID(), root = options.runtimeRoot || runtimeRoot;
    const args = [join(root, 'server.mjs'), '--codex', codex, '--cwd', settings.workspace, '--state', join(settings.stateDir, 'queue.json'), '--ready-file', join(settings.stateDir, 'session.json'), '--instance-id', instanceId, '--recover-stale-lock'];
    if (settings.template) args.push('--template', settings.template);
    if (settings.learningModules?.length) args.push('--learning-modules', settings.learningModules.join(','));
    if (settings.maxConcurrency != null) args.push('--max-concurrency', String(settings.maxConcurrency));
    if (settings.connect) args.push('--connect');
    if (settings.gitExecutable) args.push('--git', settings.gitExecutable);
    if (packageId) args.push('--package-id', packageId);
    const handles = [];
    let child;
    try {
      for (const name of ['launcher.stdout.log', 'launcher.stderr.log']) {
        const path = join(settings.stateDir, name); await noLinks(path);
        const item = await lstat(path).catch((error) => error.code === 'ENOENT' ? null : Promise.reject(error));
        if (item && (!item.isFile() || item.nlink !== 1)) fail('control_room_log_invalid');
        handles.push(await open(path, 'w', 0o600));
      }
      child = spawn(process.execPath, args, { cwd: root, detached: true, windowsHide: true, stdio: ['ignore', handles[0].fd, handles[1].fd] });
      let spawnError; child.on('error', (error) => { spawnError = error; }); child.unref();
      const deadline = Date.now() + 15000;
      while (Date.now() < deadline) {
        if (spawnError || child.exitCode != null || child.signalCode != null) fail(await startupFailure(settings.stateDir));
        const data = await readJson(join(settings.stateDir, 'session.json'));
        if (data?.instanceId === instanceId) {
          found = await inspect(settings); if (found) return receipt(found, 'started');
        }
        await sleep(150);
      }
      fail('control_room_ready_timeout');
    } catch (error) { if (child?.pid && child.exitCode == null) child.kill(); throw error; }
    finally { for (const handle of handles) await handle.close(); }
  } finally { await unlock(); }
}
export async function status(options = {}) {
  const settings = await resolveOptions(options); const found = await inspect(settings);
  return found ? receipt(found, 'running') : { ok: true, status: 'stopped', workspace: settings.workspace };
}
export async function stop(options = {}) {
  const settings = await resolveOptions(options); const found = await inspect(settings);
  if (!found) return { ok: true, status: 'stopped', workspace: settings.workspace };
  if (found.state.activeCount > 0 && options.confirmStopActive !== true) fail('control_room_active_stop_confirmation_required');
  await request(found.session, { action: 'shutdown' });
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    if (!await readJson(join(settings.stateDir, 'session.json'))) return { ok: true, status: 'stopped', workspace: settings.workspace };
    await sleep(100);
  }
  fail('control_room_stop_unverified');
}
export async function runLauncherCli(argv = process.argv.slice(2), defaults = {}) {
  const options = { ...defaults, action: 'launch' };
  const values = { '--workspace': 'workspace', '--codex': 'codex', '--git': 'gitExecutable', '--state-dir': 'stateDir', '--template': 'template', '--learning-modules': 'learningModules', '--max-concurrency': 'maxConcurrency', '--action': 'action' };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--connect') options.connect = true;
    else if (argv[i] === '--confirm-stop-active') options.confirmStopActive = true;
    else if (values[argv[i]] && argv[i + 1] && !argv[i + 1].startsWith('--')) options[values[argv[i]]] = argv[++i];
    else fail('control_room_arguments_invalid');
  }
  if (typeof options.learningModules === 'string') options.learningModules = options.learningModules.split(',').filter(Boolean);
  if (options.maxConcurrency != null) options.maxConcurrency = Number(options.maxConcurrency);
  if (!['launch', 'status', 'stop'].includes(options.action)) fail('control_room_action_invalid');
  const result = await ({ launch, status, stop }[options.action])(options); console.log(JSON.stringify(result)); return result;
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) runLauncherCli().catch((error) => { console.error(JSON.stringify({ ok: false, error: /^[a-z0-9_]+$/.test(error.message) ? error.message : 'control_room_launch_failed' })); process.exitCode = 1; });
