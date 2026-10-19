import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { WorkspaceManager } from '../lib/workspaces.mjs';

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
    const manager = new WorkspaceManager({ sourceRoot: source, storageRoot: join(root, 'owned'), execute: (file, args, opts) => run(file, ['-c', 'core.excludesFile=' + join(root, 'empty-ignore'), ...args], opts) });
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
