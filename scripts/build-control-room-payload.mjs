import { mkdir, readFile, writeFile, lstat } from 'node:fs/promises';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const source = join(repo, 'experimental/orchestrator');
const destination = join(repo, 'plugins/chronos/skills/chronos-control-room/scripts/runtime');
const version = JSON.parse(await readFile(join(repo, 'plugins/chronos/.codex-plugin/plugin.json'), 'utf8')).version;
const files = [
  'server.mjs', 'launcher.mjs', 'lib/codex-adapter.mjs', 'lib/engine.mjs',
  'lib/runtime-health.mjs', 'lib/runtime-discovery.mjs', 'lib/templates.mjs', 'lib/control-client.mjs',
  'lib/workflow-contracts.mjs', 'lib/collaboration.mjs', 'lib/collaboration-state.mjs', 'lib/file-checkpoints.mjs', 'lib/workspaces.mjs', 'lib/setup-plan.mjs', 'lib/protocol-capabilities.mjs', 'lib/agent-state.mjs', 'public/app.js',
  'public/app.css', 'public/index.html', 'public/chronos-mark.png'
];
const record = { schemaVersion: 1, pluginVersion: version, files: [] };
for (const path of files) {
  const origin = join(source, path), item = await lstat(origin);
  if (!item.isFile() || item.isSymbolicLink() || item.nlink !== 1 || item.size > 8 * 1048576) throw new Error('payload_source_invalid');
  let bytes = await readFile(origin);
  if (/\.(mjs|js|css|html)$/.test(path)) bytes = Buffer.from(bytes.toString('utf8').replace(/\r\n?/g, '\n'));
  await mkdir(dirname(join(destination, path)), { recursive: true });
  await writeFile(join(destination, path), bytes);
  record.files.push({ path, bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') });
}
await writeFile(join(destination, 'payload.json'), JSON.stringify(record, null, 2) + '\n');
console.log(JSON.stringify({ ok: true, pluginVersion: version, files: files.length, bytes: record.files.reduce((total, file) => total + file.bytes, 0) }));
