/**
 * Spell Battle + bot parity fixtures from the REAL StackRivals web code (TypeScript). READ-ONLY on
 * the web repo. The Lua port (StackRivals/Engine/Spells.lua, Bot.lua) must reproduce every value.
 *
 *   bun tools/parity/gen-spell-fixtures.ts <path-to-stackrivals-practice-arena> > tests/fixtures/spells.lua
 *
 * Cases:
 *  - rules fingerprint: every spell (name, cost, target, duration), mana table, cooldown, delivery,
 *    loadouts, bot profiles v1/v2, bot cast styles v1/v2 (read from the source text), time cap;
 *  - classic bot games (both tuning versions, every difficulty): full log + final hash;
 *  - board effects on mid-game boards: bombCells, worstFitPiece, garbage gaps, and the hash after
 *    each effect (clearCells, removeBottomRows, clearBoard, addGarbage, swapActive, replaceNext);
 *  - full Spell Battles bot vs bot (lockstep SpellSim): both logs, casts, mana, invalid casts and
 *    the hash of both boards at checkpoints;
 *  - "human" logs (random moves + random casts incl. invalid ones) vs the bot and vs each other,
 *    run through the web's verifySpellMatch: reasons, scores, hashes;
 *  - tampered logs: every fraud reason verifySpellMatch can give.
 */
const web = process.argv[2];
if (!web) throw new Error("usage: bun gen-spell-fixtures.ts <web repo path>");
const eng = await import(`${web}/src/game/engine/engine.ts`);
const sp = await import(`${web}/src/game/engine/spells.ts`);
const prng = await import(`${web}/src/game/engine/prng.ts`);
const bot = await import(`${web}/src/game/bot/bot.ts`);
const sbot = await import(`${web}/src/game/bot/spell-bot.ts`);
const rules = await import(`${web}/src/lib/match/rules.ts`);
const { INPUT_ACTIONS } = await import(`${web}/src/game/engine/types.ts`);
const fs = await import("node:fs");
const { execSync } = await import("node:child_process");

const lua = (v: unknown): string => {
  if (typeof v === "string") return JSON.stringify(v);
  if (typeof v === "number") return Number.isFinite(v) ? String(v) : v > 0 ? "math.huge" : "-math.huge";
  if (typeof v === "boolean") return String(v);
  if (v === null || v === undefined) return "nil";
  if (Array.isArray(v)) return `{${v.map(lua).join(",")}}`;
  return `{${Object.entries(v as object).map(([k, x]) => `[${JSON.stringify(k)}]=${lua(x)}`).join(",")}}`;
};
const flat = (pairs: [number, number][]) => pairs.flatMap((p) => [p[0], p[1]]);
const V1_MS = bot.BOT_V2_FROM_MS - 86400000; // a match created a day before the v2 switch
const V2_MS = bot.BOT_V2_FROM_MS + 86400000;

// ---------------- fingerprint ----------------
const src = fs.readFileSync(`${web}/src/game/bot/spell-bot.ts`, "utf8");
const objText = (name: string) => {
  const m = new RegExp(`const ${name}[^=]*=\\s*(\\{[\\s\\S]*?\\n\\});`).exec(src);
  if (!m) throw new Error(`can't find ${name}`);
  return Function(`return ${m[1]}`)();
};
const webCommit = execSync(`git -C "${web}" rev-parse HEAD`).toString().trim();
const fingerprint = {
  spells: sp.SPELLS, info: sp.SPELL_INFO, castBase: sp.CAST_BASE, manaMax: sp.MANA_MAX,
  cooldown: sp.CAST_COOLDOWN_TICKS, delivery: sp.DELIVERY_TICKS, defaultLoadout: sp.DEFAULT_LOADOUT,
  mana: [0, 1, 2, 3, 4, 5].map((l) => [0, 1, 3].map((c) => sp.manaForClear(l, c))),
  botLoadouts: sbot.BOT_LOADOUTS, castStyle: objText("CAST_STYLE"), castStyleV1: objText("CAST_STYLE_V1"),
  profiles: bot.botProfiles(V2_MS), profilesV1: bot.botProfiles(V1_MS), v2From: bot.BOT_V2_FROM_MS,
  timeCapMs: rules.DEFAULT_TIME_CAP_MS, garbageCell: eng.GARBAGE_CELL,
};

// ---------------- classic bot games ----------------
const botGames: unknown[] = [];
for (const [ver, ms] of [["v1", V1_MS], ["v2", V2_MS]] as const) {
  for (const d of bot.BOT_DIFFICULTIES) {
    for (let k = 0; k < 2; k++) {
      const seed = `wbot-${ver}-${d}-${k}`;
      const g = bot.generateBotGame(seed, d, 5400, ms);
      botGames.push({ seed, difficulty: d, createdAtMs: ms, untilTick: 5400, log: flat(g.log.inputs), ticks: g.final.tick, hash: eng.hashState(g.final), score: g.final.score });
    }
  }
}

// ---------------- board effects on real mid-game boards ----------------
let rng = prng.hashString("spell-fixtures");
const rand = () => { let r: number; [r, rng] = prng.nextRandom(rng); return r; };
const effects: unknown[] = [];
for (let k = 0; k < 24; k++) {
  const seed = `fx-${k}`;
  const d = bot.BOT_DIFFICULTIES[k % 5];
  const g = bot.generateBotGame(seed, d, 600 + Math.floor(rand() * 3000), V2_MS);
  const st = g.final;
  if (st.gameOver) continue;
  const castTick = Math.floor(rand() * 10000);
  const out: Record<string, unknown> = {
    seed, difficulty: d, untilTick: st.tick, log: flat(g.log.inputs), stateHash: eng.hashState(st),
    bomb: sp.bombCells(st), worst: sp.worstFitPiece(st), castTick, gap: sp.garbageGap(seed, castTick, 10),
    stackHeight: sbot.stackHeight(st),
    after: {
      bomb: eng.hashState(eng.clearCells(st, sp.bombCells(st))),
      lineBlast: eng.hashState(eng.removeBottomRows(st, 2)),
      clearBoard: eng.hashState(eng.clearBoard(st)),
      garbage: eng.hashState(eng.addGarbage(st, 2, sp.garbageGap(seed, castTick, 10))),
      garbage8: eng.hashState(eng.addGarbage(st, 8, 3)),
      swap: eng.hashState(eng.swapActive(st)),
      scramble: eng.hashState(eng.replaceNext(st, sp.worstFitPiece(st))),
      frozen: eng.hashState(eng.tick(st, "frozen")),
      double: eng.hashState(eng.tick(st, "double")),
    },
    // the bot's view of this board: every candidate, best first
    candidates: bot.evaluatePlacements(st).map((c: any) => [c.rotation, c.x, c.score]),
  };
  effects.push(out);
}
const gaps = Array.from({ length: 40 }, (_, i) => { const seed = `gap-${i}`; const t = Math.floor(rand() * 20000); return [seed, t, sp.garbageGap(seed, t, 10)]; });

// ---------------- full Spell Battles ----------------
function sideOut(s: any) {
  return {
    hash: eng.hashState(s.game), score: s.game.score, lines: s.game.lines, tick: s.game.tick, gameOver: s.game.gameOver,
    mana: s.mana, casts: s.casts.map((c: any) => [c.tick, sp.SPELLS.indexOf(c.spell)]),
    invalid: s.invalidCasts.map((c: any) => [c.tick, c.code, c.reason]), logLen: s.log.length,
    freezeUntil: s.freezeUntil, speedUntil: s.speedUntil, blackoutUntil: s.blackoutUntil,
  };
}
const battles: unknown[] = [];
const pairs: [string, string, number][] = [
  ["rookie", "rival", V2_MS], ["challenger", "contender", V2_MS], ["elite", "rival", V2_MS], ["rival", "rival", V2_MS],
  ["contender", "elite", V2_MS], ["rookie", "challenger", V1_MS], ["elite", "contender", V1_MS], ["rival", "rookie", V1_MS],
];
for (const [i, [a, b, ms]] of pairs.entries()) {
  const seed = `battle-${i}-${a}-${b}`;
  const cap = 10800;
  // checkpoints: run step by step
  const sim = new sp.SpellSim(seed, [
    { loadout: sbot.BOT_LOADOUTS[a], log: null, actor: new sbot.SpellBot(seed, a, ms), untilTick: cap },
    { loadout: sbot.BOT_LOADOUTS[b], log: null, actor: new sbot.SpellBot(`${seed}:b`, b, ms), untilTick: cap },
  ]);
  const checkpoints: unknown[] = [];
  for (const at of [600, 3600, 7200]) {
    while (sim.t < at && !sim.done) sim.step();
    checkpoints.push({ t: sim.t, a: sideOut(sim.sides[0]), b: sideOut(sim.sides[1]) });
  }
  const r = sim.run();
  battles.push({
    seed, a, b, createdAtMs: ms, cap, checkpoints, final: { a: sideOut(r.sides[0]), b: sideOut(r.sides[1]) },
    logA: flat(r.sides[0].log), logB: flat(r.sides[1].log), bestCombo: r.bestCombo,
  });
}

// ---------------- "human" logs through verifySpellMatch ----------------
function humanLog(seed: string, loadout: string[], ticks: number, castRate: number, junk = false): [number, number][] {
  // random play driven only by the PRNG; casts at random moments (some invalid on purpose)
  const out: [number, number][] = [];
  let t = 0;
  while (t < ticks) {
    t += 1 + Math.floor(rand() * 9);
    if (t > ticks) break;
    const r = rand();
    if (r < castRate) {
      const s = rand() < 0.85 ? loadout[Math.floor(rand() * 4)]! : sp.SPELLS[Math.floor(rand() * 9)]!;
      out.push([t, sp.castCode(s)]);
    } else if (junk && r < castRate + 0.01) {
      out.push([t, 7 + Math.floor(rand() * 90)]);
    } else {
      const a = Math.floor(rand() * 7);
      out.push([t, a]);
      if (rand() < 0.2) out.push([t, 5]);
    }
  }
  return out;
}
const humans: unknown[] = [];
const loadouts = [sp.DEFAULT_LOADOUT, ["freeze", "clearBoard", "speedUp", "scramble"], ["swap", "bomb", "garbage", "speedUp"], ["clearBoard", "lineBlast", "blackout", "garbage"]];
const verifyOut = (r: any) => ({ ok: r.ok, reasons: r.reasons, score: r.score, lines: r.lines, level: r.level, hash: r.hash, toppedOut: r.toppedOut, mana: r.mana, casts: r.casts, bestCombo: r.bestCombo, invalid: r.invalidCasts.map((c: any) => [c.tick, c.code, c.reason]) });
for (let k = 0; k < 10; k++) {
  const seed = `human-${k}`;
  const lo = loadouts[k % loadouts.length]!;
  const ticks = 1200 + Math.floor(rand() * 9600);
  const log = humanLog(seed, lo, ticks, 0.04 + rand() * 0.08, k % 3 === 0);
  const diff = bot.BOT_DIFFICULTIES[k % 5];
  const ms = k % 2 ? V1_MS : V2_MS;
  const player = { log: { v: 1, seed, startLevel: 1, ticks, inputs: log }, loadout: lo, elapsedMs: ticks * 17 + 5000 };
  const vb = rules.verifySpellMatch({ seed, timeCapMs: 180000, players: [player], bot: { actor: new sbot.SpellBot(seed, diff, ms), loadout: sbot.BOT_LOADOUTS[diff] } });
  const lo2 = loadouts[(k + 1) % loadouts.length]!;
  const ticks2 = 1200 + Math.floor(rand() * 9600);
  const log2 = humanLog(seed, lo2, ticks2, 0.06, false);
  const player2 = { log: { v: 1, seed, startLevel: 1, ticks: ticks2, inputs: log2 }, loadout: lo2, elapsedMs: ticks2 * 17 + 5000 };
  const vh = rules.verifySpellMatch({ seed, timeCapMs: 180000, players: [player, player2] });
  humans.push({
    seed, ticks, loadout: lo, log: flat(log), elapsedMs: player.elapsedMs, difficulty: diff, createdAtMs: ms,
    vsBot: verifyOut(vb.results[0]), bot: sideOut(vb.bot), ticks2, loadout2: lo2, log2: flat(log2), elapsedMs2: player2.elapsedMs,
    vsHuman: [verifyOut(vh.results[0]), verifyOut(vh.results[1])],
    decided: rules.botMatchDecided(vb.results[0].final ?? { score: 0, gameOver: true }, vb.bot.game),
  });
}

// ---------------- tampered logs: every reason ----------------
const tSeed = "tamper";
const base = humanLog(tSeed, sp.DEFAULT_LOADOUT, 3000, 0.05);
const P = (over: any, loadout: unknown = sp.DEFAULT_LOADOUT, elapsedMs = 3000 * 17 + 4000) => ({ log: { v: 1, seed: tSeed, startLevel: 1, ticks: 3000, inputs: base, ...over }, loadout, elapsedMs });
const tamper: Record<string, any> = {
  clean: P({}),
  engine: P({ v: 2 }),
  seed: P({ seed: "other" }),
  startLevel: P({ startLevel: 3 }),
  overCap: P({ ticks: 11000 }),
  tooFast: P({}, sp.DEFAULT_LOADOUT, 20000),
  unordered: P({ inputs: [[10, 0], [5, 1]] }),
  badCode: P({ inputs: [[10, 0], [11, 150]] }),
  afterEnd: P({ inputs: [[10, 0], [3500, 1]] }),
  burst: P({ inputs: [[10, 0], [10, 1], [10, 0], [10, 1], [10, 0]] }),
  loadoutDup: P({}, ["bomb", "bomb", "garbage", "blackout"]),
  loadout3self: P({}, ["bomb", "swap", "freeze", "garbage"]),
  loadoutShort: P({}, ["bomb", "garbage"]),
  castNoMana: P({ inputs: [[10, sp.castCode("garbage")]] }),
  castNotInLoadout: P({ inputs: [[10, sp.castCode("scramble")]] }),
  castCooldown: P({ inputs: [] }),
};
// a log that earns mana, then casts twice inside the cooldown and once after top-out
{
  const g = bot.generateBotGame("tamper", "rival", 3000, V2_MS);
  const ins: [number, number][] = g.log.inputs.slice();
  const t0 = ins[Math.floor(ins.length / 2)]![0] + 1;
  ins.push([t0, sp.castCode("lineBlast")], [t0 + 10, sp.castCode("bomb")]);
  ins.sort((a, b) => a[0] - b[0]);
  tamper.castCooldown = P({ inputs: ins });
}
// moves after the player topped out (a filled board, then more input)
{
  const ins: [number, number][] = [];
  for (let t = 1; t < 400; t += 2) ins.push([t, 5]);
  for (let t = 401; t < 900; t += 3) ins.push([t, 0]);
  tamper.afterTopout = P({ inputs: ins });
}
const tampered: Record<string, unknown> = {};
for (const [name, p] of Object.entries(tamper)) {
  const r = rules.verifySpellMatch({ seed: tSeed, timeCapMs: 180000, players: [p], bot: { actor: new sbot.SpellBot(tSeed, "rookie", V2_MS), loadout: sbot.BOT_LOADOUTS.rookie } });
  tampered[name] = { log: flat(p.log.inputs), v: p.log.v, seed: p.log.seed, startLevel: p.log.startLevel, ticks: p.log.ticks, loadout: p.loadout, elapsedMs: p.elapsedMs, result: verifyOut(r.results[0]) };
}

console.log(`-- GENERATED by tools/parity/gen-spell-fixtures.ts from the StackRivals web code. Do not edit.
return ${lua({ webCommit, fingerprint, botGames, effects, gaps, battles, humans, tampered })}`);
