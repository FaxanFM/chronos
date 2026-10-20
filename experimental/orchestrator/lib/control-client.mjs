/** Small authenticated client for the private loopback Control Room API. */
export class ControlRoomClient {
  #token;
  #cookie = null;
  constructor({ origin, token, expectedInstanceId = null, expectedWorkspace = null, fetchImpl = globalThis.fetch } = {}) {
    let parsed;
    try { parsed = new URL(origin); } catch { throw new Error('control_room_origin_invalid'); }
    if (parsed.protocol !== 'http:' || parsed.hostname !== '127.0.0.1' || parsed.username || parsed.password || !Number.isInteger(Number(parsed.port)) || Number(parsed.port) < 1 || Number(parsed.port) > 65535 || parsed.pathname !== '/' || parsed.search || parsed.hash) throw new Error('control_room_origin_invalid');
    if (typeof token !== 'string' || !/^[a-f0-9]{64}$/.test(token)) throw new Error('control_room_token_invalid');
    if (expectedInstanceId !== null && (typeof expectedInstanceId !== 'string' || !/^[a-f0-9-]{8,128}$/.test(expectedInstanceId))) throw new Error('control_room_instance_invalid');
    if (expectedWorkspace !== null && (typeof expectedWorkspace !== 'string' || !expectedWorkspace.trim() || expectedWorkspace.length > 4096)) throw new Error('control_room_workspace_invalid');
    if (typeof fetchImpl !== 'function') throw new Error('control_room_fetch_required');
    this.origin = parsed.origin;
    this.#token = token;
    this.expectedInstanceId = expectedInstanceId;
    this.expectedWorkspace = expectedWorkspace;
    this.fetch = fetchImpl;
  }

  async request(path, options = {}) {
    if (typeof path !== 'string' || !/^\/api\/(?:[a-z0-9/_-]+)$/.test(path)) throw new Error('control_room_path_invalid');
    const method = String(options.method || 'GET').toUpperCase();
    const headers = { ...(options.headers || {}), Origin: this.origin };
    if (this.#token) headers['X-Chronos-Token'] = this.#token;
    if (this.#cookie) headers.Cookie = this.#cookie;
    const response = await this.fetch(this.origin + path, { ...options, method, headers, redirect: 'error', credentials: 'omit' });
    const setCookie = response.headers?.get?.('set-cookie');
    if (setCookie) { this.#cookie = setCookie.split(';')[0]; this.#token = null; }
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(/^[a-z][a-z0-9_]{1,95}$/.test(body.error || '') ? body.error : 'control_room_request_failed');
    return body;
  }

  capabilities() { return this.request('/api/capabilities'); }
  async state() {
    const body = await this.request('/api/state');
    this.#assertIdentity(body);
    return body;
  }
  #assertIdentity(body) {
    if (this.expectedInstanceId && body?.runtime?.instanceId !== this.expectedInstanceId) throw new Error('control_room_instance_mismatch');
    if (this.expectedWorkspace && body?.workspace?.sourceRoot !== this.expectedWorkspace) throw new Error('control_room_workspace_mismatch');
  }
  action(action) {
    if (!action || typeof action !== 'object' || Array.isArray(action) || typeof action.action !== 'string') throw new Error('control_room_action_invalid');
    return (async () => { if (this.expectedInstanceId || this.expectedWorkspace) await this.state(); return this.request('/api/actions', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(action) }); })();
  }
}
