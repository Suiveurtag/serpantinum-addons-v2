#!/usr/bin/env node
'use strict';

// node hooks.js <status|install|uninstall> <claude|codex>  ->  {"ok":true,"data":{...}} | {"ok":false,"error":"..."}
const installers = { claude: require('./scripts/install-hooks'), codex: require('./scripts/install-codex-hooks') };

const [action, target] = process.argv.slice(2);
const installer = installers[target];
try {
  if (!installer || !['status', 'install', 'uninstall'].includes(action)) throw new Error('usage: hooks.js <status|install|uninstall> <claude|codex>');
  process.stdout.write(JSON.stringify({ ok: true, data: installer[action]() }) + '\n');
} catch (err) {
  process.stdout.write(JSON.stringify({ ok: false, error: err.message }) + '\n');
  process.exitCode = 1;
}
