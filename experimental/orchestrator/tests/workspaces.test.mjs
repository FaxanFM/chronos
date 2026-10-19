import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createHash } from 'node:crypto';
import { WorkspaceManager, executeWorkspaceGit } from '../lib/workspaces.mjs';

const run = promisify(execFile);
test('write packets use an isolated committed worktree; reviewers reuse it', async () => {
  const root = await mkdtemp(join(tmpdir(), 'chronos-workspace-'));
  const source = join(root, 'source'); await mkdir(source);
  const git = (args) => run('git', ['-C', source, '-c', 'core.excludesFile=' + join(root, 'empty-ignore'), ...args], { windowsHide: true });
  await writeFile(join(root, 'empty-ignore'), '');
  try {
    await git(['init']); await git(['config', 'user.name', 'Chronos fixture']); await git(['config', 'user.email', 'fixture@example.invalid']);
    await writeFile(join(source, 'input.txt'), 'original'); await git(['add', 'input.txt']); await git(['-c', 'commit.gpgsign=false', 'commit', '-m', 'fixture']);
    await writeFile(join(source, 'input.txt'), 'uncommitted original');
    const manager = new WorkspaceManager({ sourceRoot: source, storageRoot: join(root, 'owned'), execute: (file, args, opts) => executeWorkspaceGit(file, ['-c', 'core.excludesFile=' + join(root, 'empty-ignore'), ...args], opts) });
    const [first, duplicate] = await Promise.all([manager.prepare({ packetId: 'one', policy: 'workspace-write' }), manager.prepare({ packetId: 'one', policy: 'workspace-write' })]);
    assert.equal(first.cwd, duplicate.cwd); assert.equal(first.kind, 'git_worktree'); assert.equal(first.sourceDirty, true);
    assert.equal(await readFile(join(first.cwd, 'input.txt'), 'utf8'), 'original');
    await writeFile(join(first.cwd, 'output.txt'), 'managed result');
    const review = await manager.prepare({ packetId: 'one', policy: 'read-only', workspacePath: first.workspacePath });
    assert.equal(review.cwd, first.cwd); assert.equal(await readFile(join(source, 'input.txt'), 'utf8'), 'uncommitted original');
    await assert.rejects(manager.prepare({ packetId: 'two', policy: 'read-only', workspacePath: first.workspacePath }), /workspace_not_owned/);
    await git(['worktree', 'remove', '--force', first.cwd]);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('non-Git writes use a separate artifact directory and do not copy source files', async () => {
  const root = await mkdtemp(join(tmpdir(), 'chronos-artifacts-')); const source = join(root, 'source'); await mkdir(source);
  try {
    await writeFile(join(source, 'private.txt'), 'not copied');
    const manager = new WorkspaceManager({ sourceRoot: source, storageRoot: join(root, 'owned') });
    const readonly = await manager.prepare({ taskId: 'read', policy: 'read-only' }); assert.equal(readonly.cwd, source);
    const write = await manager.prepare({ taskId: 'write', policy: 'workspace-write' }); assert.equal(write.kind, 'artifact_directory');
    await assert.rejects(readFile(join(write.cwd, 'private.txt')), /ENOENT/);
  } finally { await rm(root, { recursive: true, force: true }); }
});

const shellQuote = (value) => "'" + value.replace(/\\/g, '/').replace(/'/g, "'\\''") + "'";
async function helperFixture({ filtered = false } = {}) {
  const root = await mkdtemp(join(tmpdir(), 'chronos-git-helpers-'));
  const source = join(root, 'source'); await mkdir(source);
  const hooks = join(root, 'hooks'); await mkdir(hooks);
  const emptyIgnore = join(root, 'empty-ignore'); await writeFile(emptyIgnore, '');
  const git = (args) => run('git', ['-C', source, '-c', `core.excludesFile=${emptyIgnore}`, '-c', 'core.fsmonitor=false', '-c', 'core.hooksPath=/dev/null', '-c', 'filter.fixture.clean=', '-c', 'filter.fixture.smudge=', '-c', 'filter.fixture.process=', '-c', 'filter.fixture.required=false', ...args], { windowsHide: true });
  await git(['init']); await git(['config', 'user.name', 'Chronos fixture']); await git(['config', 'user.email', 'fixture@example.invalid']);
  await git(['config', 'core.excludesFile', emptyIgnore]);
  await writeFile(join(source, 'input.txt'), 'original');
  if (filtered) await writeFile(join(source, '.gitattributes'), '*.txt filter=fixture\n');
  await git(['add', '.']); await git(['-c', 'commit.gpgsign=false', 'commit', '-m', 'fixture']);
  const program = join(root, 'mark.mjs');
  await writeFile(program, "import { writeFileSync } from 'node:fs'; writeFileSync(process.argv[2], 'called'); process.stdin.pipe(process.stdout);\n");
  const command = (kind) => `${shellQuote(process.execPath)} ${shellQuote(program)} ${shellQuote(join(root, kind + '.marker'))}`;
  await writeFile(join(hooks, 'post-checkout'), '#!/bin/sh\n' + command('checkout') + '\n', { mode: 0o700 });
  await git(['config', 'core.hooksPath', hooks]);
  await git(['config', 'core.fsmonitor', command('fsmonitor')]);
  await git(['config', 'filter.fixture.clean', command('clean')]);
  await git(['config', 'filter.fixture.smudge', command('smudge')]);
  const manager = new WorkspaceManager({ sourceRoot: source, storageRoot: join(root, 'owned') });
  const noMarkers = async () => {
    for (const kind of ['checkout', 'fsmonitor', 'clean', 'smudge', 'process']) await assert.rejects(readFile(join(root, kind + '.marker')), /ENOENT/);
  };
  return { root, source, git, manager, noMarkers, command };
}

test('native worktree setup suppresses Git hooks, fsmonitor and uncommitted clean filters', async () => {
  const fixture = await helperFixture();
  const { root, source, git, manager } = fixture;
  try {
    await writeFile(join(source, '.gitattributes'), '*.txt filter=fixture\n');
    await writeFile(join(source, 'input.txt'), 'uncommitted');
    // A configured but unused driver must not prevent ordinary repository work.
    await git(['config', 'filter.unused.process', fixture.command('process')]);
    const prior = process.env.GIT_DIR;
    process.env.GIT_DIR = join(root, 'unrelated-git-directory');
    let prepared;
    try { prepared = await manager.prepare({ packetId: 'safe', policy: 'workspace-write' }); }
    finally { if (prior == null) delete process.env.GIT_DIR; else process.env.GIT_DIR = prior; }
    assert.equal(prepared.kind, 'git_worktree'); assert.equal(prepared.sourceDirty, true);
    assert.equal(await readFile(join(prepared.cwd, 'input.txt'), 'utf8'), 'original');
    assert.equal(await readFile(join(source, 'input.txt'), 'utf8'), 'uncommitted');
    await fixture.noMarkers();
    await git(['config', 'filter.fixture.process', fixture.command('process')]);
    const processFilter = await manager.prepare({ packetId: 'safe-process-filter', policy: 'workspace-write' });
    assert.equal(await readFile(join(processFilter.cwd, 'input.txt'), 'utf8'), 'original');
    await fixture.noMarkers();
    await git(['worktree', 'remove', '--force', processFilter.cwd]);
    await git(['worktree', 'remove', '--force', prepared.cwd]);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('committed checkout filters require review before state creation and can retry after repair', async () => {
  const fixture = await helperFixture({ filtered: true });
  const { root, source, git, manager } = fixture;
  try {
    await git(['config', 'filter.fixture.process', fixture.command('process')]);
    await assert.rejects(manager.prepare({ packetId: 'filtered', policy: 'workspace-write' }), /workspace_checkout_filter_requires_review/);
    const slug = createHash('sha256').update('filtered').digest('hex').slice(0, 24);
    await assert.rejects(readFile(join(root, 'owned', slug, 'owner.json')), /ENOENT/);
    await fixture.noMarkers();
    await writeFile(join(source, '.gitattributes'), '*.txt -filter\n');
    await git(['add', '.gitattributes']); await git(['-c', 'commit.gpgsign=false', 'commit', '-m', 'reviewed filter removal']);
    const prepared = await manager.prepare({ packetId: 'filtered', policy: 'workspace-write' });
    assert.equal(await readFile(join(prepared.cwd, 'input.txt'), 'utf8'), 'original');
    await fixture.noMarkers();
    await git(['worktree', 'remove', '--force', prepared.cwd]);
  } finally { await rm(root, { recursive: true, force: true }); }
});
