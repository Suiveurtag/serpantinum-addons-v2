import assert from 'node:assert/strict';
import { monitors, displayAt, windows, covered, span, ledges, landing, beyond, cursor, diff } from '../../payload/clawd/js/world.mjs';

// Two screens side by side (the live layout: HDMI-A-1 left of DP-1, bars on top) + a third one far away.
const screens = [{ name: 'DP-1', x: 0, y: 31, width: 1920, height: 1080 }, { name: 'HDMI-A-1', x: -1920, y: 27, width: 1920, height: 1080 },
  { name: 'far', x: 5000, y: 0, width: 800, height: 600 }];
const native = [
  { name: 'DP-1', x: 0, y: 31, activeWorkspace: { id: 2 }, lastIpcObject: { reserved: [0, 45, 0, 0], specialWorkspace: { id: 0 } } },
  // raw `hyprctl monitors -j` shape (fixtures): reserved at the top level
  { name: 'HDMI-A-1', x: -1920, y: 27, activeWorkspace: { id: 1 }, reserved: [0, 45, 0, 30], specialWorkspace: { id: -98 } },
];
const displays = monitors(screens, native);
const [dp, hdmi, far] = displays;
assert.deepEqual(dp, { id: 'DP-1', x: 0, y: 31, w: 1920, h: 1080, floor: 1111, top: 76, workspace: 2, special: 0 });
assert.deepEqual(hdmi, { id: 'HDMI-A-1', x: -1920, y: 27, w: 1920, h: 1080, floor: 1077, top: 72, workspace: 1, special: -98 });
assert.deepEqual(far, { id: 'far', x: 5000, y: 0, w: 800, h: 600, floor: 600, top: 0, workspace: null, special: 0 });
assert.deepEqual(monitors([{ name: 'solo', x: 0, y: 0, width: 100, height: 50 }], []), [{ id: 'solo', x: 0, y: 0, w: 100, h: 50, floor: 50, top: 0, workspace: null, special: 0 }]);
assert.equal(displayAt(displays, 10, 40).id, 'DP-1');
assert.equal(displayAt(displays, -5, 500).id, 'HDMI-A-1');
assert.equal(displayAt(displays, 4000, 500).id, 'far');  // nearest

// Windows: visible ones only, global coords, front first.
const client = (address, more = {}) => ({ address, at: [100, 300], size: [600, 400], workspace: { id: 2 }, mapped: true, focusHistoryID: 5, ...more });
const clients = [
  client('tile', { focusHistoryID: 0, at: [8, 84], size: [1904, 1019] }),
  client('float', { floating: true, focusHistoryID: 1, at: [786, 445], size: [1065, 587] }),
  client('back', { floating: true, focusHistoryID: 3, at: [600, 700], size: [500, 300] }),
  client('hidden', { hidden: true }), client('unmapped', { mapped: false }), client('min', { minimized: true }),
  client('foreignmin', { floating: true }), client('other-ws', { workspace: { id: 7 } }),
  client('left', { workspace: { id: 1 }, at: [-1800, 500], size: [800, 400], floating: true, focusHistoryID: 2 }),
  client('special', { workspace: { id: -98 }, floating: true, focusHistoryID: 9, at: [-1000, 200], size: [300, 300] }),
  client('pinned', { workspace: { id: 9 }, pinned: true, focusHistoryID: 8, at: [1500, 100], size: [200, 200] }),
  client('full', { fullscreen: 2, focusHistoryID: 6, workspace: { id: 1 }, at: [-1920, 27], size: [1920, 1080] }),
  { address: 'broken' },
];
const wins = windows(clients, displays, { foreignmin: true });
assert.deepEqual(wins.map(w => w.id), ['full', 'float', 'left', 'back', 'pinned', 'special', 'tile']);
assert.deepEqual(wins[1], { id: 'float', x: 786, y: 445, w: 1065, h: 587, max: false, floating: true, display: 'DP-1' });
assert.equal(wins[0].max, true);
assert.equal(wins.find(w => w.id === 'left').display, 'HDMI-A-1');
assert.equal(wins.find(w => w.id === 'tile').floating, false);
assert.deepEqual(windows([], displays), []);

// Covered: windows in front only.
assert.equal(covered(wins, 'back', 800, 820, 700), true);    // float (in front) covers back's top there
assert.equal(covered(wins, 'back', 600, 700, 700), false);   // float starts at x 786
assert.equal(covered(wins, 'float', 800, 900, 445), false);  // nothing in front of it on DP-1
assert.equal(covered(wins, 'tile', 800, 900, 445), true);
assert.equal(covered(wins, 'nope', 800, 900, 445), true);     // unknown id: every window counts

// Ledges: window tops with room above under the bar, wide enough, not maximized, above the floor; one floor per display.
const petW = 84, petH = 56;
const flat = ledges({ wins, displays, petW, petH });
assert.deepEqual(flat.filter(l => l.kind === 'win').map(l => l.id), ['float', 'left', 'back', 'special']);
assert.deepEqual(flat.find(l => l.id === 'float'), { id: 'float', kind: 'win', x: 786, y: 445, w: 1065, display: 'DP-1' });
// tile: top 84 is 8 px under the bar (76); pinned: 200 px wide but its top (100) has no room; full: maximized
assert.deepEqual(flat.filter(l => l.kind === 'floor').map(l => [l.id, l.y, l.x, l.w]), [['floor:DP-1', 1111, 0, 1920], ['floor:HDMI-A-1', 1077, -1920, 1920], ['floor:far', 600, 5000, 800]]);
assert.equal(ledges({ wins: [{ id: 'narrow', x: 0, y: 500, w: 120, h: 100, display: 'DP-1' }], displays, petW, petH }).filter(l => l.kind === 'win').length, 0);
assert.equal(ledges({ wins: [{ id: 'low', x: 0, y: 1100, w: 500, h: 11, display: 'DP-1' }], displays, petW, petH }).filter(l => l.kind === 'win').length, 0);
// widgets (5d) use the same rules
assert.deepEqual(ledges({ widgets: [{ id: 'clock', x: 100, y: 400, w: 300, h: 120, display: 'DP-1' }], displays, petW, petH }).filter(l => l.kind === 'widget').map(l => l.id), ['clock']);
assert.equal(ledges({ displays }).length, 3);

// Span: the uncovered part of a ledge around cx.
const back = flat.find(l => l.id === 'back');
assert.deepEqual(span(wins, back, 650), { x0: 600, x1: 786 });  // float covers back's top from x 786
assert.equal(span(wins, back, 900), null);
assert.equal(span(wins, back, 2000), null);                       // off the ledge
assert.deepEqual(span(wins, flat.find(l => l.id === 'float'), 1000), { x0: 786, x1: 1851 });
assert.deepEqual(span(wins, flat.find(l => l.kind === 'floor'), 50), { x0: 0, x1: 1920 });

// Landing: first free ledge at/below his feet spanning cx, else the floor under cx.
assert.equal(landing(flat, wins, 1000, 100, displays).id, 'float');
assert.equal(landing(flat, wins, 1000, 446, displays).id, 'float');   // 1 px tolerance
assert.equal(landing(flat, wins, 1000, 450, displays).id, 'floor:DP-1');
assert.equal(landing(flat, wins, 650, 100, displays).id, 'back');
assert.equal(landing(flat, wins, 900, 500, displays).id, 'floor:DP-1');   // under float, back is covered there
assert.equal(landing(flat, wins, -1500, 100, displays).id, 'floor:HDMI-A-1');  // the fullscreen window covers 'left'
assert.equal(landing(flat, wins.filter(w => w.id !== 'full'), -1500, 100, displays).id, 'left');
assert.equal(landing(flat, wins, -100, 100, displays).id, 'floor:HDMI-A-1');
assert.equal(landing(flat, wins, 5100, 0, displays).id, 'floor:far');
assert.equal(landing(flat.filter(l => l.kind === 'floor'), [], 100, 100).id, 'floor:DP-1');  // no displays: floors' spans
assert.equal(landing([], [], 0, 0, displays), null);

// Beyond / cursor in global coords.
assert.equal(beyond(displays, dp, -1, 500).id, 'HDMI-A-1');
assert.equal(beyond(displays, hdmi, 1, 500).id, 'DP-1');
assert.equal(beyond(displays, dp, 1, 500), null);
assert.equal(beyond(displays, dp, -1, 10), null);   // above HDMI's top (27)
assert.equal(beyond(displays, null, 1, 0), null);
assert.deepEqual(cursor(displays, dp, { x: -100, y: 600 }), { x: -100, y: 600, display: 'HDMI-A-1', inside: false });
assert.deepEqual(cursor(displays, dp, { x: 100, y: 600 }), { x: 100, y: 600, display: 'DP-1', inside: true });
assert.deepEqual(cursor(displays, dp, { x: 3000, y: 600 }), { x: 3000, y: 600, display: null, inside: false });
assert.equal(cursor(displays, dp, null), null);

// Diff.
const r = (x, y = 0) => ({ x, y, w: 10, h: 10 });
assert.deepEqual(diff({ a: r(0), b: r(5), c: r(9) }, { a: r(0), b: r(6), d: r(1) }), { opened: ['d'], closed: [{ id: 'c', rect: r(9) }], moved: ['b'] });
assert.deepEqual(diff({}, {}), { opened: [], closed: [], moved: [] });
console.log('CLAWD_WORLD_PASS');
