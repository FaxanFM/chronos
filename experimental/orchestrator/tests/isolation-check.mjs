import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { CodexAdapter } from '../lib/codex-adapter.mjs';

export async function checkIsolation({ codexPath, cwd } = {}) {
  let modelRequests = 0;
  const evidence = { isolationResponses: 0, serverCount: 0, cursorPages: 0, configMcpEntries: 0, configLayerMcpEntries: 0, toolCount: 0, disabledServers: 0 };
  const spawnWithoutModelTurns = (...args) => {
    const child = spawn(...args);
    const write = child.stdin.write.bind(child.stdin);
    const inventoryIds = new Set();
    let buffer = '';
    child.stdout.on('data', (chunk) => {
      buffer += chunk.toString('utf8'); let end;
      while ((end = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, end); buffer = buffer.slice(end + 1);
        try {
          const message = JSON.parse(line);
          if (inventoryIds.has(message.id) && message.result) {
            evidence.isolationResponses += 1;
            evidence.serverCount += Array.isArray(message.result.data) ? message.result.data.length : -1;
            for (const server of message.result.data || []) {
              evidence.toolCount += Object.keys(server.tools || {}).length;
              if (server.runtimeStatus === 'disabled') evidence.disabledServers += 1;
            }
            if (message.result.nextCursor != null) evidence.cursorPages += 1;
          }
          if (message.id === 'probe-config') {
            evidence.configMcpEntries = Object.keys(message.result?.config?.mcp_servers || {}).length;
            evidence.configLayerMcpEntries = (message.result?.layers || []).reduce((count, layer) => count + Object.keys(layer.config?.mcp_servers || {}).length, 0);
          }
        } catch {}
      }
    });
    child.stdin.write = (chunk, ...rest) => {
      const message = JSON.parse(String(chunk));
      if (message.method === 'mcpServerStatus/list') inventoryIds.add(message.id);
      if (message.method === 'thread/start') write(JSON.stringify({ jsonrpc: '2.0', id: 'probe-config', method: 'config/read', params: { includeLayers: true, cwd: resolve(cwd) } }) + '\n');
      if (message.method === 'turn/start') {
        modelRequests += 1;
        throw new Error('probe_model_turn_blocked');
      }
      return write(chunk, ...rest);
    };
    return child;
  };
  const adapter = new CodexAdapter({ codexPath, cwd: resolve(cwd), spawnProc: spawnWithoutModelTurns });
  adapter.on('error', () => {});
  try {
    await adapter.connect();
    try { await assert.rejects(adapter.startTask({ id: 'isolation-probe', instruction: 'This must never be sent to a model.' }), /probe_model_turn_blocked/); }
    catch (error) { console.log('Isolation evidence:', JSON.stringify(evidence)); throw error; }
    assert.equal(modelRequests, 1, 'The probe must reach the pre-turn isolation checks.');
    assert.ok(evidence.isolationResponses > 0); assert.equal(evidence.toolCount, 0); assert.equal(evidence.disabledServers, evidence.serverCount);
    return { result: 'PASS', modelTurnsSent: 0, isolationCheckedBeforeTurn: true, disabledMetadataRecords: evidence.disabledServers, availableExternalTools: evidence.toolCount };
  } finally { await adapter.close(); }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const args = process.argv.slice(2);
  const get = (name) => args.includes(name) ? args[args.indexOf(name) + 1] : undefined;
  console.log(JSON.stringify(await checkIsolation({ codexPath: get('--codex'), cwd: get('--cwd') || process.cwd() })));
}
