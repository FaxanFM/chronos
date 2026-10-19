import { build } from 'esbuild';
import { mkdir, copyFile, readFile, readdir, writeFile } from 'node:fs/promises';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = dirname(fileURLToPath(import.meta.url));
await mkdir(resolve(root, 'public'), { recursive: true });
const result = await build({ absWorkingDir: root, entryPoints: ['./frontend/main.jsx'], tsconfigRaw: { compilerOptions: { alwaysStrict: true } }, bundle: true, minify: true, legalComments: 'eof', metafile: true, write: false, outfile: './public/app.js', format: 'iife', platform: 'browser' });

function packageRootForInput(input) {
  const normalized = input.replaceAll('\\', '/');
  const marker = 'node_modules/';
  const index = normalized.lastIndexOf(marker);
  if (index < 0) return null;
  const tail = normalized.slice(index + marker.length).split('/');
  if (!tail[0] || tail[0].startsWith('.')) return null;
  const packageSegments = tail[0].startsWith('@') ? tail.slice(0, 2) : tail.slice(0, 1);
  return resolve(root, normalized.slice(0, index), 'node_modules', ...packageSegments);
}

async function findLicense(packageRoot) {
  const entries = await readdir(packageRoot, { withFileTypes: true });
  const licenses = entries.filter((entry) => entry.isFile() && /^(license|licence|copying)(?:\.|$)/i.test(entry.name)).sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
  if (!licenses.length) return null;
  return join(packageRoot, licenses[0].name);
}

async function bundledLicenseNotices(meta) {
  const packages = new Map();
  for (const input of Object.keys(meta.inputs).sort()) {
    const packageRoot = packageRootForInput(input);
    if (!packageRoot) continue;
    const metadata = JSON.parse(await readFile(join(packageRoot, 'package.json'), 'utf8'));
    const packageName = metadata.name;
    const packageKey = `${packageName}@${metadata.version}`;
    if (packages.has(packageKey)) continue;
    const licensePath = await findLicense(packageRoot);
    if (!licensePath) throw new Error(`Bundled dependency has no license file: ${packageName}`);
    const licenseText = (await readFile(licensePath, 'utf8')).replaceAll('\r\n', '\n').replaceAll('\r', '\n').trimEnd();
    packages.set(packageKey, { name: packageName, version: metadata.version, licenseText });
  }
  return [...packages.values()].sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : a.version < b.version ? -1 : a.version > b.version ? 1 : 0);
}

const notices = await bundledLicenseNotices(result.metafile);
const licenseFooter = [
  '',
  '// Chronos Control Room bundled dependency licenses',
  ...notices.flatMap(({ name, version, licenseText }) => [
    `// ----- ${name}@${version} -----`,
    ...licenseText.split('\n').map((line) => `// ${line}`.trimEnd()),
  ]),
  '',
].join('\n');
const bundle = result.outputFiles.find((file) => file.path.endsWith('.js'));
if (!bundle) throw new Error('esbuild produced no browser bundle.');
for (const file of result.outputFiles) {
  await writeFile(file.path, file === bundle ? `${file.text}${licenseFooter}` : file.contents);
}
await copyFile(resolve(root, 'frontend/styles.css'), resolve(root, 'public/styles.css'));
await copyFile(resolve(root, '../../plugins/chronos/assets/chronos-mark.png'), resolve(root, 'public/chronos-mark.png'));
