#!/usr/bin/env node
'use strict';

// Capri sidecar: JSON lines on stdout for the shell, JSON lines on stdin from it.
// Keeps the upstream HTTP bridge (127.0.0.1:47823) so the upstream hooks work unchanged.
// stdout carries protocol only: route every log line to stderr.
console.log = console.error;

const readline = require('node:readline');
const { createBridge } = require('./lib/bridge');

const PORT = Number(process.env.CAPRI_PORT) || 47823;

function emit(message) {
  process.stdout.write(JSON.stringify(message) + '\n');
}

const server = createBridge({ port: PORT, onEvent: (evt) => emit({ t: 'event', evt }) });

const input = readline.createInterface({ input: process.stdin });
input.on('line', (line) => {
  let message;
  try { message = JSON.parse(line); } catch { return; }
  if (message?.t === 'ping') emit({ t: 'pong', id: message.id });
});
// The shell closes stdin when Capri turns off or the shell exits: never outlive it.
input.on('close', () => { server.close(); process.exit(0); });
