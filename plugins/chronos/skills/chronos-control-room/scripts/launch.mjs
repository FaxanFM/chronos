import { runLauncherCli } from './runtime/launcher.mjs';

try { await runLauncherCli(process.argv.slice(2), { requirePayload: true }); }
catch (error) {
  console.error(JSON.stringify({ ok: false, error: /^[a-z0-9_]+$/.test(error.message) ? error.message : 'control_room_launch_failed' }));
  process.exitCode = 1;
}
