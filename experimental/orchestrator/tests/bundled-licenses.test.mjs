import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

test('browser bundle carries complete bundled dependency notices', async () => {
  const paths = [
    resolve(root, 'public/app.js'),
    resolve(root, '../../plugins/chronos/skills/chronos-control-room/scripts/runtime/public/app.js'),
  ];
  for (const path of paths) {
    const text = await readFile(path, 'utf8');
    const footerStart = text.indexOf('// Chronos Control Room bundled dependency licenses');
    assert.ok(footerStart >= 0, `missing bundled license footer: ${path}`);
    const footer = text.slice(footerStart).replace(/^\/\/ ?/gm, '').replace(/\s+/g, ' ');
    for (const header of [
      '@xyflow/react@12.8.6',
      'lucide-react@0.468.0',
      'react@19.1.1',
      'react-dom@19.1.1',
      'd3-selection@3.0.0',
    ]) assert.ok(footer.includes(header), `missing bundled package header: ${header}`);
    assert.ok(footer.includes('Permission is hereby granted, free of charge, to any person obtaining a copy'));
    assert.ok(footer.includes('Permission to use, copy, modify, and/or distribute this software for any purpose'));
    assert.ok(footer.includes('Redistribution and use in source and binary forms'));
    assert.ok(footer.includes('THE SOFTWARE IS PROVIDED "AS IS"'));
    assert.ok(footer.includes('Copyright (c) Meta Platforms, Inc.'));
  }
});
