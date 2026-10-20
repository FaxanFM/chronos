import { createHash, randomUUID } from 'node:crypto';
import { execFile } from 'node:child_process';
import { mkdir, lstat, readFile, writeFile, realpath } from 'node:fs/promises';
import { resolve, join, relative, isAbsolute, parse, basename } from 'node:path';
import { FileCheckpointStore } from './file-checkpoints.mjs';

export function executeWorkspaceGit(file, args, options = {}) {
  const { input, ...settings } = options;
  if (input != null && (typeof input !== 'string' || Buffer.byteLength(input) > 1048576)) return Promise.reject(new Error('workspace_git_input_invalid'));
  return new Promise((accept, reject) => {
    const child = execFile(file, args, settings, (error, stdout, stderr) => error ? reject(Object.assign(error, { stdout, stderr })) : accept({ stdout, stderr }));
    child.stdin?.on('error', () => {});
    child.stdin?.end(input || '');
  });
}
const within = (root, value) => { const path = relative(root, value); return !path.startsWith('..') && !isAbsolute(path); };

async function rejectLinks(path) {
  let cursor = resolve(path);
  while (cursor !== parse(cursor).root) {
    const info = await lstat(cursor).catch((error) => error.code === 'ENOENT' ? null : Promise.reject(error));
    if (info?.isSymbolicLink()) throw new Error('workspace_symlink_not_allowed');
    cursor = resolve(cursor, '..');
  }
}

export class WorkspaceManager {
  constructor({ sourceRoot, storageRoot, gitExecutable = 'git', execute = executeWorkspaceGit, checkpointStore = null } = {}) {
    this.sourceRoot = resolve(sourceRoot);
    this.storageRoot = resolve(storageRoot);
    this.gitExecutable = gitExecutable;
    this.execute = execute;
    this.checkpointStore = checkpointStore || new FileCheckpointStore({ sourceRoot: this.sourceRoot, storageRoot: join(this.storageRoot, 'checkpoints'), workspaceRoots: [this.storageRoot] });
    this.inflight = new Map();
    this.seedCheckpoints = new Map();
    this.seedMetadata = join(this.storageRoot, '.checkpoint-seeds');
  }

  async prepare({ packetId, taskId, policy = 'read-only', workspacePath, collaborative = false, attempt = 1, inputCheckpoints = [], baseCheckpoint = null, priorCheckpoint = null, priorBaseCheckpoint = null, repairCheckpoint = null, packetBaseCheckpoint = null } = {}) {
    if (!['read-only', 'workspace-write'].includes(policy)) throw new Error('workspace_policy_invalid');
    if (policy === 'read-only' && (!workspacePath || collaborative) && !inputCheckpoints?.length && !baseCheckpoint && !priorCheckpoint && !repairCheckpoint && !packetBaseCheckpoint) return { cwd: this.sourceRoot, workspacePath: null, kind: 'source_read_only', base: 'selected workspace' };
    if (collaborative && !this.checkpointStore) throw new Error('workspace_checkpoint_manager_required');
    const key = String(packetId || taskId || '');
    if (!key || key.length > 200) throw new Error('workspace_owner_required');
    const slug = createHash('sha256').update(collaborative ? `${key}:attempt:${attempt}` : key).digest('hex').slice(0, 24);
    const base = join(this.storageRoot, slug);
    const cwd = join(base, 'work');
    if (workspacePath && resolve(workspacePath) !== cwd) throw new Error('workspace_not_owned');
    if (workspacePath) return this.readOwned(base, cwd, slug);
    if (collaborative || inputCheckpoints?.length || baseCheckpoint || priorCheckpoint || repairCheckpoint || packetBaseCheckpoint) {
      if (!this.checkpointStore) throw new Error('workspace_checkpoint_manager_required');
      return this.prepareCheckpointWorkspace({ packetId: String(packetId), taskId: String(taskId || packetId), policy, attempt, inputCheckpoints, baseCheckpoint, priorCheckpoint, priorBaseCheckpoint, repairCheckpoint, packetBaseCheckpoint });
    }
    if (this.inflight.has(slug)) return this.inflight.get(slug);
    const pending = this.createOwned(base, cwd, slug).finally(() => this.inflight.delete(slug));
    this.inflight.set(slug, pending);
    return pending;
  }

  async seedCheckpoint(packetId) {
    if (!this.checkpointStore) throw new Error('workspace_checkpoint_manager_required');
    if (this.seedCheckpoints.has(packetId)) return this.seedCheckpoints.get(packetId);
    if (this.inflight.has(`seed:${packetId}`)) return this.inflight.get(`seed:${packetId}`);
    const pending = this.createSeedCheckpoint(packetId).finally(() => this.inflight.delete(`seed:${packetId}`));
    this.inflight.set(`seed:${packetId}`, pending);
    return pending;
  }

  async createSeedCheckpoint(packetId) {
    await rejectLinks(this.seedMetadata);
    await mkdir(this.seedMetadata, { recursive: true, mode: 0o700 });
    const seedFile = join(this.seedMetadata, createHash('sha256').update(packetId).digest('hex') + '.json');
    const info = await lstat(seedFile).catch((error) => error.code === 'ENOENT' ? null : Promise.reject(error));
    if (info && (!info.isFile() || info.isSymbolicLink() || info.nlink !== 1 || info.size > 8192)) throw new Error('workspace_seed_metadata_invalid');
    const stored = await readFile(seedFile, 'utf8').then((text) => JSON.parse(text)).catch((error) => { if (error.code === 'ENOENT') return null; throw new Error('workspace_seed_metadata_invalid'); });
    if (stored) { await this.checkpointStore.verify(stored, { ownerId: `seed:${packetId}` }); this.seedCheckpoints.set(packetId, stored); return stored; }
    const prepared = await this.prepare({ packetId: `${packetId}:seed`, taskId: `${packetId}:seed`, policy: 'workspace-write' });
    const receipt = await this.checkpointStore.checkpoint({ workspacePath: prepared.cwd, ownerId: `seed:${packetId}` });
    await writeFile(seedFile, JSON.stringify(receipt), { flag: 'wx', mode: 0o600 });
    this.seedCheckpoints.set(packetId, receipt); return receipt;
  }

  async prepareCheckpointWorkspace({ packetId, taskId, policy, attempt, inputCheckpoints, priorCheckpoint, priorBaseCheckpoint, repairCheckpoint, packetBaseCheckpoint }) {
    if (!packetId || !taskId || taskId.length > 100 || !Number.isInteger(attempt) || attempt < 1 || attempt > 3) throw new Error('workspace_checkpoint_identity_invalid');
    const seed = await this.seedCheckpoint(packetId);
    if (packetBaseCheckpoint && packetBaseCheckpoint.id !== seed.id) throw new Error('checkpoint_seed_changed');
    if (priorCheckpoint && !priorBaseCheckpoint) throw new Error('checkpoint_prior_base_required');
    const sources = repairCheckpoint ? [repairCheckpoint] : priorCheckpoint ? [...(inputCheckpoints || []), priorCheckpoint] : inputCheckpoints?.length ? inputCheckpoints : [packetBaseCheckpoint || seed];
    const baseReceipt = priorCheckpoint ? (priorBaseCheckpoint || seed) : (packetBaseCheckpoint || seed);
    const destination = join(this.checkpointStore.materialized, createHash('sha256').update(`${taskId}:${attempt}:${randomUUID()}`).digest('hex').slice(0, 24));
    if (process.platform === 'win32' && destination.length > 240) throw new Error('workspace_native_path_too_long');
    const materialized = sources.length === 1 ? await this.checkpointStore.materialize(sources[0], { destination, ownerId: sources[0].ownerId || undefined }) : await this.checkpointStore.materializeMany(sources, { destination, baseReceipt });
    const checkpointBase = await this.checkpointStore.checkpoint({ workspacePath: materialized.cwd, ownerId: `input:${taskId}:${attempt}` });
    const ownerBase = join(this.storageRoot, '.checkpoint-owners');
    await rejectLinks(ownerBase);
    await mkdir(ownerBase, { recursive: true, mode: 0o700 });
    const owner = { schemaVersion: 1, owner: `task:${taskId}:${attempt}`, taskId, attempt, sourceRoot: await realpath(this.sourceRoot), cwd: materialized.cwd, kind: 'checkpoint_directory', base: baseReceipt.id, sourceDirty: false, createdAt: new Date().toISOString() };
    await writeFile(join(ownerBase, basename(destination) + '.json'), JSON.stringify(owner), { flag: 'wx', mode: 0o600 });
    return { cwd: materialized.cwd, workspacePath: materialized.cwd, kind: 'checkpoint_directory', base: owner.base, sourceDirty: false, checkpointBase, fileBaseCheckpoint: seed };
  }

  async #ownedCheckpoint(task, ownerId) {
    if (!this.checkpointStore || !task?.workspacePath || !task.id || !Number.isInteger(task.attempts)) throw new Error('workspace_checkpoint_manager_required');
    if (resolve(task.workspacePath) !== join(this.checkpointStore.materialized, basename(task.workspacePath)) || !/^[a-f0-9]{24}$/.test(basename(task.workspacePath))) throw new Error('workspace_not_owned');
    const ownerFile = join(this.storageRoot, '.checkpoint-owners', basename(task.workspacePath) + '.json'); await rejectLinks(join(this.storageRoot, '.checkpoint-owners'));
    const info = await lstat(ownerFile);
    if (!info.isFile() || info.isSymbolicLink() || info.nlink !== 1 || info.size > 8192) throw new Error('workspace_owner_invalid');
    const parsed = JSON.parse(await readFile(ownerFile, 'utf8'));
    if (parsed.schemaVersion !== 1 || parsed.taskId !== task.id || parsed.attempt !== task.attempts || parsed.cwd !== resolve(task.workspacePath) || parsed.sourceRoot !== await realpath(this.sourceRoot)) throw new Error('workspace_owner_mismatch');
    return this.checkpointStore.checkpoint({ workspacePath: task.workspacePath, ownerId });
  }
  async sealTask(task) { return this.#ownedCheckpoint(task, `task:${task.id}`); }
  async repairTask(task) { return this.#ownedCheckpoint(task, `repair:${task.id}:${task.attempts}`); }
  async verifyCheckpoint(receipt, options = {}) { if (!this.checkpointStore) throw new Error('workspace_checkpoint_manager_required'); return this.checkpointStore.verify(receipt, options); }

  async readOwned(base, cwd, slug) {
    if (!within(this.storageRoot, cwd)) throw new Error('workspace_not_owned');
    await rejectLinks(base);
    const info = await lstat(join(base, 'owner.json')).catch(() => null);
    if (!info?.isFile() || info.isSymbolicLink() || info.nlink !== 1 || info.size > 4096) throw new Error('workspace_owner_invalid');
    let owner;
    try { owner = JSON.parse(await readFile(join(base, 'owner.json'), 'utf8')); } catch { throw new Error('workspace_owner_invalid'); }
    if (owner.schemaVersion !== 1 || owner.owner !== slug || owner.sourceRoot !== await realpath(this.sourceRoot) || resolve(owner.cwd || '') !== cwd || !['git_worktree', 'artifact_directory'].includes(owner.kind)) throw new Error('workspace_owner_invalid');
    const directory = await lstat(cwd).catch(() => null);
    if (!directory?.isDirectory() || directory.isSymbolicLink()) throw new Error('workspace_directory_invalid');
    return { cwd, workspacePath: cwd, kind: owner.kind, branch: owner.branch || null, base: owner.base, sourceDirty: owner.sourceDirty === true };
  }

  async git(args, { input, config = [], raw = false } = {}) {
    const hookFile = join(this.storageRoot, '.chronos-hooks-disabled');
    await rejectLinks(this.storageRoot);
    await mkdir(this.storageRoot, { recursive: true, mode: 0o700 });
    try { await writeFile(hookFile, '', { flag: 'wx', mode: 0o600 }); } catch (error) { if (error.code !== 'EEXIST') throw error; }
    const existing = await lstat(hookFile);
    if (!existing.isFile() || existing.isSymbolicLink() || existing.nlink !== 1) throw new Error('workspace_hook_guard_invalid');
    const safety = ['-c', `core.hooksPath=${hookFile}`, '-c', 'core.fsmonitor=false', '-c', 'submodule.recurse=false'];
    const result = await this.execute(this.gitExecutable, [...config, ...safety, '-C', this.sourceRoot, ...args], { windowsHide: true, timeout: 20000, maxBuffer: 1048576, ...(input != null ? { input } : {}), env: { ...process.env, GIT_TERMINAL_PROMPT: '0', GIT_OPTIONAL_LOCKS: '0', GIT_DIR: undefined, GIT_WORK_TREE: undefined, GIT_INDEX_FILE: undefined, GIT_COMMON_DIR: undefined } });
    const output = String(result.stdout || '');
    return raw ? output : output.trim();
  }

  async filterOverrides() {
    let output;
    try { output = await this.git(['config', '--null', '--name-only', '--get-regexp', '^filter\\..*\\.(smudge|process|clean|required)$'], { raw: true }); }
    catch (error) { if (error.code === 1) return []; throw new Error('workspace_git_filter_probe_failed'); }
    if (!output.endsWith('\0')) throw new Error('workspace_git_filter_probe_failed');
    const drivers = new Set();
    for (const key of output.slice(0, -1).split('\0')) {
      const match = /^filter\.(.{1,200})\.(?:smudge|process|clean|required)$/u.exec(key);
      if (!match || /[\x00-\x1f\x7f=]/.test(match[1])) throw new Error('workspace_git_filter_probe_failed');
      drivers.add(match[1]);
      if (drivers.size > 64) throw new Error('workspace_git_filter_probe_failed');
    }
    const config = [...drivers].flatMap((driver) => ['-c', `filter.${driver}.process=`, '-c', `filter.${driver}.smudge=`, '-c', `filter.${driver}.clean=`, '-c', `filter.${driver}.required=false`]);
    if (config.join(' ').length > 15000) throw new Error('workspace_git_filter_probe_failed');
    return config;
  }

  async checkCheckoutAttributes(commit, config) {
    let names, attributes;
    try {
      names = await this.git(['ls-tree', '-rz', '--name-only', commit], { config, raw: true });
      if (!names) return;
      if (!names.endsWith('\0') || names.slice(0, -1).split('\0').some((name) => !name)) throw new Error();
      attributes = await this.git(['check-attr', `--source=${commit}`, '-z', '--stdin', 'filter'], { config, input: names, raw: true });
    } catch { throw new Error('workspace_git_attribute_probe_failed'); }
    if (!attributes.endsWith('\0')) throw new Error('workspace_git_attribute_probe_failed');
    const fields = attributes.slice(0, -1).split('\0');
    const paths = names.slice(0, -1).split('\0');
    if (fields.length !== paths.length * 3) throw new Error('workspace_git_attribute_probe_failed');
    for (let i = 0; i < paths.length; i++) {
      if (fields[i * 3] !== paths[i] || fields[i * 3 + 1] !== 'filter') throw new Error('workspace_git_attribute_probe_failed');
      if (!['unspecified', 'unset'].includes(fields[i * 3 + 2])) throw new Error('workspace_checkout_filter_requires_review');
    }
  }

  async createOwned(base, cwd, slug) {
    await rejectLinks(this.storageRoot);
    await mkdir(this.storageRoot, { recursive: true, mode: 0o700 });
    const existing = await lstat(base).catch((error) => error.code === 'ENOENT' ? null : Promise.reject(error));
    if (existing) return this.readOwned(base, cwd, slug);
    const canonicalSource = await realpath(this.sourceRoot);
    let kind = 'artifact_directory', branch = null, baseCommit = 'empty artifact directory', sourceDirty = false;
    let repository;
    try { repository = await this.git(['rev-parse', '--show-toplevel']); }
    catch (error) {
      if (error.code === 'ENOENT') throw new Error('git_executable_not_found');
      if (!String(error.stderr || '').includes('not a git repository')) throw new Error('workspace_git_probe_failed');
    }
    let config = [];
    if (repository) {
      config = await this.filterOverrides();
      baseCommit = await this.git(['rev-parse', '--verify', 'HEAD']);
      if (!/^[a-f0-9]{40,64}$/.test(baseCommit)) throw new Error('workspace_base_invalid');
      await this.checkCheckoutAttributes(baseCommit, config);
      sourceDirty = !!(await this.git(['status', '--porcelain', '--untracked-files=no'], { config }));
    }
    await mkdir(base, { mode: 0o700 });
    if (repository) {
      branch = 'codex/chronos-' + slug + '-' + randomUUID().slice(0, 8);
      try { await this.git(['worktree', 'add', '-b', branch, '--', cwd, baseCommit], { config }); }
      catch { throw new Error('workspace_worktree_create_failed'); }
      kind = 'git_worktree';
    } else {
      await mkdir(cwd, { mode: 0o700 });
    }
    const owner = { schemaVersion: 1, owner: slug, sourceRoot: canonicalSource, cwd, kind, branch, base: baseCommit, sourceDirty, createdAt: new Date().toISOString() };
    await writeFile(join(base, 'owner.json'), JSON.stringify(owner), { flag: 'wx', mode: 0o600 });
    return this.readOwned(base, cwd, slug);
  }
}
