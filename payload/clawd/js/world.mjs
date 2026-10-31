// Clawd's world, pure geometry in GLOBAL logical px (Hyprland layout coordinates). Adapted from Capri's world.mjs.

// Quickshell screens + Hyprland monitors (Quickshell HyprlandMonitor or raw `hyprctl monitors -j` objects) -> displays.
// floor = where he stands (above the reserved bottom area), top = under the bar (reserved top).
export function monitors(screens, native) {
  return screens.map(s => {
    const m = (native || []).find(m => m.name === s.name) || null;
    const ipc = m ? m.lastIpcObject || m : {};
    const r = Array.isArray(ipc.reserved) ? ipc.reserved : [0, 0, 0, 0];
    const x = m && Number.isFinite(m.x) ? m.x : s.x, y = m && Number.isFinite(m.y) ? m.y : s.y;
    const ws = m && m.activeWorkspace ? m.activeWorkspace.id : null;
    return { id: s.name, x, y, w: s.width, h: s.height,
      floor: y + s.height - Math.max(0, r[3] || 0), top: y + Math.max(0, r[1] || 0),
      workspace: Number.isFinite(ws) ? ws : null, special: ipc.specialWorkspace && ipc.specialWorkspace.id || 0 };
  });
}

// The display containing (gx, gy), else the nearest one.
export function displayAt(displays, gx, gy) {
  let best = null, gap = Infinity;
  for (const d of displays) {
    const dx = Math.max(d.x - gx, 0, gx - d.x - d.w), dy = Math.max(d.y - gy, 0, gy - d.y - d.h);
    if (dx + dy < gap) { gap = dx + dy; best = d; }
  }
  return best;
}

// j/clients -> the windows on screen, front first: fullscreen > floating/pinned > tiled, then focus history
// (approximates Hyprland's stacking). minimized: {address: true} from the foreign-toplevel protocol.
export function windows(clients, displays, minimized) {
  const shown = (clients || []).filter(c => {
    if (!c || !c.address || !c.at || !c.size || c.hidden || c.mapped === false || c.minimized || minimized && minimized[c.address]) return false;
    const ws = c.workspace ? c.workspace.id : null;
    return c.pinned || displays.some(d => ws === d.workspace || (d.special && ws === d.special));
  });
  const layer = c => c.fullscreen ? 2 : c.floating || c.pinned ? 1 : 0;
  const focus = c => c.focusHistoryID >= 0 ? c.focusHistoryID : Infinity;
  shown.sort((a, b) => layer(b) - layer(a) || focus(a) - focus(b));
  return shown.map(c => {
    const x = c.at[0], y = c.at[1], w = c.size[0], h = c.size[1];
    const d = displayAt(displays, x + w / 2, y + h / 2);
    return { id: c.address, x, y, w, h, max: !!(c.fullscreen || c.maximized), floating: !!(c.floating || c.pinned), display: d ? d.id : null };
  });
}

// Is any part of [x0, x1] at height y covered by a window in front of window `id`? (Unknown id: every window counts.)
export function covered(wins, id, x0, x1, y) {
  const i = wins.findIndex(w => w.id === id);
  const front = i < 0 ? wins : wins.slice(0, i);
  return front.some(w => w.x < x1 && w.x + w.w > x0 && y >= w.y && y < w.y + w.h);
}

// The uncovered piece of a ledge's top line around cx: {x0, x1}, or null when cx itself is covered or off the ledge.
export function span(wins, ledge, cx) {
  if (!ledge || cx < ledge.x || cx > ledge.x + ledge.w) return null;
  let x0 = ledge.x, x1 = ledge.x + ledge.w;
  if (ledge.kind === 'floor') return { x0, x1 };
  const i = wins.findIndex(w => w.id === ledge.id);
  for (const w of i < 0 ? wins : wins.slice(0, i)) {
    if (ledge.y < w.y || ledge.y >= w.y + w.h || w.x + w.w <= x0 || w.x >= x1) continue;
    if (cx >= w.x && cx <= w.x + w.w) return null;
    if (w.x + w.w <= cx) x0 = Math.max(x0, w.x + w.w); else x1 = Math.min(x1, w.x);
  }
  return { x0, x1 };
}

// Where he can stand: window tops (not maximized, wide enough, room above under the bar, above the floor),
// widget tops (5d: {id, x, y, w, h, display}) and one floor per display.
export function ledges({ wins = [], widgets = [], displays = [], petW = 0, petH = 0 }) {
  const out = [];
  const add = (kind, r) => {
    const d = displays.find(d => d.id === r.display) || displayAt(displays, r.x + r.w / 2, r.y);
    if (!d || r.max || r.w <= petW + 40 || r.y < d.top + petH + 8 || r.y > d.floor - petH) return;
    out.push({ id: r.id, kind, x: r.x, y: r.y, w: r.w, display: d.id });
  };
  for (const w of wins) add('win', w);
  for (const w of widgets) add('widget', w);
  for (const d of displays) out.push({ id: 'floor:' + d.id, kind: 'floor', x: d.x, y: d.floor, w: d.w, display: d.id });
  return out;
}

// Falling with his feet at (cx, feetY): the first free ledge he meets (top at/below his feet, spans cx, not covered at cx),
// else the floor of the display under cx.
export function landing(ledges, wins, cx, feetY, displays) {
  let best = null;
  for (const l of ledges) {
    if (l.kind === 'floor' || l.y < feetY - 1 || cx < l.x || cx > l.x + l.w || best && l.y >= best.y) continue;
    if (l.kind === 'win' && covered(wins, l.id, cx, cx, l.y)) continue;
    best = l;
  }
  if (best) return best;
  const floors = ledges.filter(l => l.kind === 'floor');
  const d = displayAt(displays || floors.map(f => ({ id: f.display, x: f.x, y: f.y - 1, w: f.w, h: 1 })), cx, feetY);
  return d && floors.find(f => f.display === d.id) || floors[0] || null;
}

// The display touching d on that side (+1 right, -1 left) at height gy.
export function beyond(displays, d, side, gy) {
  if (!d) return null;
  return displays.find(o => o.id !== d.id && gy >= o.y && gy < o.y + o.h
    && (side > 0 ? Math.abs(o.x - d.x - d.w) <= 2 : Math.abs(o.x + o.w - d.x) <= 2)) || null;
}

// Where the cursor is: global point, its display, and whether it is on his display.
export function cursor(displays, here, p) {
  if (!p || !here) return null;
  const screen = displays.find(d => p.x >= d.x && p.x < d.x + d.w && p.y >= d.y && p.y < d.y + d.h);
  return { x: p.x, y: p.y, display: screen ? screen.id : null, inside: !!screen && screen.id === here.id };
}

// Two {id: rect} maps -> what opened, what closed (with its last rect) and what moved or resized.
export function diff(prev, next) {
  const opened = [], closed = [], moved = [];
  for (const id of Object.keys(next)) {
    const a = prev[id], b = next[id];
    if (!a) opened.push(id);
    else if (a.x !== b.x || a.y !== b.y || a.w !== b.w || a.h !== b.h) moved.push(id);
  }
  for (const id of Object.keys(prev)) if (!next[id]) closed.push({ id, rect: prev[id] });
  return { opened, closed, moved };
}
