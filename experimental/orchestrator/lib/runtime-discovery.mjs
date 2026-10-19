import { access, readdir, realpath, stat } from 'node:fs/promises';
import { constants } from 'node:fs';
import { homedir } from 'node:os';
import { delimiter, dirname, isAbsolute, join, resolve } from 'node:path';
import { createHash } from 'node:crypto';

export const pathIdentity = (value) => process.platform === 'win32' ? resolve(value).toLowerCase() : resolve(value);
export async function discoverCodex({ explicit, env = process.env } = {}) {
  const candidates = [];
  if (explicit) {
    if (!isAbsolute(explicit)) throw new Error('codex_path_must_be_absolute');
    candidates.push(explicit);
  } else {
    if (env.CODEX_CLI_PATH) candidates.push(env.CODEX_CLI_PATH);
    for (const directory of String(env.PATH || env.Path || '').split(delimiter).filter(Boolean)) {
      candidates.push(join(directory, process.platform === 'win32' ? 'codex.exe' : 'codex'));
      candidates.push(join(directory, 'node_modules/@openai/codex/bin/codex.js'));
      candidates.push(join(directory, '../lib/node_modules/@openai/codex/bin/codex.js'));
    }
    if (process.platform === 'darwin') candidates.push('/Applications/Codex.app/Contents/Resources/codex', '/Applications/Codex.app/Contents/Resources/bin/codex');
    if (process.platform === 'win32' && env.LOCALAPPDATA) {
      const bin = join(env.LOCALAPPDATA, 'OpenAI/Codex/bin');
      const versions = (await readdir(bin, { withFileTypes: true }).catch(() => [])).filter((entry) => entry.isDirectory()).slice(0, 64);
      for (const entry of versions.reverse()) candidates.push(join(bin, entry.name, 'codex.exe'));
    }
  }
  for (const candidate of [...new Set(candidates)]) {
    if (!isAbsolute(candidate) || /\.(cmd|bat)$/i.test(candidate)) continue;
    try {
      const path = await realpath(candidate);
      if (!(await stat(path)).isFile()) continue;
      await access(path, /\.(m?js|cjs)$/i.test(path) || process.platform === 'win32' ? constants.R_OK : constants.X_OK);
      return path;
    } catch { /* Try only the next explicit discovery candidate. */ }
  }
  throw new Error(explicit ? 'codex_path_not_found' : 'control_room_codex_runtime_missing');
}

export function defaultStateDir(workspace, { codexHome = process.env.CODEX_HOME, home = homedir() } = {}) {
  const identity = createHash('sha256').update(pathIdentity(workspace)).digest('hex').slice(0, 24);
  return join(resolve(codexHome || join(home, '.codex')), 'chronos/control-room', identity);
}
