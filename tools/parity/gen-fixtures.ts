/**
 * Generates parity fixtures from the REAL StackRivals web engine (TypeScript), so the Lua port can
 * be checked against it on identical input sequences.
 *
 *   bun tools/parity/gen-fixtures.ts <path-to-stackrivals-practice-arena> > tests/fixtures/parity.lua
 *
 * Cases:
 *  - bot games (the web bot at every difficulty) -> real play with many line clears, combos,
 *    back-to-back quads and high levels;
 *  - fuzz scripts -> random actions incl. hold, soft drop, both rotations, wall kicks, top-outs.
 * For every case we record the input log and the web engine's hashState at several checkpoints.
 */
const web = process.argv[2];
if (!web) throw new Error("usage: bun gen-fixtures.ts <web repo path>");
const eng = await import(`${web}/src/game/engine/engine.ts`);
const prng = await import(`${web}/src/game/engine/prng.ts`);
const bot = await import(`${web}/src/game/bot/bot.ts`);
const { INPUT_ACTIONS } = await import(`${web}/src/game/engine/types.ts`);

type Input = { tick: number; action: string };
const lua = (v: unknown): string => {
  if (typeof v === "string") return JSON.stringify(v);
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  if (Array.isArray(v)) return `{${v.map(lua).join(",")}}`;
  if (v && typeof v === "object") return `{${Object.entries(v).map(([k, x]) => `[${JSON.stringify(k)}]=${lua(x)}`).join(",")}}`;
  return "nil";
};

function summarize(s: any) {
  return {
    hash: eng.hashState(s), score: s.score, lines: s.lines, level: s.level, pieces: s.piecesPlaced,
    tick: s.tick, gameOver: s.gameOver, quads: s.clears.quad, b2b: s.backToBack, combo: s.combo,
  };
}

function caseFor(name: string, seed: string, inputs: Input[], untilTick: number) {
  const flat: number[] = [];
  for (const i of inputs) flat.push(i.tick, INPUT_ACTIONS.indexOf(i.action));
  const checkpoints = [Math.floor(untilTick / 4), Math.floor(untilTick / 2), untilTick].map((t) => {
    const s = eng.replay(seed, {}, inputs, t);
    return { until: t, ...summarize(s) };
  });
  return { name, seed, untilTick, log: flat, checkpoints };
}

const cases: unknown[] = [];

// 1) bot games
const diffs = ["rookie", "challenger", "contender", "elite", "rival"];
let n = 0;
for (const d of diffs) {
  for (let k = 0; k < 4; k++) {
    const seed = `bot-${d}-${k}`;
    const g = bot.generateBotGame(seed, d, 36000);
    const inputs: Input[] = eng.deserializeInputs(g.log);
    cases.push(caseFor(`bot ${d} #${k}`, seed, inputs, g.log.ticks));
    n++;
  }
}

// 1b) "well" bot: keeps the right column open and aims for quads, so parity covers quads,
// back-to-back bonuses, long combos chains and high levels through real play.
function wellBotGame(seed: string, until: number, gap: number) {
  let s = eng.createGame(seed);
  const inputs: Input[] = [];
  const W = s.config.width;
  const H = s.config.height + s.config.hiddenRows;
  const evalBoard = (st: any, cleared: number) => {
    const b: number[] = st.board;
    const heights: number[] = [];
    let holes = 0;
    for (let x = 0; x < W; x++) {
      let top = H;
      for (let y = 0; y < H; y++) if (b[y * W + x]) { top = y; break; }
      heights.push(H - top);
      for (let y = top + 1; y < H; y++) if (!b[y * W + x]) holes++;
    }
    const maxH = Math.max(...heights);
    let bump = 0;
    for (let x = 0; x < W - 2; x++) bump += Math.abs(heights[x]! - heights[x + 1]!);
    const wellBlocked = heights[W - 1]! > 0 ? 1 : 0;
    let v = -holes * 40 - bump * 3 - heights.slice(0, W - 1).reduce((a, h) => a + h, 0) * 0.6 - wellBlocked * 60;
    if (cleared === 4) v += 400;
    else if (cleared > 0) v += maxH > 12 ? 30 * cleared : -25 * cleared;
    if (maxH > 15) v -= 200;
    return v;
  };
  while (!s.gameOver && s.tick < until) {
    // choose the best (rotation, x) for the active piece
    let best: { acts: string[]; v: number } | null = null;
    for (let rot = 0; rot < 4; rot++) {
      for (let dx = -5; dx <= 5; dx++) {
        const acts: string[] = [];
        if (rot === 3) acts.push("rotateCCW"); else for (let k = 0; k < rot; k++) acts.push("rotateCW");
        for (let k = 0; k < Math.abs(dx); k++) acts.push(dx < 0 ? "left" : "right");
        let t = s;
        let ok = true;
        for (const a of acts) {
          const before = t.active;
          t = eng.applyInput(t, a, t.tick);
          if (t.active && before && t.active.x === before.x && t.active.rotation === before.rotation && t.active.y === before.y) { ok = false; break; }
        }
        if (!ok) continue;
        const linesBefore = t.lines;
        t = eng.applyInput(t, "hardDrop", t.tick);
        const v = evalBoard(t, t.lines - linesBefore) + (t.gameOver ? -1e6 : 0);
        if (!best || v > best.v) best = { acts: [...acts, "hardDrop"], v };
      }
    }
    if (!best) best = { acts: ["hardDrop"], v: 0 };
    for (const a of best.acts) {
      for (let k = 0; k < gap; k++) s = eng.tick(s); // human-ish pacing; gravity keeps running
      if (s.gameOver || !s.active) break;
      inputs.push({ tick: s.tick, action: a });
      s = eng.applyInput(s, a, s.tick);
      if (s.gameOver) break;
    }
    if (s.tick >= until) break;
  }
  return { inputs, ticks: s.tick };
}
for (let k = 0; k < 6; k++) {
  const seed = `well-${k}`;
  const g = wellBotGame(seed, 30000, 1 + (k % 3));
  cases.push(caseFor(`well bot #${k}`, seed, g.inputs, g.ticks));
}

// 2) fuzz scripts with a seeded PRNG (so fixtures are reproducible)
let r = prng.hashString("srwow-fuzz");
const rand = () => { const [v, nx] = prng.nextRandom(r); r = nx; return v; };
const WEIGHTS: [string, number][] = [
  ["left", 18], ["right", 18], ["rotateCW", 12], ["rotateCCW", 10], ["softDrop", 14], ["hardDrop", 16], ["hold", 6],
];
const total = WEIGHTS.reduce((a, [, w]) => a + w, 0);
const pick = () => { let x = rand() * total; for (const [a, w] of WEIGHTS) { if ((x -= w) < 0) return a; } return "hardDrop"; };
for (let k = 0; k < 40; k++) {
  const seed = `fuzz-${k}-${Math.floor(rand() * 1e9).toString(16)}`;
  const until = 600 + Math.floor(rand() * 9000);
  const inputs: Input[] = [];
  let t = 0;
  while (t < until) {
    const burst = 1 + Math.floor(rand() * 3); // several inputs on one tick happen in real play
    for (let b = 0; b < burst; b++) inputs.push({ tick: t, action: pick() });
    t += Math.floor(rand() * 25);
  }
  cases.push(caseFor(`fuzz #${k}`, seed, inputs, until));
}

// 3) PRNG vectors
const vectors = ["", "a", "abc", "StackRivals", "srwow-daily-2026-11-04", "0123456789abcdef"].map((str) => {
  let st = prng.hashString(str);
  const seq: number[] = [];
  for (let i = 0; i < 8; i++) { const [v, nx] = prng.nextRandom(st); st = nx; seq.push(Math.floor(v * 1e9)); }
  return { str, hash: prng.hashString(str), seq };
});

// 4) Daily Blitz golden sequences: the first 14 pieces for fixed UTC dates (seed format of the addon)
const { PIECE_IDS } = await import(`${web}/src/game/engine/pieces.ts`);
const dailies = ["2026-11-04", "2026-11-05", "2026-12-24", "2027-01-01", "2028-02-29"].map((date) => {
  const seed = `srwow-daily-${date}`;
  const g = eng.createGame(seed);
  // the engine deals 7-piece bags: bag 1 + bag 2 = the first 14 pieces of the run
  let st = prng.hashString(seed);
  const [b1, n1] = prng.shuffle(PIECE_IDS, st);
  const [b2] = prng.shuffle(PIECE_IDS, n1);
  const pieces = [...b1, ...b2];
  if (pieces[0] !== g.active.id || pieces[1] !== g.queue[0]) throw new Error("bag order mismatch");
  return { date, pieces };
});

// 5) Rules fingerprint: every constant that defines gameplay. The Lua test compares these one by
// one, so a rule change on the web shows up as a precise failing line (not just a hash mismatch).
const pieces = await import(`${web}/src/game/engine/pieces.ts`);
const types = await import(`${web}/src/game/engine/types.ts`);
const controls = await import(`${web}/src/game/controls.ts`);
let match: Record<string, number> = {};
try {
  const m = await import(`${web}/src/lib/match/rules.ts`);
  match = {
    timeCapMs: m.DEFAULT_TIME_CAP_MS, countdownMs: m.COUNTDOWN_MS, maxInputsPerTick: m.MAX_INPUTS_PER_TICK,
    maxInputsPerSecond: m.MAX_INPUTS_PER_SECOND, reconnectGraceMs: m.RECONNECT_GRACE_MS,
  };
} catch { /* web match rules unavailable: leave empty */ }
const kicks: Record<string, number[][]> = {};
for (const id of pieces.PIECE_IDS) for (const [f, t] of [[0, 1], [1, 0], [1, 2], [2, 1], [2, 3], [3, 2], [3, 0], [0, 3]]) {
  kicks[`${id}:${f}>${t}`] = pieces.getKicks(id, f, t).map((c: number[]) => [c[0], c[1]]);
}
const shapes: Record<string, number[][][]> = {};
for (const id of pieces.PIECE_IDS) shapes[id] = pieces.SHAPES[id].map((r: number[][]) => r.map((c) => [c[0], c[1]]));
const rules = {
  engineVersion: types.ENGINE_VERSION,
  ticksPerSecond: types.TICKS_PER_SECOND,
  inputActions: [...types.INPUT_ACTIONS],
  pieceIds: [...pieces.PIECE_IDS],
  config: { ...types.DEFAULT_CONFIG },
  linePoints: [1, 2, 3, 4].map((n) => eng.LINE_POINTS[n]),
  b2bMultiplier: eng.B2B_MULTIPLIER,
  comboPoints: eng.COMBO_POINTS,
  softDropPoints: eng.SOFT_DROP_POINTS,
  hardDropPoints: eng.HARD_DROP_POINTS,
  gravity: Array.from({ length: 25 }, (_, i) => eng.gravityTicks(i + 1)),
  handling: { ...controls.HANDLING },
  shapes,
  kicks,
  match,
};
const { execSync } = await import("node:child_process");
let webCommit = "unknown";
try { webCommit = execSync(`git -C ${JSON.stringify(web)} rev-parse HEAD`).toString().trim(); } catch { /* not a git checkout */ }

console.log(`-- GENERATED by tools/parity/gen-fixtures.ts from the web engine at commit ${webCommit} (ENGINE_VERSION ${types.ENGINE_VERSION}). Do not edit.`);
console.log(`return ${lua({ engineVersion: types.ENGINE_VERSION, webCommit, rules, prngVectors: vectors, dailies, cases })}`);
console.error(`${cases.length} cases (${n} bot games)`);
