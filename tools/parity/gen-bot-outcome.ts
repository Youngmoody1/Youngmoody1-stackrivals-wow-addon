/**
 * vs-Bot win rule (web ef71158 "first to top out loses", checked at 8ddaad7), from the web's REAL
 * code, read-only on the web repo. The Lua port (Spells.botOutcome / botMatchEndTick /
 * botMatchDecided / botResult) must reproduce every value.
 *
 *   bun tools/parity/gen-bot-outcome.ts <web repo> > tests/fixtures/bot_outcome.lua
 *
 *  - rules: botOutcome / botMatchEndTick / botMatchDecided on every combination of top-out (none,
 *    player, bot, both), tick order (first, same tick, later), scores (higher, lower, equal),
 *    forfeit and the time cap;
 *  - matches: full Spell Battles vs all 5 bot levels and players that top out early, play well, stop
 *    early without a top-out (a disconnect), or play to the cap. The result is computed exactly like
 *    src/lib/match.server.ts: the bot's full run decides who was first; the bot is shown at the end
 *    tick (verifySpellMatch with bot.untilTick).
 */
const web = process.argv[2];
if (!web) throw new Error("usage: bun gen-bot-outcome.ts <web repo>");
const rules = await import(`${web}/src/lib/match/rules.ts`);
const sp = await import(`${web}/src/game/engine/spells.ts`);
const eng = await import(`${web}/src/game/engine/engine.ts`);
const sbot = await import(`${web}/src/game/bot/spell-bot.ts`);
const { execSync } = await import("node:child_process");
const webCommit = execSync(`git -C ${web} rev-parse HEAD`).toString().trim();
const lua = (v: unknown): string => {
  if (typeof v === "string") return JSON.stringify(v);
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  if (v === null || v === undefined) return "nil";
  if (Array.isArray(v)) return `{${v.map(lua).join(",")}}`;
  return `{${Object.entries(v as object).map(([k, x]) => `[${JSON.stringify(k)}]=${lua(x)}`).join(",")}}`;
};
const CAP = 10800;
const V2 = Date.parse("2026-10-29T12:00:00Z");

// ---- 1. the rule functions on every combination ----
const cases: unknown[] = [];
const tickSets: [number, number][] = [[1000, 2000], [2000, 1000], [1500, 1500], [CAP, CAP], [CAP, 2000], [2000, CAP], [3000, CAP]];
for (const [mt, bt] of tickSets) {
  for (const meTop of [false, true]) for (const botTop of [false, true]) for (const [ms, bs] of [[500, 300], [300, 500], [400, 400]]) for (const forfeited of [false, true]) {
    const me = { score: ms, toppedOut: meTop, ticks: mt, forfeited };
    const bot = { score: bs, toppedOut: botTop, ticks: bt };
    cases.push({
      me, bot,
      outcome: rules.botOutcome(me, bot),
      endTick: rules.botMatchEndTick(me, bot, CAP),
      decided: rules.botMatchDecided({ gameOver: meTop }, { gameOver: botTop }),
    });
  }
}

// ---- 2. full matches, the server's way ----
type Style = "dropper" | "player" | "early-stop" | "idle";
function playerLog(seed: string, diff: string, style: Style) {
  // the player is the web's own spell bot (another seed), or a key masher that hard-drops
  const meActor = style === "dropper"
    ? { act: (s: any) => (s.game.gameOver ? null : (s.game.tick % 7 === 0 ? 5 : null)) }
    : style === "idle"
      ? { act: () => null }
      : new sbot.SpellBot(`${seed}:me`, "rookie", V2);
  const sim = new sp.SpellSim(seed, [
    { loadout: sp.DEFAULT_LOADOUT, log: null, actor: meActor, untilTick: CAP },
    { loadout: sbot.BOT_LOADOUTS[diff], log: null, actor: new sbot.SpellBot(seed, diff, V2), untilTick: CAP },
  ]);
  const r = sim.run();
  const me = r.sides[0];
  let inputs: [number, number][] = me.log;
  let ticks: number = me.game.tick;
  if (style === "early-stop") {
    // the run stops at tick 3000 without a top-out (a disconnect): never an automatic win
    ticks = Math.min(ticks, 3000);
    inputs = inputs.filter((x: [number, number]) => x[0] <= ticks);
  }
  return { log: { v: 1, seed, startLevel: 1, ticks, inputs }, loadout: sp.DEFAULT_LOADOUT, elapsedMs: ticks * 17 + 5000 };
}
const flat = (pairs: [number, number][]) => pairs.flatMap((p) => [p[0], p[1]]);
const matches: unknown[] = [];
for (const diff of ["rookie", "challenger", "contender", "elite", "rival"]) {
  for (const style of ["dropper", "player", "early-stop", "idle"] as Style[]) {
    for (const k of [1, 2]) {
      const seed = `bo-${diff}-${style}-${k}`;
      const p = playerLog(seed, diff, style);
      const full = rules.verifySpellMatch({ seed, timeCapMs: 180000, players: [p], bot: { actor: new sbot.SpellBot(seed, diff, V2), loadout: sbot.BOT_LOADOUTS[diff] } });
      const v = full.results[0]!;
      const fg = full.bot!.game;
      const meEnd = { score: v.score, toppedOut: v.toppedOut, ticks: v.final?.tick ?? 0 };
      const botEnd = { score: fg.score, toppedOut: fg.gameOver, ticks: fg.tick };
      const endTick = rules.botMatchEndTick(meEnd, botEnd, CAP);
      let shown = fg;
      if (endTick < fg.tick) {
        shown = rules.verifySpellMatch({ seed, timeCapMs: 180000, players: [p], bot: { actor: new sbot.SpellBot(seed, diff, V2), loadout: sbot.BOT_LOADOUTS[diff], untilTick: endTick } }).bot!.game;
      }
      matches.push({
        seed, difficulty: diff, style, createdAtMs: V2, ticks: p.log.ticks, log: flat(p.log.inputs),
        me: meEnd, bot: botEnd, endTick, outcome: rules.botOutcome(meEnd, botEnd),
        shown: { score: shown.score, tick: shown.tick, gameOver: shown.gameOver, hash: eng.hashState(shown) },
      });
    }
  }
}

console.log(`-- GENERATED by tools/parity/gen-bot-outcome.ts from the StackRivals web code. Do not edit.
return ${lua({ webCommit, cases, matches })}`);
