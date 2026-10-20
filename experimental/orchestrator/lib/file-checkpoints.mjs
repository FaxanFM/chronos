import { createHash, randomUUID } from 'node:crypto';
import { constants } from 'node:fs';
import { lstat, open, mkdir, readdir, link, unlink } from 'node:fs/promises';
import { resolve, relative, isAbsolute, dirname, join, sep } from 'node:path';

const fail = (code) => { throw new Error(code); };
const hash = (bytes) => createHash('sha256').update(bytes).digest('hex');
const digest = (value) => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const ordinal = (a, b) => a < b ? -1 : a > b ? 1 : 0;
const within = (root, value) => { const part = relative(root, value); return !part.startsWith('..') && !isAbsolute(part); };
const exact = (value, keys) => value && typeof value === 'object' && !Array.isArray(value) && Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));
const RECEIPT_KEYS = ['schemaVersion', 'id', 'manifestSha256', 'fileCount', 'bytes', 'excludedPaths', 'ownerId', 'workspacePath'];
const MANIFEST_KEYS = ['schemaVersion', 'sourceRoot', 'workspacePath', 'ownerId', 'excludedPaths', 'fileCount', 'bytes', 'files'];
const MAX_MANIFEST_BYTES = 2 * 1048576;

function safePath(value) {
  if (typeof value !== 'string' || !value || value.length > 4096 || isAbsolute(value) || value.includes('\\')) fail('checkpoint_unsafe_path');
  const parts = value.split('/');
  if (parts.length > 64) fail('checkpoint_unsafe_path');
  for (const part of parts) {
    if (!part || part === '.' || part === '..' || /[<>:"|?*\x00-\x1f\x7f]/.test(part) || /[. ]$/.test(part) || /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$/i.test(part) || part.toLowerCase() === '.git') fail('checkpoint_unsafe_path');
  }
}

function validPaths(files) {
  const names = new Set(), directories = new Map();
  let previous = '';
  for (const file of files) {
    safePath(file.path);
    if (previous && ordinal(previous, file.path) >= 0) fail('checkpoint_manifest_paths_invalid');
    previous = file.path;
    const lower = file.path.toLowerCase();
    if (names.has(lower) || directories.has(lower)) fail('checkpoint_manifest_paths_invalid');
    const parts = file.path.split('/');
    for (let index = 1; index < parts.length; index++) {
      const spelling = parts.slice(0, index).join('/'), key = spelling.toLowerCase();
      if (names.has(key) || directories.has(key) && directories.get(key) !== spelling) fail('checkpoint_manifest_paths_invalid');
      directories.set(key, spelling);
    }
    names.add(lower);
  }
}

async function safeAncestors(path) {
  for (let cursor = resolve(path);;) {
    const info = await lstat(cursor).catch((error) => error.code === 'ENOENT' ? null : Promise.reject(error));
    if (info && (info.isSymbolicLink() || !info.isDirectory())) fail('checkpoint_reparse_ancestor');
    const parent = dirname(cursor);
    if (cursor === parent) return;
    cursor = parent;
  }
}

function sameIdentity(a, b) {
  return a.isFile() && b.isFile() && !a.isSymbolicLink() && !b.isSymbolicLink() && a.nlink === 1 && b.nlink === 1 && a.ino === b.ino && a.dev === b.dev && a.size === b.size && a.mtimeMs === b.mtimeMs && a.ctimeMs === b.ctimeMs;
}

async function readRegular(path, maxBytes) {
  if (!Number.isSafeInteger(maxBytes) || maxBytes < 0) fail('checkpoint_size_cap');
  await safeAncestors(dirname(path));
  const before = await lstat(path);
  if (!before.isFile() || before.isSymbolicLink() || before.nlink !== 1) fail('checkpoint_reparse_entry');
  if (before.size > maxBytes) fail('checkpoint_size_cap');
  const handle = await open(path, constants.O_RDONLY | (constants.O_NOFOLLOW || 0));
  try {
    if (!sameIdentity(before, await handle.stat())) fail('checkpoint_source_changed');
    const chunks = [], buffer = Buffer.alloc(Math.min(65536, maxBytes + 1));
    let total = 0;
    for (;;) {
      const { bytesRead } = await handle.read(buffer, 0, buffer.length, null);
      if (!bytesRead) break;
      total += bytesRead;
      if (total > maxBytes) fail('checkpoint_size_cap');
      chunks.push(Buffer.from(buffer.subarray(0, bytesRead)));
    }
    const after = await lstat(path);
    if (!sameIdentity(before, after) || !sameIdentity(before, await handle.stat()) || total !== before.size) fail('checkpoint_source_changed');
    await safeAncestors(dirname(path));
    return Buffer.concat(chunks);
  } finally { await handle.close(); }
}

async function safeMkdir(path) {
  await safeAncestors(path);
  await mkdir(path, { recursive: true, mode: 0o700 });
  await safeAncestors(path);
}

// Publish only complete files. Existing objects must contain exactly the same bytes.
async function publish(path, bytes) {
  await safeMkdir(dirname(path));
  const temp = path + '.' + randomUUID() + '.tmp';
  let handle;
  try {
    handle = await open(temp, 'wx', 0o600);
    await handle.writeFile(bytes); await handle.sync(); await handle.close(); handle = null;
    try { await link(temp, path); }
    catch (error) { if (error.code !== 'EEXIST') throw error; }
    await unlink(temp);
    const existing = await readRegular(path, Buffer.byteLength(bytes));
    if (!existing.equals(Buffer.from(bytes))) fail('checkpoint_publish_conflict');
  } finally { if (handle) await handle.close().catch(() => {}); await unlink(temp).catch(() => {}); }
}

export class FileCheckpointStore {
  constructor({ storageRoot, sourceRoot, workspaceRoots, maxBytes = 64 * 1048576, maxFiles = 4096 } = {}) {
    if (typeof storageRoot !== 'string' || !storageRoot || typeof sourceRoot !== 'string' || !sourceRoot || !Number.isSafeInteger(maxBytes) || maxBytes < 1 || maxBytes > 1024 * 1048576 || !Number.isInteger(maxFiles) || maxFiles < 1 || maxFiles > 16384) fail('checkpoint_config_invalid');
    this.storageRoot = resolve(storageRoot); this.sourceRoot = resolve(sourceRoot);
    this.materialized = join(this.storageRoot, 'materialized');
    this.blobs = join(this.storageRoot, 'blobs'); this.manifests = join(this.storageRoot, 'manifests');
    this.workspaceRoots = (workspaceRoots || [this.sourceRoot, this.materialized]).map((root) => resolve(root));
    this.maxBytes = maxBytes; this.maxFiles = maxFiles;
  }

  validWorkspace(path) {
    return typeof path === 'string' && isAbsolute(path) && resolve(path) === path && this.workspaceRoots.some((root) => within(root, path)) && !within(path, this.storageRoot) && (!within(this.storageRoot, path) || within(this.materialized, path) && path !== this.materialized);
  }

  validateReceipt(receipt, ownerId) {
    if (!exact(receipt, RECEIPT_KEYS) || receipt.schemaVersion !== 1 || !digest(receipt.id) || receipt.id !== receipt.manifestSha256 || !Number.isInteger(receipt.fileCount) || receipt.fileCount < 0 || receipt.fileCount > this.maxFiles || !Number.isSafeInteger(receipt.bytes) || receipt.bytes < 0 || receipt.bytes > this.maxBytes || !Array.isArray(receipt.excludedPaths) || JSON.stringify(receipt.excludedPaths) !== '[".git"]' || typeof receipt.ownerId !== 'string' || !receipt.ownerId || receipt.ownerId.length > 200 || !this.validWorkspace(receipt.workspacePath)) fail('checkpoint_receipt_invalid');
    if (ownerId != null && receipt.ownerId !== ownerId) fail('checkpoint_owner_mismatch');
  }

  async walk(root, directory = root, files = [], directoryCount = { value: 0 }) {
    await safeAncestors(directory);
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      if (directory === root && entry.name === '.git') continue;
      const absolute = join(directory, entry.name), path = relative(root, absolute).split(sep).join('/');
      safePath(path);
      const info = await lstat(absolute);
      if (info.isSymbolicLink()) fail('checkpoint_reparse_entry');
      if (info.isDirectory()) {
        if (++directoryCount.value > this.maxFiles * 4) fail('checkpoint_directory_cap');
        await this.walk(root, absolute, files, directoryCount);
      } else if (info.isFile()) {
        if (info.nlink !== 1) fail('checkpoint_hardlink');
        files.push({ absolute, path });
        if (files.length > this.maxFiles) fail('checkpoint_file_cap');
      } else fail('checkpoint_special_file');
    }
    return files;
  }

  async checkpoint({ workspacePath, ownerId } = {}) {
    if (!this.validWorkspace(workspacePath) || typeof ownerId !== 'string' || !ownerId || ownerId.length > 200) fail('checkpoint_owner_or_workspace_invalid');
    await safeAncestors(workspacePath);
    const directory = await lstat(workspacePath);
    if (!directory.isDirectory()) fail('checkpoint_workspace_invalid');
    const entries = (await this.walk(workspacePath)).sort((a, b) => ordinal(a.path, b.path));
    validPaths(entries);
    const files = []; let bytes = 0;
    for (const entry of entries) {
      const data = await readRegular(entry.absolute, this.maxBytes - bytes);
      bytes += data.length;
      const sha256 = hash(data);
      await publish(join(this.blobs, sha256.slice(0, 2), sha256), data);
      files.push({ path: entry.path, bytes: data.length, sha256 });
    }
    const after = (await this.walk(workspacePath)).sort((a, b) => ordinal(a.path, b.path));
    if (JSON.stringify(entries) !== JSON.stringify(after)) fail('checkpoint_source_changed');
    for (const file of files) if (hash(await readRegular(join(workspacePath, ...file.path.split('/')), file.bytes)) !== file.sha256) fail('checkpoint_source_changed');
    const manifest = { schemaVersion: 1, sourceRoot: this.sourceRoot, workspacePath, ownerId, excludedPaths: ['.git'], fileCount: files.length, bytes, files };
    const id = hash(JSON.stringify(manifest));
    const body = JSON.stringify({ ...manifest, id, manifestSha256: id });
    if (Buffer.byteLength(body) > MAX_MANIFEST_BYTES) fail('checkpoint_manifest_size_cap');
    await publish(join(this.manifests, id + '.json'), body);
    return { schemaVersion: 1, id, manifestSha256: id, fileCount: files.length, bytes, excludedPaths: ['.git'], ownerId, workspacePath };
  }

  async inspectManifest(receipt) {
    this.validateReceipt(receipt);
    let manifest;
    try { manifest = JSON.parse(await readRegular(join(this.manifests, receipt.id + '.json'), MAX_MANIFEST_BYTES)); }
    catch (error) { if (error.code === 'ENOENT') fail('checkpoint_manifest_missing'); if (error instanceof SyntaxError) fail('checkpoint_manifest_invalid'); throw error; }
    if (!exact(manifest, [...MANIFEST_KEYS, 'id', 'manifestSha256']) || manifest.sourceRoot !== this.sourceRoot || manifest.id !== receipt.id || manifest.manifestSha256 !== receipt.id || MANIFEST_KEYS.filter((key) => key !== 'files' && key !== 'sourceRoot').some((key) => JSON.stringify(manifest[key]) !== JSON.stringify(receipt[key])) || !Array.isArray(manifest.files) || manifest.files.length !== receipt.fileCount) fail('checkpoint_manifest_invalid');
    const content = Object.fromEntries(MANIFEST_KEYS.map((key) => [key, manifest[key]]));
    if (hash(JSON.stringify(content)) !== receipt.id) fail('checkpoint_manifest_tampered');
    validPaths(manifest.files);
    let bytes = 0;
    for (const file of manifest.files) {
      if (!exact(file, ['path', 'bytes', 'sha256']) || !Number.isSafeInteger(file.bytes) || file.bytes < 0 || !digest(file.sha256)) fail('checkpoint_manifest_invalid');
      bytes += file.bytes;
      if (!Number.isSafeInteger(bytes) || bytes > this.maxBytes) fail('checkpoint_size_cap');
    }
    if (bytes !== receipt.bytes) fail('checkpoint_manifest_invalid');
    return manifest;
  }

  async readBlob(file) {
    let data;
    try { data = await readRegular(join(this.blobs, file.sha256.slice(0, 2), file.sha256), file.bytes); }
    catch (error) { if (error.code === 'ENOENT') fail('checkpoint_blob_missing'); throw error; }
    if (data.length !== file.bytes || hash(data) !== file.sha256) fail('checkpoint_blob_tampered');
    return data;
  }

  async verify(receipt, { ownerId } = {}) {
    this.validateReceipt(receipt, ownerId);
    const manifest = await this.inspectManifest(receipt);
    for (const file of manifest.files) await this.readBlob(file);
    return manifest;
  }

  async writeFiles(files, destination) {
    if (typeof destination !== 'string' || !isAbsolute(destination) || resolve(destination) !== destination || destination === this.materialized || !within(this.materialized, destination)) fail('checkpoint_destination_invalid');
    validPaths(files);
    if (files.length > this.maxFiles || files.reduce((sum, file) => sum + file.bytes, 0) > this.maxBytes) fail('checkpoint_size_cap');
    await safeMkdir(dirname(destination));
    try { await mkdir(destination, { mode: 0o700 }); }
    catch (error) { if (error.code === 'EEXIST') fail('checkpoint_destination_exists'); throw error; }
    for (const file of files) {
      const target = join(destination, ...file.path.split('/'));
      await safeMkdir(dirname(target));
      const handle = await open(target, 'wx', 0o600);
      try { await handle.writeFile(await this.readBlob(file)); }
      finally { await handle.close(); }
    }
    return { cwd: destination, fileCount: files.length };
  }

  async materialize(receipt, { destination, ownerId } = {}) {
    const manifest = await this.verify(receipt, { ownerId });
    return { ...await this.writeFiles(manifest.files, destination), id: manifest.id };
  }

  async materializeMany(receipts, { destination, ownerId, baseReceipt } = {}) {
    if (!Array.isArray(receipts) || !receipts.length || receipts.length > 32) fail('checkpoint_merge_inputs_invalid');
    const manifests = [];
    for (const receipt of receipts) manifests.push(await this.verify(receipt, { ownerId }));
    const base = baseReceipt ? await this.verify(baseReceipt) : null;
    const baseFiles = new Map((base?.files || []).map((file) => [file.path, file]));
    const maps = manifests.map((manifest) => new Map(manifest.files.map((file) => [file.path, file])));
    const paths = new Set([...baseFiles.keys(), ...maps.flatMap((map) => [...map.keys()])]);
    const files = [];
    for (const path of [...paths].sort(ordinal)) {
      const original = baseFiles.get(path)?.sha256 ?? null;
      const values = base ? maps.map((map) => map.get(path)?.sha256 ?? null).filter((value) => value !== original) : maps.flatMap((map) => map.has(path) ? [map.get(path).sha256] : []);
      const changes = [...new Set(values)];
      if (changes.length > 1) fail('checkpoint_merge_conflict');
      const chosen = changes.length ? changes[0] : original;
      if (chosen !== null) files.push(maps.find((map) => map.get(path)?.sha256 === chosen)?.get(path) || baseFiles.get(path));
    }
    return { ...await this.writeFiles(files, destination), sourceIds: manifests.map((manifest) => manifest.id) };
  }
}
