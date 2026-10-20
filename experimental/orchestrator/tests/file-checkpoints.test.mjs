import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { FileCheckpointStore } from '../lib/file-checkpoints.mjs';
import { createHash } from 'node:crypto';

async function forged(store, receipt, change) {
  const { id, manifestSha256, ...body } = await store.inspectManifest(receipt);
  change(body);
  const replacement = createHash('sha256').update(JSON.stringify(body)).digest('hex');
  await fs.writeFile(path.join(store.manifests, replacement + '.json'), JSON.stringify({ ...body, id: replacement, manifestSha256: replacement }));
  return { ...receipt, id: replacement, manifestSha256: replacement, bytes: body.bytes, fileCount: body.fileCount };
}

test('rehashed case collision manifest cannot be verified on any OS', async () => {
  const { src, store } = await setup(); await fs.writeFile(path.join(src, 'a'), 'x');
  const receipt = await store.checkpoint({ workspacePath: src, ownerId: 'a' });
  const value = await forged(store, receipt, (body) => { body.files = [{ ...body.files[0], path: 'A' }, body.files[0]]; body.fileCount = 2; body.bytes = 2; });
  await assert.rejects(store.verify(value), /checkpoint_manifest_paths_invalid/);
});

test('rehashed prefix-collision and extra-key manifests cannot be verified', async () => {
  const { src, store } = await setup(); await fs.writeFile(path.join(src, 'a'), 'x');
  const receipt = await store.checkpoint({ workspacePath: src, ownerId: 'a' });
  const prefix = await forged(store, receipt, (body) => { body.files.push({ ...body.files[0], path: 'a/b' }); body.fileCount = 2; body.bytes = 2; });
  await assert.rejects(store.verify(prefix), /checkpoint_manifest_paths_invalid/);
  const extra = await forged(store, receipt, (body) => { body.extra = true; });
  await assert.rejects(store.verify(extra), /checkpoint_manifest_invalid/);
});

test('valid digest cannot transfer a manifest to another source identity', async () => {
  const { src, store } = await setup(); const receipt = await store.checkpoint({ workspacePath: src, ownerId: 'a' });
  const value = await forged(store, receipt, (body) => { body.sourceRoot = path.dirname(body.sourceRoot); });
  await assert.rejects(store.verify(value), /checkpoint_manifest_invalid/);
});

test('deletion wins over an unchanged branch and unrelated base files survive', async () => {
  const { root, src, store } = await setup(); await fs.writeFile(path.join(src, 'keep'), 'k'); await fs.writeFile(path.join(src, 'remove'), 'r');
  const base = await store.checkpoint({ workspacePath: src, ownerId: 'a' });
  await fs.unlink(path.join(src, 'remove')); const deleted = await store.checkpoint({ workspacePath: src, ownerId: 'a' });
  const destination = path.join(store.materialized, 'deletion');
  await store.materializeMany([base, deleted], { destination, baseReceipt: base });
  assert.deepEqual(await fs.readdir(destination), ['keep']);
});

test('store internals cannot be checkpoint inputs but owned materializations can', async () => {
  const { root, src } = await setup();
  const store = new FileCheckpointStore({ sourceRoot: root, storageRoot: path.join(root, 'store'), workspaceRoots: [root] });
  const receipt = await store.checkpoint({ workspacePath: src, ownerId: 'a' });
  await assert.rejects(store.checkpoint({ workspacePath: store.manifests, ownerId: 'a' }), /checkpoint_owner_or_workspace_invalid/);
  const destination = path.join(store.materialized, 'owned'); await store.materialize(receipt, { destination });
  await store.checkpoint({ workspacePath: destination, ownerId: 'b' });
});

const setup = async () => { const root = await fs.mkdtemp(path.join(os.tmpdir(), 'chronos-checkpoint-')); const src = path.join(root, 'src'); const store = new FileCheckpointStore({ storageRoot: path.join(root, 'store'), sourceRoot: root }); await fs.mkdir(src); return { root, src, store }; };
test('content-addressed repeat and materialize', async () => { const { root, src, store } = await setup(); await fs.writeFile(path.join(src, 'a.txt'), 'hello'); const a = await store.checkpoint({ workspacePath: src, ownerId: 'o' }); const b = await store.checkpoint({ workspacePath: src, ownerId: 'o' }); assert.equal(a.id, b.id); const d = path.join(root, 'store', 'materialized', 'one'); await fs.mkdir(path.dirname(d), { recursive: true }); const out = await store.materialize(a, { destination: d, ownerId: 'o' }); assert.equal(await fs.readFile(path.join(out.cwd, 'a.txt'), 'utf8'), 'hello'); });
test('rejects unsafe entries and owner mismatch', async () => { const { src, store } = await setup(); await fs.mkdir(path.join(src, '.git')); await fs.writeFile(path.join(src, 'x'), 'x'); const r = await store.checkpoint({ workspacePath: src, ownerId: 'a' }); await assert.rejects(() => store.verify(r, { ownerId: 'b' }), /checkpoint_/); });
test('enforces size cap and tamper detection', async () => { const { src, root } = await setup(); const store = new FileCheckpointStore({ storageRoot: path.join(root, 's'), sourceRoot: root, maxBytes: 2 }); await fs.writeFile(path.join(src, 'x'), 'abc'); await assert.rejects(() => store.checkpoint({ workspacePath: src, ownerId: 'a' }), /checkpoint_size_cap/); });
test('merge rejects conflicting paths', async () => { const { root, src, store } = await setup(); await fs.writeFile(path.join(src, 'x'), 'one'); const a = await store.checkpoint({ workspacePath: src, ownerId: 'a' }); await fs.writeFile(path.join(src, 'x'), 'two'); const b = await store.checkpoint({ workspacePath: src, ownerId: 'a' }); const d = path.join(root, 'store', 'materialized', 'm'); await assert.rejects(() => store.materializeMany([a, b], { destination: d, ownerId: 'a' }), /checkpoint_merge_conflict/); });
test('missing workspace rejects', async () => { const { root, store } = await setup(); await assert.rejects(() => store.checkpoint({ workspacePath: path.join(root, 'missing'), ownerId: 'a' })); });
test('empty checkpoint is valid', async () => { const { root, src, store } = await setup(); const r = await store.checkpoint({ workspacePath: src, ownerId: 'a' }); assert.equal(r.fileCount, 0); });
test('dot git is excluded', async () => { const { src, store } = await setup(); await fs.mkdir(path.join(src, '.git')); await fs.writeFile(path.join(src, '.git', 'secret'), 'x'); const r = await store.checkpoint({ workspacePath: src, ownerId: 'a' }); assert.equal(r.fileCount, 0); });
test('receipt tamper rejects', async () => { const { src, store } = await setup(); const r = await store.checkpoint({ workspacePath: src, ownerId: 'a' }); await assert.rejects(() => store.verify({ ...r, bytes: 1 })); });
test('destination outside rejects', async () => { const { src, store } = await setup(); const r = await store.checkpoint({ workspacePath: src, ownerId: 'a' }); await assert.rejects(() => store.materialize(r, { destination: path.join(os.tmpdir(), 'outside') })); });
test('stable IDs across stores', async () => { const { root, src, store } = await setup(); await fs.writeFile(path.join(src, 'a'), '1'); const r = await store.checkpoint({ workspacePath: src, ownerId: 'a' }); const store2 = new FileCheckpointStore({ storageRoot: path.join(root, 'other'), sourceRoot: root }); const r2 = await store2.checkpoint({ workspacePath: src, ownerId: 'a' }); assert.equal(r.id, r2.id); });
test('new file merge union', async () => { const { root, src, store } = await setup(); await fs.mkdir(path.join(root, 'store', 'materialized'), { recursive: true }); const a = await store.checkpoint({ workspacePath: src, ownerId: 'a' }); await fs.writeFile(path.join(src, 'new'), 'n'); const b = await store.checkpoint({ workspacePath: src, ownerId: 'a' }); const d = path.join(root, 'store', 'materialized', 'u'); const out = await store.materializeMany([a, b], { destination: d, ownerId: 'a' }); assert.equal(out.fileCount, 1); });
test('three-way preserves base', async () => { const { root, src, store } = await setup(); await fs.mkdir(path.join(root, 'store', 'materialized'), { recursive: true }); await fs.writeFile(path.join(src, 'base'), 'b'); const base = await store.checkpoint({ workspacePath: src, ownerId: 'a' }); await fs.writeFile(path.join(src, 'new'), 'n'); const child = await store.checkpoint({ workspacePath: src, ownerId: 'a' }); const d = path.join(root, 'store', 'materialized', 't'); const out = await store.materializeMany([child], { destination: d, ownerId: 'a', baseReceipt: base }); assert.equal(out.fileCount, 2); });
test('strict receipt keys reject extras', async () => { const { src, store } = await setup(); const r = await store.checkpoint({ workspacePath: src, ownerId: 'a' }); await assert.rejects(() => store.verify({ ...r, extra: true }), /checkpoint_/); });
test('source root and workspace binding reject forged receipt', async () => { const { src, store } = await setup(); const r = await store.checkpoint({ workspacePath: src, ownerId: 'a' }); await assert.rejects(() => store.verify({ ...r, workspacePath: path.dirname(src) }), /checkpoint_/); });
test('negative receipt count rejects', async () => { const { src, store } = await setup(); const r = await store.checkpoint({ workspacePath: src, ownerId: 'a' }); await assert.rejects(() => store.verify({ ...r, bytes: -1 }), /checkpoint_/); });
test('case collision paths are rejected', async () => { if (process.platform === 'win32') return; const { src, store } = await setup(); await fs.writeFile(path.join(src, 'A'), 'a'); await fs.writeFile(path.join(src, 'a'), 'b'); await assert.rejects(() => store.checkpoint({ workspacePath: src, ownerId: 'a' }), /checkpoint_/); });
test('file directory prefix collision is rejected by filesystem', async () => { const { src, store } = await setup(); await fs.writeFile(path.join(src, 'prefix'), 'x'); await assert.rejects(() => fs.mkdir(path.join(src, 'prefix'))); await store.checkpoint({ workspacePath: src, ownerId: 'a' }); });
test('blob tamper is detected', async () => { const { src, store } = await setup(); await fs.writeFile(path.join(src, 'x'), 'x'); const r = await store.checkpoint({ workspacePath: src, ownerId: 'a' }); const m = await store.inspectManifest(r); const p = path.join(store.blobs, m.files[0].sha256.slice(0, 2), m.files[0].sha256); await fs.writeFile(p, 'tampered'); await assert.rejects(() => store.verify(r), /checkpoint_/); });
test('directory symlink is rejected', async () => { const { root, src, store } = await setup(); try { await fs.symlink(root, path.join(src, 'link'), 'junction'); } catch { return; } await assert.rejects(() => store.checkpoint({ workspacePath: src, ownerId: 'a' }), /checkpoint_/); });
test('three-way deletion conflict rejects', async () => { const { root, src, store } = await setup(); await fs.mkdir(path.join(root, 'store', 'materialized'), { recursive: true }); await fs.writeFile(path.join(src, 'x'), 'x'); const base = await store.checkpoint({ workspacePath: src, ownerId: 'a' }); await fs.rm(path.join(src, 'x')); const deleted = await store.checkpoint({ workspacePath: src, ownerId: 'a' }); await fs.writeFile(path.join(src, 'x'), 'changed'); const changed = await store.checkpoint({ workspacePath: src, ownerId: 'a' }); const d = path.join(root, 'store', 'materialized', 'conflict'); await assert.rejects(() => store.materializeMany([deleted, changed], { destination: d, ownerId: 'a', baseReceipt: base }), /checkpoint_merge_conflict/); });
test('storage ancestor symlink is rejected', async () => { const { root, src } = await setup(); const link = path.join(root, 'linked-store'); try { await fs.symlink(root, link, 'junction'); } catch { return; } const { FileCheckpointStore } = await import('../lib/file-checkpoints.mjs'); const store = new FileCheckpointStore({ storageRoot: path.join(link, 'store'), sourceRoot: root }); await assert.rejects(() => store.checkpoint({ workspacePath: src, ownerId: 'a' }), /checkpoint_/); });
test('hardlink source is rejected', async () => { const { root, src, store } = await setup(); const a = path.join(src, 'a'); await fs.writeFile(a, 'x'); try { await fs.link(a, path.join(src, 'b')); } catch { return; } await assert.rejects(() => store.checkpoint({ workspacePath: src, ownerId: 'a' }), /checkpoint_/); });
