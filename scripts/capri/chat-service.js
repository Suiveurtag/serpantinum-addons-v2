'use strict';

const fs = require('node:fs'),
  path = require('node:path'),
  os = require('node:os');
const llm = require('./llm'),
  ollama = require('./ollama'),
  {
    Actions
  } = require('./actions');
const intents = import('./intent.mjs');
const validHistory = h => Array.isArray(h) ? h.filter(m => m && ['user', 'assistant'].includes(m.role) && typeof m.content === 'string').slice(-60).map(m => ({
  role: m.role,
  content: m.content.slice(0, 16000)
})) : [];
class ChatService {
  constructor(emit) {
    this.emit = emit;
    this.actions = new Actions();
    this.turns = new Map();
    this.chatModels = [];
    this.dir = path.join(process.env.XDG_STATE_HOME || path.join(os.homedir(), '.local/state'), 'serpantinum', 'capri');
    fs.mkdirSync(this.dir, {
      recursive: true,
      mode: 0o700
    });
    fs.chmodSync(this.dir, 0o700);
    this.cfg = {
      provider: 'ollama',
      chatModel: null,
      apiKeys: {},
      ...this.read('chat.json', {})
    };
    this.memory = this.read('memory.json', {
      history: [],
      claude: null
    });
    llm.restoreClaude(this.memory.claude);
  }
  read(name, fallback) {
    try {
      return JSON.parse(fs.readFileSync(path.join(this.dir, name), 'utf8'));
    } catch {
      return fallback;
    }
  }
  save(name, data) {
    const p = path.join(this.dir, name),
      tmp = p + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(data, null, 2), {
      mode: 0o600
    });
    fs.chmodSync(tmp, 0o600);
    fs.renameSync(tmp, p);
  }
  publicConfig() {
    const {
      apiKeys,
      ...cfg
    } = this.cfg;
    return {
      ...cfg,
      keys: Object.keys(apiKeys || {}),
      providers: Object.entries(llm.PROVIDERS).map(([id, p]) => ({
        id,
        label: p.label
      })),
      models: this.chatModels
    };
  }
  async status() {
    const provider = this.cfg.provider;
    this.chatModels = await llm.models(provider, this.cfg);
    if (!this.chatModels) return {
      ok: false,
      error: 'offline',
      provider
    };
    if (!this.chatModels.length) return {
      ok: false,
      error: 'nomodel',
      provider
    };
    const model = this.chatModels.includes(this.cfg.chatModel) ? this.cfg.chatModel : this.chatModels.find(m => !ollama.isCloud(m)) || this.chatModels[0];
    this.cfg.chatModel = model;
    llm.warm(provider, model);
    return {
      ok: true,
      provider,
      model,
      agent: provider === 'claude',
      local: llm.isLocal(provider, this.cfg, model),
      warmup: provider === 'ollama' && !ollama.isCloud(model)
    };
  }
  async configure(patch) {
    if (!patch || typeof patch !== 'object') throw new Error('Invalid configuration');
    const old = this.cfg,
      oldModels = this.chatModels,
      next = {
        ...old,
        apiKeys: {
          ...old.apiKeys
        }
      };
    if (patch.provider !== undefined) {
      if (!Object.hasOwn(llm.PROVIDERS, patch.provider)) throw new Error('Unknown provider');
      next.provider = patch.provider;
      if (next.provider !== old.provider) next.chatModel = null;
    }
    for (const key of ['chatModel', 'codexModel', 'customUrl', 'claudeCwd', 'claudeMode']) if (patch[key] !== undefined) {
      if (typeof patch[key] !== 'string' || patch[key].length > 2000) throw new Error('Invalid ' + key);
      next[key] = patch[key];
    }
    if (next.customUrl) {
      const u = new URL(next.customUrl);
      if (!['http:', 'https:'].includes(u.protocol) || u.username || u.password) throw new Error('Use an HTTP(S) server address');
    }
    if (patch.apiKey !== undefined) {
      if (typeof patch.apiKey !== 'string' || patch.apiKey.length > 4096) throw new Error('Invalid key');
      if (patch.apiKey) next.apiKeys[next.provider] = patch.apiKey;
    }
    if (patch.removeKey) delete next.apiKeys[next.provider];
    this.cfg = next;
    try {
      const status = await this.status();
      if (!status.ok) throw new Error(status.error);
      this.save('chat.json', this.cfg);
      if (next.claudeCwd !== old.claudeCwd) {
        llm.resetClaude();
        this.memory.claude = null;
        this.save('memory.json', this.memory);
      }
      return {
        ...status,
        config: this.publicConfig()
      };
    } catch (e) {
      this.cfg = old;
      this.chatModels = oldModels;
      throw e;
    }
  }
  async send({
    id,
    messages
  }) {
    if (this.turns.size) throw new Error('An answer is already running');
    if (!Array.isArray(messages) || messages.length > 21 || !messages.length || messages.some(m => !m || !['system', 'user', 'assistant'].includes(m.role) || typeof m.content !== 'string' || m.content.length > 32000) || messages.at(-1).role !== 'user') throw new Error('Invalid conversation');
    const ctrl = new AbortController();
    this.turns.set(id, ctrl);
    const timeout = setTimeout(() => ctrl.abort(), 90000);
    let streamed = false,
      model = this.cfg.chatModel,
      tried = new Set(),
      busy = 0;
    try {
      if (!model) {
        const s = await this.status();
        if (!s.ok) throw new Error(s.error);
        model = s.model;
      }
      for (;;) {
        try {
          const text = await llm.chat(this.cfg.provider, this.cfg, {
            model,
            messages
          }, piece => {
            if (!ctrl.signal.aborted) {
              streamed = true;
              this.emit({
                t: 'chat.delta',
                id,
                text: piece
              });
            }
          }, ctrl.signal);
          this.cfg.chatModel = model;
          this.save('chat.json', this.cfg);
          this.memory.claude = llm.claudeMemory();
          this.save('memory.json', this.memory);
          return {
            ok: true,
            text,
            model
          };
        } catch (e) {
          if (ctrl.signal.aborted || streamed || !['busy', 'gone', 'signin'].includes(e.code) || this.cfg.provider === 'claude') throw e;
          if (e.code === 'busy' && busy++ === 0) {
            await new Promise(r => {
              const t = setTimeout(r, 1500);
              ctrl.signal.addEventListener('abort', () => {
                clearTimeout(t);
                r();
              }, {
                once: true
              });
            });
            ctrl.signal.throwIfAborted();
            continue;
          }
          tried.add(model);
          const next = this.chatModels.find(m => !tried.has(m) && !ollama.isCloud(m)) || this.chatModels.find(m => !tried.has(m));
          if (!next || tried.size >= 3) throw e;
          model = next;
          busy = 0;
        }
      }
    } finally {
      clearTimeout(timeout);
      this.turns.delete(id);
    }
  }
  async request(m) {
    const a = m.args || {};
    switch (m.method) {
      case 'status':
        return this.status();
      case 'config':
        return this.publicConfig();
      case 'configure':
        return this.configure(a);
      case 'memory':
        return validHistory(this.memory.history);
      case 'remember':
        this.memory.history = validHistory(a.history);
        this.save('memory.json', this.memory);
        return true;
      case 'forget':
        for (const c of this.turns.values()) c.abort();
        llm.resetClaude();
        this.memory = {
          history: [],
          claude: null
        };
        this.save('memory.json', this.memory);
        return true;
      case 'stop':
        this.turns.get(a.id)?.abort();
        return true;
      case 'send':
        return this.send(a);
      case 'intent':
        if (typeof a.text !== 'string' || a.text.length > 2000) throw new Error('Message too long');
        return (await intents).parseIntent(a.text, Array.isArray(a.apps) ? a.apps : [], a.waitingWhen);
      default:
        if (!['openApps', 'findApp', 'closeApp', 'findLaunch', 'launch', 'openSite', 'media', 'music', 'youtube', 'roblox', 'webSearch', 'searchFiles', 'openFile', 'screenshot'].includes(m.method)) throw new Error('Unknown method');
        return this.actions[m.method](...(Array.isArray(a.values) ? a.values : []));
    }
  }
  handle(m) {
    if (!m || typeof m !== 'object' || m.t !== 'chat.request') return false;
    if (typeof m.id !== 'string' || m.id.length > 80) return true;
    Promise.resolve().then(() => this.request(m)).then(data => this.emit({
      t: 'chat.result',
      id: m.id,
      data
    })).catch(e => this.emit({
      t: 'chat.result',
      id: m.id,
      data: {
        ok: false,
        error: String(e.message || e).slice(0, 300),
        code: e.code || null
      }
    }));
    return true;
  }
  stop() {
    for (const c of this.turns.values()) c.abort();
  }
}
module.exports = {
  ChatService,
  validHistory
};
