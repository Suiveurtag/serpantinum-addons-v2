#!/usr/bin/env node
'use strict';

// Claude Code / Codex hook -> Clawd: one JSON line into the shell's clawd.sock.
// Observe only: no output, always exit 0, give up fast; silent when the shell (or Clawd) is not running.
// Usage: node clawd-hook.js [--agent codex]   (the hook event arrives on stdin)

const net = require('node:net');
const path = require('node:path');

const AGENT = process.argv.slice(2).join(' ') === '--agent codex' ? 'codex' : 'claude';
const SOCKET = path.join(process.env.XDG_RUNTIME_DIR || `/run/user/${process.getuid()}`, 'serpantinum', 'clawd.sock');

const text = (value, max) => (typeof value === 'string' && value ? value.slice(0, max) : undefined);

// Only what Clawd shows: never prompts, tool inputs or replies.
function slim(evt) {
  let event = evt.hook_event_name;
  let type = evt.notification_type;
  if (event === 'PermissionRequest') { event = 'Notification'; type = 'permission_prompt'; }
  if (event === 'PreToolUse' && evt.tool_name === 'request_user_input') { event = 'Notification'; type = 'agent_needs_input'; }
  return {
    agent: AGENT, event, session_id: text(evt.session_id, 80), tool_name: text(evt.tool_name, 40),
    notification_type: text(type, 40), dir: text(typeof evt.cwd === 'string' ? path.basename(evt.cwd) : '', 40),
  };
}

function run() {
  const bail = () => process.exit(0);
  setTimeout(bail, 500).unref();
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (chunk) => { raw += chunk; if (raw.length > 8 * 1024 * 1024) bail(); });
  process.stdin.on('error', bail);
  process.stdin.on('end', () => {
    let evt;
    try { evt = JSON.parse(raw); } catch { return bail(); }
    if (!evt || typeof evt.hook_event_name !== 'string') return bail();
    const socket = net.createConnection(SOCKET);
    socket.on('error', bail);
    socket.on('close', bail);
    socket.end(JSON.stringify(slim(evt)) + '\n');
  });
}

module.exports = { slim };
if (require.main === module) run();
