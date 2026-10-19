import http from 'node:http';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { readFile, stat } from 'node:fs/promises';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { CodexAdapter } from './lib/codex-adapter.mjs';
import { Orchestrator } from './lib/engine.mjs';

const root = dirname(fileURLToPath(import.meta.url));
const files = new Map([
  ['/', [join(root, 'public/index.html'), 'text/html; charset=utf-8']],
  ['/app.js', [join(root, 'public/app.js'), 'text/javascript; charset=utf-8']],
  ['/styles.css', [join(root, 'public/styles.css'), 'text/css; charset=utf-8']],
  ['/assets/chronos-mark.png', [resolve(root, '../../plugins/chronos/assets/chronos-mark.png'), 'image/png']]
]);
const safeCode = (error) => /^[a-z][a-z0-9_]{1,95}$/.test(error?.message || '') ? error.message : 'operation_failed';

export async function createControlRoom({ engine, token = randomBytes(32).toString('hex'), port = 0 } = {}) {
  if (!engine || !/^[a-f0-9]{64}$/.test(token)) throw new Error('control_room_parameters_invalid');
  let origin;
  let cookieName;
  let closing;
  const session = randomBytes(32).toString('hex');
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
        if (path === '/api/state' && req.method === 'GET') return respond(res, 200, engine.snapshot());
        if (path !== '/api/actions' || req.method !== 'POST') return respond(res, 404, { error: 'route_not_found' });
        if (req.headers.origin !== origin) return respond(res, 403, { error: 'origin_required' });
        if (req.headers['content-type']?.split(';')[0] !== 'application/json') return respond(res, 415, { error: 'json_required' });
        const chunks = []; let size = 0;
        for await (const chunk of req) {
          size += chunk.length;
          if (size > 65536) { respond(res, 413, { error: 'request_too_large' }); req.resume(); return; }
          chunks.push(chunk);
        }
        let input;
        try { input = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { return respond(res, 400, { error: 'json_invalid' }); }
        if (input?.action === 'shutdown') {
          respond(res, 200, { stopped: true });
          setImmediate(() => close().catch(() => {}));
          return;
        }
        return respond(res, 200, await engine.action(input));
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
  const timer = setInterval(() => engine.tick().catch(() => {}), 15000); timer.unref();
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

async function main() {
  const options = new Map();
  for (let i = 2; i < process.argv.length; i += 2) {
    if (process.argv[i] === '--recover-stale-lock') { options.set(process.argv[i], true); i -= 1; continue; }
    if (!['--codex', '--cwd', '--state', '--port', '--codex-home'].includes(process.argv[i]) || !process.argv[i + 1]) throw new Error('usage_node_server_mjs_--codex_absolute_executable_--cwd_repository');
    options.set(process.argv[i], process.argv[i + 1]);
  }
  const cwd = resolve(options.get('--cwd') || process.cwd());
  if (!(await stat(cwd)).isDirectory()) throw new Error('workspace_directory_required');
  const port = options.has('--port') ? Number(options.get('--port')) : 0;
  if (!Number.isInteger(port) || port < 0 || port > 65535) throw new Error('port_invalid');
  const adapter = new CodexAdapter({ codexPath: options.get('--codex'), cwd, codexHome: options.get('--codex-home') });
  const statePath = resolve(options.get('--state') || join(root, '.local', 'queue.json'));
  const engine = await new Orchestrator({ adapter, statePath, recoverStaleLock: options.has('--recover-stale-lock') }).initialize();
  let room;
  try { room = await createControlRoom({ engine, port }); }
  catch (error) { await engine.close(); throw error; }
  console.log('Chronos Control Room - experimental, not a marketplace release');
  console.log('Workspace: ' + cwd);
  console.log('Private launch link (keep local): ' + room.url);
  console.log('Paused. No model turns, hooks, installations or recurrences start automatically.');
  let stopping = false;
  const stop = async () => { if (stopping) return; stopping = true; await room.close(); };
  process.once('SIGINT', stop); process.once('SIGTERM', stop);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) main().catch((error) => { console.error(safeCode(error)); process.exitCode = 1; });
