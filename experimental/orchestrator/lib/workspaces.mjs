import { createHash, randomUUID } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, lstat, readFile, writeFile, realpath } from 'node:fs/promises';
import { resolve, join, relative, isAbsolute, parse } from 'node:path';

const run = promisify(execFile);
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
  constructor({ sourceRoot, storageRoot, gitExecutable = 'git', execute = run } = {}) {
    this.sourceRoot = resolve(sourceRoot);
    this.storageRoot = resolve(storageRoot);
    this.gitExecutable = gitExecutable;
    this.execute = execute;
    this.inflight = new Map();
  }

  async prepare({ packetId, taskId, policy = 'read-only', workspacePath } = {}) {
    if (!['read-only', 'workspace-write'].includes(policy)) throw new Error('workspace_policy_invalid');
    const key = String(packetId || taskId || '');
    if (!key || key.length > 200) throw new Error('workspace_owner_required');
    const slug = createHash('sha256').update(key).digest('hex').slice(0, 24);
    const base = join(this.storageRoot, slug);
    const cwd = join(base, 'work');
    if (workspacePath && resolve(workspacePath) !== cwd) throw new Error('workspace_not_owned');
    if (workspacePath) return this.readOwned(base, cwd, slug);
    if (policy === 'read-only') return { cwd: this.sourceRoot, workspacePath: null, kind: 'source_read_only', base: 'selected workspace' };
    if (this.inflight.has(slug)) return this.inflight.get(slug);
    const pending = this.createOwned(base, cwd, slug).finally(() => this.inflight.delete(slug));
    this.inflight.set(slug, pending);
    return pending;
  }

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

  async git(args) {
    const result = await this.execute(this.gitExecutable, ['-C', this.sourceRoot, ...args], { windowsHide: true, timeout: 20000, maxBuffer: 1048576, env: { ...process.env, GIT_TERMINAL_PROMPT: '0' } });
    return String(result.stdout || '').trim();
  }

  async createOwned(base, cwd, slug) {
    await rejectLinks(this.storageRoot);
    await mkdir(this.storageRoot, { recursive: true, mode: 0o700 });
    const existing = await lstat(base).catch((error) => error.code === 'ENOENT' ? null : Promise.reject(error));
    if (existing) return this.readOwned(base, cwd, slug);
    await mkdir(base, { mode: 0o700 });
    const canonicalSource = await realpath(this.sourceRoot);
    let kind = 'artifact_directory', branch = null, baseCommit = 'empty artifact directory', sourceDirty = false;
    let repository;
    try { repository = await this.git(['rev-parse', '--show-toplevel']); }
    catch (error) {
      if (error.code === 'ENOENT') throw new Error('git_executable_not_found');
      if (!String(error.stderr || '').includes('not a git repository')) throw new Error('workspace_git_probe_failed');
    }
    if (repository) {
      baseCommit = await this.git(['rev-parse', '--verify', 'HEAD']);
      if (!/^[a-f0-9]{40,64}$/.test(baseCommit)) throw new Error('workspace_base_invalid');
      sourceDirty = !!(await this.git(['status', '--porcelain', '--untracked-files=no']));
      branch = 'codex/chronos-' + slug + '-' + randomUUID().slice(0, 8);
      try { await this.git(['worktree', 'add', '-b', branch, '--', cwd, baseCommit]); }
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
