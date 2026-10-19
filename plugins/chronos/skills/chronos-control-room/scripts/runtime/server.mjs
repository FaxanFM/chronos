import http from 'node:http';
import { randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { readFile, stat, lstat, writeFile, rename, unlink } from 'node:fs/promises';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { CodexAdapter } from './lib/codex-adapter.mjs';
import { Orchestrator } from './lib/engine.mjs';
import { WorkspaceManager } from './lib/workspaces.mjs';
import { RuntimeHealth } from './lib/runtime-health.mjs';
import { readSetupPlan } from './lib/setup-plan.mjs';

const root = dirname(fileURLToPath(import.meta.url));
const files = new Map([
  ['/', [join(root, 'public/index.html'), 'text/html; charset=utf-8']],
  ['/app.js', [join(root, 'public/app.js'), 'text/javascript; charset=utf-8']],
  ['/app.css', [join(root, 'public/app.css'), 'text/css; charset=utf-8']],
  ['/styles.css', [join(root, 'public/styles.css'), 'text/css; charset=utf-8']],
  ['/assets/chronos-mark.png', [join(root, 'public/chronos-mark.png'), 'image/png']]
]);
const safeCode = (error) => /^[a-z][a-z0-9_]{1,95}$/.test(error?.message || '') ? error.message : 'operation_failed';

export async function createControlRoom({ engine, token = randomBytes(32).toString('hex'), port = 0, runtimeHealth, workspaceInfo, instanceId = randomUUID(), packageId = null } = {}) {
  if (!engine || !/^[a-f0-9]{64}$/.test(token)) throw new Error('control_room_parameters_invalid');
  let origin;
  let cookieName;
  let closing;
  const session = randomBytes(32).toString('hex');
  const health = runtimeHealth || new RuntimeHealth({ adapter: engine.adapter, engine });
  engine.dispatchLimit = (configured) => {
    const evidence = health.snapshot();
    if (!evidence || !Number.isFinite(evidence.host?.freeMemoryBytes)) return Math.min(configured, 1);
    if (evidence.host.freeMemoryBytes < 256 * 1048576) return 0;
    return Math.min(configured, evidence.recommendedConcurrency || 1);
  };
  const snapshot = async () => {
    const state = engine.snapshot();
    return { ...state, runtime: { ...state.runtime, instanceId, packageId }, heartbeat: await health.sample(), workspace: workspaceInfo || { sourceRoot: engine.adapter?.cwd || null, base: 'committed_HEAD', uncommittedChangesCopied: false } };
  };
  const matchesSecret = (value, expected) => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value) && timingSafeEqual(Buffer.from(value), Buffer.from(expected));
  const respond = (res, code, data) => { res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' }); res.end(JSON.stringify(data)); };
  const server = http.createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('Content-Security-Policy', "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'");
    try {
      if (req.headers.host !== new URL(origin).host) return respond(res, 403, { error: 'host_not_allowed' });
      if (req.headers.origin && req.headers.origin !== origin) return respond(res, 403, { error: 'origin_not_allowed' });
      const path = new URL(req.url, origin).pathname;
      if (path.startsWith('/api/')) {
        const received = req.headers['x-chronos-token'];
        const cookies = (req.headers.cookie || '').split(';').map((value) => value.trim().split('='));
        const cookie = cookies.find(([name]) => name === cookieName)?.[1];
        const launchAuthorized = matchesSecret(received, token);
        if (!launchAuthorized && !matchesSecret(cookie, session)) return respond(res, 401, { error: 'open_the_private_launch_link' });
        if (launchAuthorized) res.setHeader('Set-Cookie', cookieName + '=' + session + '; HttpOnly; SameSite=Strict; Path=/api/');
        if (path === '/api/state' && req.method === 'GET') return respond(res, 200, await snapshot());
        if (path !== '/api/actions' || req.method !== 'POST') return respond(res, 404, { error: 'route_not_found' });
        if (req.headers.origin !== origin) return respond(res, 403, { error: 'origin_required' });
        if (req.headers['content-type']?.split(';')[0] !== 'application/json') return respond(res, 415, { error: 'json_required' });
        const chunks = []; let size = 0;
        for await (const chunk of req) {
          size += chunk.length;
          if (size > 2097152) { respond(res, 413, { error: 'request_too_large' }); req.resume(); return; }
          chunks.push(chunk);
        }
        let input;
        try { input = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { return respond(res, 400, { error: 'json_invalid' }); }
        if (input?.action === 'shutdown') {
          respond(res, 200, { stopped: true });
          setImmediate(() => close().catch(() => {}));
          return;
        }
        if (input?.action === 'inspect-thread') return respond(res, 200, await engine.adapter.inspectThread(input.sourceThreadLink));
        await engine.action(input);
        return respond(res, 200, await snapshot());
      }
      if (req.method !== 'GET' || !files.has(path)) return respond(res, 404, { error: 'route_not_found' });
      const [file, contentType] = files.get(path);
      const bytes = await readFile(file);
      res.writeHead(200, { 'Content-Type': contentType }); res.end(bytes);
    } catch (error) { if (!res.headersSent) respond(res, 400, { error: safeCode(error) }); else res.end(); }
  });
  server.requestTimeout = 15000; server.headersTimeout = 10000;
  await new Promise((accept, reject) => { server.once('error', reject); server.listen(port, '127.0.0.1', accept); });
  origin = 'http://127.0.0.1:' + server.address().port;
  cookieName = 'chronos_session_' + server.address().port;
  const timer = setInterval(() => { health.sample().catch(() => {}); engine.tick().catch(() => {}); }, 15000); timer.unref();
  const close = () => {
    if (!closing) closing = (async () => {
      clearInterval(timer);
      try { await engine.close(); }
      finally { server.closeAllConnections(); await new Promise((done) => server.close(done)); }
    })();
    return closing;
  };
  return { origin, url: origin + '/#token=' + token, token, server,
    close
  };
}

export async function startLocalControlRoom({ codexPath, cwd, codexHome, statePath, port = 0, recoverStaleLock = false, instanceId = randomUUID(), packageId = null, template = 'software_factory', learningModules = [], maxConcurrency = 1, connect = false, gitExecutable = 'git', setupPlan, setupPlanHash } = {}) {
  cwd = resolve(cwd || process.cwd());
  if (!(await stat(cwd)).isDirectory()) throw new Error('workspace_directory_required');
  if (!Number.isInteger(port) || port < 0 || port > 65535) throw new Error('port_invalid');
  if (!['blank', 'software_factory', 'research', 'engineering', 'marketing', 'outcome_learning', 'tool_call_review'].includes(template) || !Array.isArray(learningModules) || learningModules.some((id) => !['outcome_learning', 'tool_call_review'].includes(id))) throw new Error('setup_template_invalid');
  const setup = setupPlan ? await readSetupPlan(resolve(setupPlan), { workspace: cwd, expectedHash: setupPlanHash }) : null;
  const adapter = new CodexAdapter({ codexPath, cwd, codexHome });
  statePath = resolve(statePath || join(root, '.local', 'queue.json'));
  const existing = await stat(statePath).catch((error) => error.code === 'ENOENT' ? null : Promise.reject(error));
  const workspaces = new WorkspaceManager({ sourceRoot: cwd, storageRoot: join(dirname(statePath), 'workspaces'), gitExecutable });
  const prepareWorkspace = async (input) => {
    const prepared = await workspaces.prepare(input);
    if (prepared.workspacePath) await adapter.allowWorkspace(prepared.workspacePath);
    return prepared;
  };
  const engine = await new Orchestrator({ adapter, statePath, prepareWorkspace, verifier: adapter, recoverStaleLock }).initialize();
  try {
    if (!existing) {
      if (template !== 'software_factory') {
        await engine.action({ action: 'apply-template', templateId: template });
        await engine.action({ action: 'delete-workflow', workflowId: 'software_factory-default' });
      }
      for (const templateId of [...new Set(learningModules)]) if (templateId !== template) await engine.action({ action: 'apply-template', templateId });
      await engine.action({ action: 'configure', maxConcurrency });
    }
    if (setup) await engine.action({ action: 'apply-setup-plan', plan: setup.plan });
    if (connect) await engine.action({ action: 'connect' });
    const room = await createControlRoom({ engine, port, instanceId, packageId });
    return { ...room, engine, adapter, statePath, instanceId, cwd };
  } catch (error) { await engine.close(); throw error; }
}

async function main() {
  const options = new Map();
  for (let i = 2; i < process.argv.length; i += 2) {
    if (['--recover-stale-lock', '--connect'].includes(process.argv[i])) { options.set(process.argv[i], true); i -= 1; continue; }
    if (!['--codex', '--git', '--cwd', '--state', '--port', '--codex-home', '--ready-file', '--instance-id', '--package-id', '--template', '--learning-modules', '--max-concurrency', '--setup-plan', '--setup-plan-sha256'].includes(process.argv[i]) || !process.argv[i + 1]) throw new Error('control_room_arguments_invalid');
    options.set(process.argv[i], process.argv[i + 1]);
  }
  const cwd = resolve(options.get('--cwd') || process.cwd());
  const port = options.has('--port') ? Number(options.get('--port')) : 0;
  const statePath = resolve(options.get('--state') || join(root, '.local', 'queue.json'));
  const readyFile = options.has('--ready-file') ? resolve(options.get('--ready-file')) : null;
  if (readyFile && readyFile !== join(dirname(statePath), 'session.json')) throw new Error('ready_file_must_share_queue_directory');
  const instanceId = options.get('--instance-id') || randomUUID();
  if (!/^[a-f0-9-]{36}$/.test(instanceId)) throw new Error('instance_id_invalid');
  const packageId = options.get('--package-id') || null;
  if (packageId && !/^[a-f0-9]{64}$/.test(packageId)) throw new Error('package_id_invalid');
  const room = await startLocalControlRoom({ codexPath: options.get('--codex'), gitExecutable: options.get('--git') || 'git', codexHome: options.get('--codex-home'), cwd, statePath, port, instanceId, packageId, recoverStaleLock: options.has('--recover-stale-lock'), template: options.get('--template') || 'software_factory', learningModules: options.get('--learning-modules')?.split(',').filter(Boolean) || [], maxConcurrency: options.has('--max-concurrency') ? Number(options.get('--max-concurrency')) : 1, connect: options.has('--connect'), setupPlan: options.get('--setup-plan'), setupPlanHash: options.get('--setup-plan-sha256') });
  const cleanupReady = async () => {
    if (!readyFile) return;
    const item = await lstat(readyFile).catch(() => null);
    if (!item?.isFile() || item.isSymbolicLink() || item.nlink !== 1 || item.size > 16384) return;
    const data = JSON.parse(await readFile(readyFile, 'utf8'));
    if (data.instanceId === instanceId) await unlink(readyFile).catch(() => {});
  };
  if (readyFile) {
    const item = await lstat(readyFile).catch((error) => error.code === 'ENOENT' ? null : Promise.reject(error));
    if (item && (!item.isFile() || item.isSymbolicLink() || item.nlink !== 1)) { await room.close(); throw new Error('ready_file_invalid'); }
    const temporary = readyFile + '.' + instanceId + '.tmp';
    try {
      await writeFile(temporary, JSON.stringify({ schemaVersion: 1, protocol: 'chronos-control-room', instanceId, packageId, pid: process.pid, origin: room.origin, url: room.url, workspace: cwd, queueFile: statePath, startedAt: new Date().toISOString() }) + '\n', { flag: 'wx', mode: 0o600 });
      await rename(temporary, readyFile);
    } catch (error) { await room.close(); await unlink(temporary).catch(() => {}); throw error; }
    room.server.once('close', () => cleanupReady().catch(() => {}));
  }
  console.log('Chronos Control Room - local managed workflow runtime');
  console.log('Workspace: ' + cwd);
  console.log('Private launch link (keep local): ' + room.url);
  console.log('Paused. No model turns, hooks, installations or recurrences start automatically.');
  let stopping = false;
  const stop = async () => { if (stopping) return; stopping = true; await room.close(); };
  process.once('SIGINT', stop); process.once('SIGTERM', stop);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) main().catch((error) => { console.error(safeCode(error)); process.exitCode = 1; });
