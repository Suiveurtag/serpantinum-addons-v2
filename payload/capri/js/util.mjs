// capri-desktop src/renderer/js/util.js (licence in ../LICENSE), for QML's JavaScript engine: it has
// no setTimeout, requestAnimationFrame, performance or matchMedia, so they live here, driven by
// pump() from one QML Timer (CapriEngine.qml). Only what Capri's body, fx and forms use.

const T0 = Date.now();
export const performance = { now: () => Date.now() - T0 };

let timers = [];
let frames = [];
export function setTimeout(fn, ms = 0) {
  const t = { at: performance.now() + ms, fn };
  timers.push(t);
  return t;
}
export function clearTimeout(t) {
  timers = timers.filter((x) => x !== t);
}
export function requestAnimationFrame(fn) {
  frames.push(fn);
}
// One tick of the host clock: due timeouts, then this frame's callbacks.
export function pump() {
  const now = performance.now();
  const due = timers.filter((t) => t.at <= now);
  if (due.length) timers = timers.filter((t) => t.at > now);
  for (const t of due) t.fn();
  const run = frames;
  frames = [];
  for (const fn of run) fn(now);
}
// Capri turned off: nothing left to call into destroyed QML items.
export function reset() {
  timers = [];
  frames = [];
}

// async/await is missing too: co(generator) runs a generator that yields promises, as an async function would.
export function co(it) {
  return new Promise((resolve, reject) => {
    const step = (ok, value) => {
      let r;
      try {
        r = ok ? it.next(value) : it.throw(value);
      } catch (error) {
        reject(error);
        return;
      }
      if (r.done) resolve(r.value);
      else Promise.resolve(r.value).then((v) => step(true, v), (e) => step(false, e));
    };
    step(true);
  });
}

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
export const rand = (a, b) => a + Math.random() * (b - a);
export const pick = (list) => list[Math.floor(Math.random() * list.length)];
export const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
export const lerp = (a, b, t) => a + (b - a) * t;

export const ease = {
  linear: (t) => t,
  out: (t) => 1 - Math.pow(1 - t, 4),               // power4.out
  in: (t) => t * t * t,
  inOut: (t) => (t < 0.5 ? 8 * t * t * t * t : 1 - Math.pow(-2 * t + 2, 4) / 2),
};

// The shell's performance mode stands in for prefers-reduced-motion (set by CapriEngine.qml).
export const reducedMotion = { matches: false };

// localStorage stand-in, backed by the shell's Config (set by CapriEngine.qml).
export const storage = { getItem: () => null, setItem: () => {} };

// the local date, YYYY-MM-DD
export const today = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

// Tweens a set of numeric props on `target`. Values are read by the stepped render loop,
// so the result lands on whole drawing frames like cel animation.
export function tween(target, to, ms, easing = ease.out) {
  const from = {};
  for (const k of Object.keys(to)) from[k] = target[k];
  const start = performance.now();
  return new Promise((resolve) => {
    if (ms <= 0) {
      Object.assign(target, to);
      resolve();
      return;
    }
    const tick = () => {
      const t = Math.min(1, (performance.now() - start) / ms);
      const e = easing(t);
      for (const k of Object.keys(to)) target[k] = lerp(from[k], to[k], e);
      if (t < 1) requestAnimationFrame(tick);
      else resolve();
    };
    requestAnimationFrame(tick);
  });
}
