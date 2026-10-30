/**
 * Reproduces the two Spell Battle live-loop findings with the web's REAL code (read-only).
 *
 *   bun tools/parity/web-live-loop-repro.ts <web repo>
 *
 * `liveMatch` follows src/components/game/VersusGame.tsx step by step (the Spell Battle block of
 * the frame loop + advanceOpp, with the bot as opponent): per tick, incoming spells land on the
 * player, the player's inputs are applied (break after a top-out), then the player's gravity step,
 * then advanceOpp(player tick); when the player's run ends, advanceOpp(capTicks). The result is
 * compared with the server's verifySpellMatch on the same log.
 */
const web = process.argv[2];
if (!web) throw new Error("usage: bun web-live-loop-repro.ts <web repo>");
const sp = await import(`${web}/src/game/engine/spells.ts`);
const eng = await import(`${web}/src/game/engine/engine.ts`);
const sbot = await import(`${web}/src/game/bot/spell-bot.ts`);
const rules = await import(`${web}/src/lib/match/rules.ts`);

const CAP = 10800;
type Human = (tick: number, side: any) => number[];

function liveMatch(seed: string, diff: string, ms: number, loadout: string[], human: Human) {
  let me = sp.createSide(seed, loadout);
  let o = sp.createSide(seed, sbot.BOT_LOADOUTS[diff]);
  const actor = new sbot.SpellBot(seed, diff, ms);
  let pendingMe: any[] = [], pendingOpp: any[] = [];
  let loggedAfterTopout: { tick: number; code: number } | null = null;
  const advanceOpp = (upTo: number) => {
    let guard = 0;
    while (!o.game.gameOver && o.game.tick < Math.min(upTo, CAP) && guard++ < 20000) {
      const t = o.game.tick;
      const due = pendingOpp.filter((x) => x.at <= t);
      if (due.length) { pendingOpp = pendingOpp.filter((x) => x.at > t); for (const inc of due) o = sp.receive(o, inc); }
      for (let k = 0; k < 2 && !o.game.gameOver; k++) {
        const c = actor.act(o, me);
        if (c === null) break;
        o = sp.applyCode(o, c, (i: any) => pendingMe.push(i));
      }
      if (!o.game.gameOver) o = sp.stepSide(o);
    }
  };
  while (true) {
    const t = me.game.tick;
    const due = pendingMe.filter((x) => x.at <= t);
    if (due.length) { pendingMe = pendingMe.filter((x) => x.at > t); for (const inc of due) me = sp.receive(me, inc); }
    const overBeforeInputs = me.game.gameOver;
    for (const code of human(t, me)) {
      const before = me.log.length;
      me = sp.applyCode(me, code, (i: any) => pendingOpp.push(i));
      if (overBeforeInputs && me.log.length > before && !loggedAfterTopout) loggedAfterTopout = { tick: t, code };
      if (me.game.gameOver) break;
    }
    if (!me.game.gameOver) me = sp.stepSide(me);
    advanceOpp(me.game.tick);
    const s = me.game;
    if (s.gameOver || s.tick >= CAP || rules.botMatchDecided(s, o.game)) break;
  }
  advanceOpp(CAP); // after the player's run: f.lockstep -> upTo = capTicks
  const v = rules.verifySpellMatch({
    seed, timeCapMs: 180000,
    players: [{ log: { v: 1, seed, startLevel: 1, ticks: me.game.tick, inputs: me.log }, loadout, elapsedMs: me.game.tick * 17 + 10000 }],
    bot: { actor: new sbot.SpellBot(seed, diff, ms), loadout: sbot.BOT_LOADOUTS[diff] },
  });
  return { me, o, v, loggedAfterTopout };
}

const V2 = Date.parse("2026-10-29T12:00:00Z");

// Quick mode: the two known cases from the search below (seconds instead of minutes).
//   QUICK=1 bun tools/parity/web-live-loop-repro.ts <web repo>
if (process.env.QUICK) {
  const r1 = liveMatch("final-tick-1132", "elite", V2, sp.DEFAULT_LOADOUT, (t) => (t % 20 === 0 ? [5] : []));
  console.log(`1. final tick: seed "final-tick-1132", bot elite: live bot score ${r1.o.game.score}, server bot score ${r1.v.bot!.game.score}`);
  const me = new sbot.SpellBot("topout-6:me", "rookie", V2);
  const r2 = liveMatch("topout-6", "rival", V2, sp.DEFAULT_LOADOUT, (t, side) => {
    const c = side.game.gameOver ? null : me.act(side, { game: { score: 0 } } as any);
    return [c !== null && c < 100 ? c : 2];
  });
  console.log(`2. input after incoming top-out: seed "topout-6", bot rival: logged after top-out ${JSON.stringify(r2.loggedAfterTopout)}, server reasons [${r2.v.results[0]!.reasons.join(", ")}]`);
  process.exit(0);
}

// ---- Finding 1: the bot's actions at tick 10800 count on the server, not live ----
// A player who drops pieces straight down tops out early; the bot plays on to 3:00.
console.log("== 1. final tick (bot acts at t = capTicks on the server only) ==");
let found1 = 0, boards = 0;
const want = Number(process.env.SCORE_DIFF ?? "1");
for (let k = 0; k < 2000 && found1 < 2; k++) {
  for (const diff of ["rival", "elite", "contender"]) {
    const seed = `final-tick-${k}`;
    const r = liveMatch(seed, diff, V2, sp.DEFAULT_LOADOUT, (t) => (t % 20 === 0 ? [5] : []));
    const live = r.o.game.score, server = r.v.bot!.game.score;
    if (eng.hashState(r.o.game) !== eng.hashState(r.v.bot!.game)) boards++;
    if (want ? live !== server : eng.hashState(r.o.game) !== eng.hashState(r.v.bot!.game)) {
      found1++;
      console.log(`seed "${seed}", bot ${diff}, tuning v2, player drops a piece every 20 ticks:`);
      console.log(`  live bot: tick ${r.o.game.tick}, score ${live}, hash ${eng.hashState(r.o.game)}`);
      console.log(`  server bot: tick ${r.v.bot!.game.tick}, score ${server}, hash ${eng.hashState(r.v.bot!.game)}`);
      console.log(`  player score ${r.v.results[0]!.score} -> outcome live ${live > r.v.results[0]!.score ? "loss" : "?"} / server ${server > r.v.results[0]!.score ? "loss" : "?"}`);
      break;
    }
  }
}
console.log(`  (boards differed in ${boards} matches searched; score differences shown above)`);
if (!found1) console.log("  (no score difference found in this search)");

// ---- Finding 2: an input in the tick where incoming garbage tops the player out is logged ----
console.log("\n== 2. input logged after an incoming top-out -> inputs_after_topout for an honest log ==");
let found2 = 0;
for (let k = 0; k < 600 && found2 < 2; k++) {
  const seed = `topout-${k}`;
  // a real player model: the web's own Rookie spell bot plays the moves, and whenever it has nothing
  // to do this tick it "mashes" a rotate key (players do press keys while the stack is high);
  // the Rival bot's garbage eventually tops it out
  const me = new sbot.SpellBot(`${seed}:me`, "rookie", V2);
  const r = liveMatch(seed, "rival", V2, sp.DEFAULT_LOADOUT, (t, side) => {
    const c = side.game.gameOver ? null : me.act(side, { game: { score: 0 } } as any);
    return [c !== null && c < 100 ? c : 2];
  });
  if (r.loggedAfterTopout) {
    found2++;
    console.log(`seed "${seed}", bot rival, tuning v2, player presses a key every tick:`);
    console.log(`  incoming garbage topped the player out at tick ${r.loggedAfterTopout.tick}; the input ${r.loggedAfterTopout.code} at that tick was still logged`);
    console.log(`  server verifySpellMatch reasons: [${r.v.results[0]!.reasons.join(", ")}]  ok = ${r.v.results[0]!.ok}`);
  }
}
if (!found2) console.log("  (not found in this search)");
