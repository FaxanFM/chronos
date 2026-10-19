import { build } from 'esbuild';
import { mkdir, copyFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = dirname(fileURLToPath(import.meta.url));
await mkdir(resolve(root, 'public'), { recursive: true });
await build({ absWorkingDir: root, entryPoints: ['./frontend/main.jsx'], bundle: true, minify: true, legalComments: 'eof', format: 'iife', platform: 'browser', outfile: './public/app.js' });
await copyFile(resolve(root, 'frontend/styles.css'), resolve(root, 'public/styles.css'));
