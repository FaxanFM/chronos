import test from 'node:test';
import assert from 'node:assert/strict';
import { ControlRoomClient } from '../lib/control-client.mjs';

const token = 'a'.repeat(64);
const response = (body, ok = true, headers = {}) => ({ ok, headers: { get: (name) => headers[name.toLowerCase()] || null }, json: async () => body });

test('control client is loopback-only and rejects malformed identity or paths', async () => {
  assert.throws(() => new ControlRoomClient({ origin: 'http://localhost:1234', token }), /origin_invalid/);
  assert.throws(() => new ControlRoomClient({ origin: 'https://127.0.0.1:1234', token }), /origin_invalid/);
  for (const origin of ['http://user:secret@127.0.0.1:1234', 'http://127.0.0.1:0', 'http://127.0.0.1:65536', 'http://127.0.0.1:1234/path', 'http://127.0.0.1:1234/?token=secret']) {
    assert.throws(() => new ControlRoomClient({ origin, token }), /origin_invalid/);
  }
  assert.throws(() => new ControlRoomClient({ origin: 'http://127.0.0.1:1234', token: 'bad' }), /token_invalid/);
  const client = new ControlRoomClient({ origin: 'http://127.0.0.1:1234', token, fetchImpl: async () => response({}) });
  await assert.rejects(client.request('/not-api'), /path_invalid/);
  assert.throws(() => client.action({}), /action_invalid/);
});

test('client pins origin, refuses redirects, does not send ambient credentials, and never exposes token in errors', async () => {
  let call;
  const client = new ControlRoomClient({ origin: 'http://127.0.0.1:1234', token, fetchImpl: async (url, options) => {
    call = { url, options };
    return response({ ok: true }, true, { 'set-cookie': 'chronos_session_1234=bbbb; HttpOnly; SameSite=Strict' });
  } });
  await client.capabilities();
  assert.equal(call.url, 'http://127.0.0.1:1234/api/capabilities');
  assert.equal(call.options.headers.Origin, 'http://127.0.0.1:1234');
  assert.equal(call.options.redirect, 'error');
  assert.equal(call.options.credentials, 'omit');
  assert.equal(call.options.headers['X-Chronos-Token'], token);
  await client.action({ action: 'pause' });
  assert.equal(call.options.headers.Origin, 'http://127.0.0.1:1234');
  assert.equal(call.options.headers.Cookie, 'chronos_session_1234=bbbb');
  assert.equal(call.options.headers['X-Chronos-Token'], undefined);
  const rejecting = new ControlRoomClient({ origin: 'http://127.0.0.1:1234', token, fetchImpl: async () => response({ error: 'auth_failed' }, false) });
  await assert.rejects(rejecting.state(), (error) => error.message === 'auth_failed' && !error.message.includes(token));
  const hostile = new ControlRoomClient({ origin: 'http://127.0.0.1:1234', token, fetchImpl: async () => response({ error: `bad token ${token}` }, false) });
  await assert.rejects(hostile.state(), { message: 'control_room_request_failed' });
  assert.ok(!JSON.stringify(client).includes(token));
});
