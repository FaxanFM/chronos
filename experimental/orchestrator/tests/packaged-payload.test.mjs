import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { join, resolve, dirname, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = resolve(fileURLToPath(new URL('../../..', import.meta.url)));
const payloadRoot = join(repo, 'plugins/chronos/skills/chronos-control-room/scripts/runtime');

test('packaged runtime includes every relative import target', async () => {
  const record = JSON.parse(await readFile(join(payloadRoot, 'payload.json'), 'utf8'));
  const files = new Set(record.files.map((item) => item.path));
  assert.ok(files.has('lib/collaboration.mjs'), 'collaboration protocol must be packaged');
  assert.ok(files.has('lib/collaboration-state.mjs'), 'collaboration state must be packaged');
  assert.ok(files.has('lib/file-checkpoints.mjs'), 'file checkpoint store must be packaged');
  for (const relative of files) {
    if (!/\.(?:mjs|js)$/.test(relative)) continue;
    const source = await readFile(join(payloadRoot, relative), 'utf8');
    const imports = [...source.matchAll(/(?:from\s*|import\s*\()(['"])(\.\.?\/[^'"]+)\1/g)].map((match) => match[2]);
    for (const specifier of imports) {
      const candidate = specifier.replace(/\\/g, '/').replace(/^\.\//, '');
      const target = join(dirname(relative), candidate).replace(/\\/g, '/');
      const normalized = extname(target) ? target : `${target}.mjs`;
      assert.ok(files.has(normalized), `${relative} imports missing packaged module ${normalized}`);
    }
  }
});
