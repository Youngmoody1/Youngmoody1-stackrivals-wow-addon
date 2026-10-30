/**
 * Spell edge cases, scripted step by step on the web's REAL spell code (read-only on the web repo).
 * The Lua test (tests/test_spells.lua, "scenarios") runs the same scripts and must match the web
 * after every step: both boards (hashState), mana, freeze / speed / blackout, casts, invalid casts.
 *
 *   bun tools/parity/gen-spell-scenarios.ts <web repo> > tests/fixtures/spell_scenarios.lua
 *
 * Script ops (two sides, A = 0 and B = 1; opponent spells go to the other side's pending list,
 * exactly like SpellSim):
 *   ["mana", side, n]          set mana (scripts only: real mana comes from clears)
 *   ["board", side, rows]      fill the bottom rows ("X" = garbage cell, "." = empty)
 *   ["code", side, code]       applyCode (a move 0..6, a cast 100..108, or junk)
 *   ["step", side, n]          n ticks: incoming due spells land, then gravity (stepSide)
 *   ["both", n]                n lockstep ticks for both sides (A then B, like SpellSim)
 */
const web = process.argv[2];
if (!web) throw new Error("usage: bun gen-spell-scenarios.ts <web repo>");
const eng = await import(`${web}/src/game/engine/engine.ts`);
const sp = await import(`${web}/src/game/engine/spells.ts`);
const { execSync } = await import("node:child_process");
const lua = (v: unknown): string => {
  if (typeof v === "string") return JSON.stringify(v);
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  if (v === null || v === undefined) return "nil";
  if (Array.isArray(v)) return `{${v.map(lua).join(",")}}`;
  return `{${Object.entries(v as object).map(([k, x]) => `[${JSON.stringify(k)}]=${lua(x)}`).join(",")}}`;
};
const C = (s: string) => sp.castCode(s);
const L = { left: 0, right: 1, cw: 2, ccw: 3, soft: 4, hard: 5, hold: 6 };

type Op = [string, ...unknown[]];
interface Scenario { name: string; seed: string; loadouts: [string[], string[]]; ops: Op[] }

const self2 = (a: string, b: string, c = "garbage", d = "blackout") => [a, b, c, d];
const scenarios: Scenario[] = [
  { name: "bomb on an empty board, at spawn", seed: "sc-bomb-1", loadouts: [self2("bomb", "swap"), sp.DEFAULT_LOADOUT], ops: [["mana", 0, 20], ["code", 0, C("bomb")], ["step", 0, 3]] },
  { name: "bomb against the left wall over a filled stack", seed: "sc-bomb-2", loadouts: [self2("bomb", "swap"), sp.DEFAULT_LOADOUT],
    ops: [["board", 0, ["XXXXXXXXX.", "XXXX.XXXXX", "X.XXXXXXXX"]], ["mana", 0, 20], ["code", 0, L.left], ["code", 0, L.left], ["code", 0, L.left], ["code", 0, L.left], ["code", 0, L.left], ["code", 0, C("bomb")], ["step", 0, 2]] },
  { name: "bomb against the right wall, rotated piece", seed: "sc-bomb-3", loadouts: [self2("bomb", "freeze"), sp.DEFAULT_LOADOUT],
    ops: [["board", 0, ["XXXXXXXX.X", "XXXXXXXX.X"]], ["mana", 0, 20], ["code", 0, L.cw], ["code", 0, L.right], ["code", 0, L.right], ["code", 0, L.right], ["code", 0, L.right], ["code", 0, L.right], ["code", 0, C("bomb")], ["step", 0, 2]] },
  { name: "line blast on an empty board and on a stack", seed: "sc-lb", loadouts: [self2("lineBlast", "bomb"), sp.DEFAULT_LOADOUT],
    ops: [["mana", 0, 20], ["code", 0, C("lineBlast")], ["step", 0, 180], ["board", 0, ["XXXXXXXXX.", "XXXXX.XXXX", "X.XXXXXXXX", "XXX.XXXXXX"]], ["code", 0, C("lineBlast")], ["step", 0, 2]] },
  { name: "freeze: no fall for 300 ticks, then gravity again; a recast restarts it", seed: "sc-freeze", loadouts: [self2("freeze", "bomb"), sp.DEFAULT_LOADOUT],
    ops: [["mana", 0, 20], ["code", 0, C("freeze")], ["step", 0, 299], ["step", 0, 1], ["step", 0, 1], ["step", 0, 60], ["code", 0, C("freeze")], ["step", 0, 100]] },
  { name: "cooldown: 179 ticks refused, 180 allowed", seed: "sc-cd", loadouts: [self2("lineBlast", "bomb"), sp.DEFAULT_LOADOUT],
    ops: [["mana", 0, 20], ["code", 0, C("lineBlast")], ["step", 0, 179], ["code", 0, C("bomb")], ["step", 0, 1], ["code", 0, C("bomb")]] },
  { name: "swap with an empty hold, then with a held piece, then after hold was used", seed: "sc-swap", loadouts: [self2("swap", "bomb"), sp.DEFAULT_LOADOUT],
    ops: [["mana", 0, 20], ["code", 0, C("swap")], ["step", 0, 180], ["code", 0, L.hold], ["code", 0, C("swap")], ["step", 0, 180], ["code", 0, L.hard], ["code", 0, L.hold], ["code", 0, C("swap")]] },
  { name: "clear board on a high stack", seed: "sc-clear", loadouts: [self2("clearBoard", "bomb"), sp.DEFAULT_LOADOUT],
    ops: [["board", 0, Array.from({ length: 15 }, (_, i) => "XXXXXXXXXX".split("").map((c, x) => (x === i % 10 ? "." : c)).join(""))], ["mana", 0, 16], ["code", 0, C("clearBoard")], ["step", 0, 5]] },
  { name: "garbage: lands 90 ticks later with the seeded gap", seed: "sc-garbage", loadouts: [sp.DEFAULT_LOADOUT, sp.DEFAULT_LOADOUT],
    ops: [["mana", 0, 20], ["code", 0, C("garbage")], ["both", 89], ["both", 1], ["both", 1]] },
  { name: "garbage on a full stack tops the target out; spells after that have no effect", seed: "sc-garbage-top", loadouts: [sp.DEFAULT_LOADOUT, sp.DEFAULT_LOADOUT],
    ops: [["board", 1, Array.from({ length: 19 }, (_, i) => "XXXXXXXXXX".split("").map((c, x) => (x === i % 10 ? "." : c)).join(""))], ["mana", 0, 20], ["code", 0, C("garbage")], ["both", 95], ["mana", 1, 20], ["code", 1, C("lineBlast")], ["both", 200], ["code", 0, C("blackout")], ["both", 100]] },
  { name: "garbage pushes the falling piece up", seed: "sc-garbage-push", loadouts: [sp.DEFAULT_LOADOUT, sp.DEFAULT_LOADOUT],
    ops: [["board", 1, ["XXXXXXXXX.", "XXXXXXXXX."]], ["mana", 0, 20], ["code", 0, C("garbage")], ["step", 1, 60], ["both", 92]] },
  { name: "both cast garbage on the same tick: both land on the same tick", seed: "sc-cross", loadouts: [sp.DEFAULT_LOADOUT, sp.DEFAULT_LOADOUT],
    ops: [["mana", 0, 20], ["mana", 1, 20], ["code", 0, C("garbage")], ["code", 1, C("garbage")], ["both", 91], ["both", 90], ["code", 0, C("blackout")], ["code", 1, C("blackout")], ["both", 91]] },
  { name: "speed up and freeze overlap: freeze wins, then double gravity", seed: "sc-speed", loadouts: [["freeze", "bomb", "speedUp", "garbage"], ["freeze", "bomb", "speedUp", "garbage"]],
    ops: [["mana", 0, 20], ["mana", 1, 20], ["code", 0, C("speedUp")], ["both", 100], ["code", 1, C("freeze")], ["both", 200], ["both", 200], ["both", 100]] },
  { name: "blackout and scramble on the rival", seed: "sc-blind", loadouts: [["bomb", "swap", "blackout", "scramble"], sp.DEFAULT_LOADOUT],
    ops: [["board", 1, ["XXXX..XXXX", "XXX....XXX"]], ["mana", 0, 20], ["code", 0, C("scramble")], ["both", 91], ["both", 90], ["code", 0, C("blackout")], ["both", 91], ["both", 600]] },
  { name: "refused casts: no mana, not in loadout, topped out, junk codes", seed: "sc-refused", loadouts: [sp.DEFAULT_LOADOUT, sp.DEFAULT_LOADOUT],
    ops: [["mana", 0, 3], ["code", 0, C("lineBlast")], ["mana", 0, 20], ["code", 0, C("scramble")], ["code", 0, 57], ["code", 0, 109], ["code", 0, -1],
      ["board", 0, Array.from({ length: 20 }, (_, i) => "XXXXXXXXXX".split("").map((c, x) => (x === i % 10 ? "." : c)).join(""))], ["code", 0, L.hard], ["code", 0, C("lineBlast")]] },
];

function snap(sides: any[]) {
  return sides.map((s) => ({
    hash: eng.hashState(s.game), mana: s.mana, over: s.game.gameOver, tick: s.game.tick,
    freeze: s.freezeUntil, speed: s.speedUntil, blackout: s.blackoutUntil, next: s.game.queue[0],
    casts: s.casts.length, invalid: s.invalidCasts.map((c: any) => c.reason).join(","), logLen: s.log.length,
  }));
}

function run(sc: Scenario) {
  const sides = [sp.createSide(sc.seed, sc.loadouts[0]), sp.createSide(sc.seed, sc.loadouts[1])];
  const pending: any[][] = [[], []];
  const after: unknown[] = [];
  const recv = (i: number) => {
    const t = sides[i].game.tick;
    const due = pending[i].filter((x) => x.at <= t);
    if (due.length) { pending[i] = pending[i].filter((x) => x.at > t); for (const inc of due) sides[i] = sp.receive(sides[i], inc); }
  };
  const tick = (i: number) => { recv(i); sides[i] = sp.stepSide(sides[i]); };
  for (const op of sc.ops) {
    const [kind, a, b] = op as [string, number, any];
    if (kind === "mana") sides[a].mana = b;
    else if (kind === "board") {
      const g = sides[a].game;
      const w = g.config.width, h = g.config.height + g.config.hiddenRows;
      const rows = b as string[];
      rows.forEach((r, k) => { const y = h - rows.length + k; for (let x = 0; x < w; x++) g.board[y * w + x] = r[x] === "X" ? 8 : 0; });
    } else if (kind === "code") sides[a] = sp.applyCode(sides[a], b, (inc: any) => pending[1 - a].push(inc));
    else if (kind === "step") for (let k = 0; k < b; k++) tick(a);
    else if (kind === "both") for (let k = 0; k < a; k++) { tick(0); tick(1); }
    after.push(snap(sides));
  }
  return { name: sc.name, seed: sc.seed, loadouts: sc.loadouts, ops: sc.ops, after };
}

const webCommit = execSync(`git -C "${web}" rev-parse HEAD`).toString().trim();
console.log(`-- GENERATED by tools/parity/gen-spell-scenarios.ts from the StackRivals web code. Do not edit.
return ${lua({ webCommit, scenarios: scenarios.map(run) })}`);
