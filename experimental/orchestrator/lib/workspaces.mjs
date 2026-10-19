import { createHash, randomUUID } from 'node:crypto';
import { execFile } from 'node:child_process';
import { mkdir, lstat, readFile, writeFile, realpath } from 'node:fs/promises';
import { resolve, join, relative, isAbsolute, parse } from 'node:path';

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
  constructor({ sourceRoot, storageRoot, gitExecutable = 'git', execute = executeWorkspaceGit } = {}) {
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
