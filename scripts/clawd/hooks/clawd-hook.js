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
// control characters and bidi overrides (would reorder the text on screen)
const clean = (value, max = 24) => text(typeof value === 'string' ? value.replace(/[\u0000-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, '').trim() : undefined, max);
const obj = (value) => (value && typeof value === 'object' ? value : {});

// First word of a command line, as a basename: never its arguments, nor leading VAR=value assignments (may hold secrets,
// quoted values with spaces included). Only a plain program name passes: "$(cat key)", "`x`"... give nothing.
function program(command) {
  let word = Array.isArray(command) ? command[0] : undefined;
  if (typeof command === 'string') {
    const words = command.match(/(?:[^\s'"\\]+|\\.|'[^']*'?|"(?:\\.|[^"\\])*"?)+/g) || [];
    word = words.find((w) => !/^[A-Za-z_][A-Za-z0-9_]*=/.test(w));
    if (word) word = word.replace(/'([^']*)'?|"((?:\\.|[^"\\])*)"?/g, '$1$2');
  }
  if (typeof word !== 'string') return undefined;
  const name = path.basename(word);
  return /^[\w.+@:-]+$/.test(name) ? clean(name) : undefined;
}

const done = (list, key) => (Array.isArray(list) ? `${list.filter((t) => obj(t)[key] === 'completed').length}/${list.length}` : undefined);

// Short action target shown above Clawd's head: a file name, a program name, a pattern... never full commands or paths.
function target(tool, input) {
  input = obj(input);
  switch (tool) {
    case 'Read': case 'Edit': case 'Write': case 'MultiEdit': case 'NotebookEdit': case 'NotebookRead': {
      const file = input.file_path || input.notebook_path;
      return typeof file === 'string' ? clean(path.basename(file)) : undefined;
    }
    case 'Bash': return program(input.command);
    case 'exec_command': case 'shell': case 'local_shell': return program(input.cmd || input.command);
    case 'Grep': case 'Glob': return clean(input.pattern);
    case 'WebFetch': try { return clean(new URL(input.url).hostname); } catch { return undefined; }
    case 'WebSearch': case 'web_search': return clean(input.query);
    case 'Task': case 'Agent': return clean(input.description);
    case 'TodoWrite': return done(input.todos, 'status');
    case 'update_plan': return done(input.plan, 'status');
    default: return undefined;
  }
}

// Our ancestors (agent, shell, terminal...): Clawd focuses the first one that owns a Hyprland window.
function ancestors(pid) {
  const fs = require('node:fs');
  const pids = [];
  while (pid > 1 && pids.length < 16) {
    pids.push(pid);
    try {
      const stat = fs.readFileSync(`/proc/${pid}/stat`, 'utf8');
      pid = Number(stat.slice(stat.lastIndexOf(')') + 2).split(' ')[1]);  // comm may hold spaces and ')'
    } catch { break; }
  }
  return pids;
}

// Only what Clawd shows: never prompts, replies, full commands or paths (just the short target above).
function slim(evt) {
  let event = evt.hook_event_name;
  let type = evt.notification_type;
  if (event === 'PermissionRequest') { event = 'Notification'; type = 'permission_prompt'; }
  if (event === 'PreToolUse' && evt.tool_name === 'request_user_input') { event = 'Notification'; type = 'agent_needs_input'; }
  return {
    agent: AGENT, event, session_id: text(evt.session_id, 80), tool_name: text(evt.tool_name, 40),
    notification_type: text(type, 40), dir: text(typeof evt.cwd === 'string' ? path.basename(evt.cwd) : '', 40),
    target: event === 'PreToolUse' ? target(evt.tool_name, evt.tool_input) : undefined, model: clean(evt.model, 40),
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
    socket.end(JSON.stringify({ ...slim(evt), pids: ancestors(process.ppid) }) + '\n');
  });
}

module.exports = { slim, ancestors, text, clean, SOCKET };
if (require.main === module) run();
