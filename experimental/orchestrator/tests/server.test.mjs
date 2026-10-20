import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import http from 'node:http';
import { Orchestrator } from '../lib/engine.mjs';
import { createControlRoom } from '../server.mjs';
import { ControlRoomClient } from '../lib/control-client.mjs';

test('loopback control API requires session token, same origin and bounded JSON', async () => {
  const adapter = new EventEmitter(); adapter.close = async () => {};
  const room = await createControlRoom({ engine: new Orchestrator({ adapter }) });
  const call = (path, options) => fetch(room.origin + path, options);
  const headers = { 'X-Chronos-Token': room.token, 'Origin': room.origin, 'Content-Type': 'application/json' };
  try {
    assert.equal((await call('/api/state')).status, 401);
    const authorized = await call('/api/state', { headers });
    assert.equal(authorized.status, 200);
    const capabilities = await call('/api/capabilities', { headers });
    assert.equal(capabilities.status, 200);
    assert.equal((await capabilities.json()).protocol, 'chronos.control-room.v1');
    const sessionCookie = authorized.headers.get('set-cookie');
    assert.match(sessionCookie, /HttpOnly; SameSite=Strict; Path=\/api\//);
    assert.doesNotMatch(sessionCookie, new RegExp(room.token));
    const cookieHeaders = { Cookie: sessionCookie.split(';')[0], Origin: room.origin, 'Content-Type': 'application/json' };
    assert.equal((await call('/api/state', { headers: cookieHeaders })).status, 200);
    assert.equal((await call('/api/actions', { method: 'POST', headers: { ...cookieHeaders, Origin: 'https://evil.example' }, body: '{}' })).status, 403);
    assert.equal((await call('/api/actions', { method: 'POST', headers: { Cookie: cookieHeaders.Cookie, 'Content-Type': 'application/json' }, body: '{}' })).status, 403);
    assert.equal((await call('/api/state', { headers: { ...headers, Origin: 'https://evil.example' } })).status, 403);
    assert.equal((await call('/api/actions', { method: 'POST', headers: { 'X-Chronos-Token': room.token, 'Content-Type': 'application/json' }, body: '{}' })).status, 403);
    assert.equal((await call('/api/actions', { method: 'POST', headers, body: '{' })).status, 400);
    assert.equal((await call('/api/actions', { method: 'POST', headers, body: JSON.stringify({ action: 'add-task', title: 'A', instruction: 'Read', dependencies: [] }) })).status, 200);
    assert.equal((await call('/api/actions', { method: 'POST', headers, body: ' '.repeat(2097153) })).status, 413);
    const index = await call('/'); assert.match(index.headers.get('content-security-policy'), /frame-ancestors 'none'/);
    assert.doesNotMatch(await index.text(), new RegExp(room.token));
    assert.equal((await call('/assets/chronos-mark.png')).status, 200);
    assert.equal((await call('/server.mjs')).status, 404);
    const rebindingStatus = await new Promise((accept, reject) => {
      const req = http.get(room.origin + '/api/state', { headers: { ...headers, Host: 'evil.example' } }, (res) => { res.resume(); accept(res.statusCode); });
      req.on('error', reject);
    });
    assert.equal(rebindingStatus, 403);
  } finally { await room.close(); }
});

test('authenticated shutdown closes only this room and is idempotent', async () => {
  let stopped = 0;
  const adapter = new EventEmitter(); adapter.close = async () => { stopped += 1; };
  const room = await createControlRoom({ engine: new Orchestrator({ adapter }) });
  const headers = { 'X-Chronos-Token': room.token, Origin: room.origin, 'Content-Type': 'application/json' };
  assert.equal((await fetch(room.origin + '/api/actions', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{"action":"shutdown"}' })).status, 401);
  const response = await fetch(room.origin + '/api/actions', { method: 'POST', headers, body: '{"action":"shutdown"}' });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { stopped: true });
  await new Promise((done) => setImmediate(done));
  await room.close();
  await room.close();
  assert.equal(stopped, 1);
  assert.equal(room.server.listening, false);
});

test('control client completes authenticated state read and guarded rename against a real room', async () => {
  const adapter = new EventEmitter(); adapter.close = async () => {};
  const engine = await new Orchestrator({ adapter }).initialize();
  const room = await createControlRoom({ engine, instanceId: '11111111-1111-4111-8111-111111111111', workspaceInfo: { sourceRoot: 'C:\\workspace', base: 'committed_HEAD', uncommittedChangesCopied: false } });
  const client = new ControlRoomClient({ origin: room.origin, token: room.token, expectedInstanceId: '11111111-1111-4111-8111-111111111111', expectedWorkspace: 'C:\\workspace' });
  try {
    assert.equal((await client.capabilities()).protocol, 'chronos.control-room.v1');
    await client.action({ action: 'rename-workflow', workflowId: 'software_factory-default', name: 'Local pipeline' });
    assert.equal((await client.state()).workflows.find((item) => item.id === 'software_factory-default').name, 'Local pipeline');
    const wrongInstance = new ControlRoomClient({ origin: room.origin, token: room.token, expectedInstanceId: '22222222-2222-4222-8222-222222222222' });
    await assert.rejects(wrongInstance.action({ action: 'rename-workflow', workflowId: 'software_factory-default', name: 'Wrong room' }), /control_room_instance_mismatch/);
    const wrongWorkspace = new ControlRoomClient({ origin: room.origin, token: room.token, expectedWorkspace: 'C:\\other' });
    await assert.rejects(wrongWorkspace.action({ action: 'rename-workflow', workflowId: 'software_factory-default', name: 'Wrong workspace' }), /control_room_workspace_mismatch/);
    const after = await client.state();
    assert.equal(after.workflows.find((item) => item.id === 'software_factory-default').name, 'Local pipeline');
    assert.equal(after.consent.execution, false);
    assert.equal(after.consent.writes, false);
    assert.equal(after.mode, 'paused');
  } finally { await room.close(); }
});
