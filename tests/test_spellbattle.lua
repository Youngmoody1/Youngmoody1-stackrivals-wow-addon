-- Spell Battle vs Bot in the addon (WoW API mock): the live game is exactly the web's lockstep
-- simulation, the match ends correctly (no play or casts after the end), spells only via the
-- spell keys during a live Spell Battle, /reload restores the match exactly. Simulated: a real
-- WoW client is still needed for the look and feel.
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe

local function tocFiles()
  local files = {}
  for line in io.lines(root .. "/StackRivals.toc") do
    if line ~= "" and not line:match("^##") then files[#files + 1] = (line:gsub("\\", "/")) end
  end
  return files
end

local function boot(saved)
  local M = dofile(testdir .. "/wowmock.lua")
  M.install()
  _G.StackRivalsDB = saved
  local ns = {}
  for _, f in ipairs(tocFiles()) do assert(loadfile(root .. "/" .. f))("StackRivals", ns) end
  M.fire("ADDON_LOADED", "StackRivals")
  M.fire("PLAYER_LOGIN")
  return M, ns
end

local function startSpell(M, ns, diff, loadout)
  SlashCmdList.STACKRIVALS("")
  if diff then ns.db.spell.difficulty = diff end
  if loadout then ns.db.spell.loadout = ns.Spells.encodeLoadout(loadout) end
  ns.App:Start("spellbot")
  M.frames_step(241) -- 4 s countdown (web)
  return ns.App.session
end

-- a deterministic "player" that clears lines and casts: the web's spell bot driving the keys
-- (like the web's DEV autoplay), one decision per frame
local function player(ns, sess, seed)
  local bot = ns.Bot.SpellBot.new(seed, "elite")
  return function()
    local sp = sess.spell
    local c = bot:act(sp.me, sp.opp)
    if not c then return end
    local spell = ns.Spells.spellOfCode(c)
    if spell then
      for i, x in ipairs(sp.me.loadout) do if x == spell then sess:press("spell" .. i) end end
    else
      local a = ns.Engine.INPUT_ACTIONS[c + 1]
      sess:press(a); sess:release(a)
    end
  end
end
-- fill a board so the next lock tops out, with a gap in every row (no line can clear)
local function bury(g)
  for y = 2, 21 do for x = 0, 9 do if x ~= y % 10 then g.board[y * 10 + x + 1] = 8 end end end
end

local function verifyLive(ns, sess)
  local S, Bot = ns.Spells, ns.Bot
  local sp = sess.spell
  local res, botSide = S.verifyMatch({ seed = sess.seed, capTicks = 10800,
    players = { { v = 1, seed = sess.seed, startLevel = 1, ticks = sp.me.game.tick, log = sp.me.log, loadout = sp.me.loadout } },
    bot = { actor = Bot.SpellBot.new(sess.seed, sp.difficulty, sp.createdAtMs), loadout = Bot.LOADOUTS[sp.difficulty] } })
  return res[1], botSide
end

describe("Spell Battle vs Bot: live play = the web's verification", function()
  for _, diff in ipairs({ "rookie", "contender", "rival" }) do
    it(diff .. ": your board and the bot's are exactly what the lockstep replay of your log gives", function()
      local M, ns = boot(nil)
      local sess = startSpell(M, ns, diff, { "lineBlast", "bomb", "garbage", "blackout" })
      eq(sess.phase, "playing")
      local step = player(ns, sess, "p-" .. diff)
      for _ = 1, 6000 do
        if sess.phase ~= "playing" then break end
        step(); M.frames_step(1)
      end
      local sp = sess.spell
      for _ = 1, 100 do if not sp.settling then break end; M.frames_step(1) end
      ok(#sp.me.casts + #sp.opp.casts > 0, "spells were cast")
      local r, botSide = verifyLive(ns, sess)
      eq(r.hash, ns.Engine.hashState(sp.me.game), "your board")
      eq(#r.invalidCasts, 0, "no invalid casts are ever logged live")
      eq(r.ok, true, table.concat(r.reasons, ","))
      if sess.phase == "playing" then
        -- mid-match: the bot side matches the replay up to the same tick
        eq(sp.opp.game.tick, sp.me.game.tick)
      else
        eq(ns.Engine.hashState(botSide.game), ns.Engine.hashState(sp.opp.game), "bot board")
      end
    end)
  end
end)

describe("Spell Battle vs Bot: the match ends when it is decided", function()
  it("bot tops out while you lead: VICTORY at once, the timer stops, no input or casts after the end", function()
    local M, ns = boot(nil)
    local sess = startSpell(M, ns, "rookie")
    local sp = sess.spell
    -- push the bot to the top quickly: fill its board (as if it played badly) and give you a lead
    bury(sp.opp.game)
    sp.me.game.score = 5000
    M.frames_step(200)
    eq(sp.opp.game.gameOver, true, "bot topped out")
    eq(sess.phase, "over")
    eq(sp.result.outcome, "win"); eq(sp.result.reason, "decided")
    local t = sp.me.game.tick
    local logLen = #sp.me.log
    sp.me.mana = 20
    sess:press("spell1"); sess:press("hardDrop"); ns.UI.spellTiles[1]:GetScript("OnClick")(ns.UI.spellTiles[1])
    M.frames_step(120)
    eq(sp.me.game.tick, t, "no more ticks"); eq(#sp.me.log, logLen, "nothing logged after the end")
    ok(ns.UI.overTitle:GetText() == "VICTORY", ns.UI.overTitle:GetText())
    eq(ns.db.spell.stats.rookie.wins, 1, "counted once")
    M.frames_step(200)
    eq(ns.db.spell.stats.rookie.wins, 1, "still once")
  end)
  it("bot tops out while you are behind: keep playing ('beat N to win'), then win by passing it", function()
    local M, ns = boot(nil)
    local sess = startSpell(M, ns, "rookie")
    local sp = sess.spell
    bury(sp.opp.game)
    sp.opp.game.score = 900
    M.frames_step(120)
    eq(sp.opp.game.gameOver, true)
    eq(sess.phase, "playing", "not decided while behind")
    ok(ns.UI.spellRival.lead:GetText():find("beat 900 to win"), ns.UI.spellRival.lead:GetText())
    sp.me.game.score = 901
    M.frames_step(2)
    eq(sess.phase, "over"); eq(sp.result.outcome, "win")
  end)
  it("you top out: the bot plays on to 3:00 over a few frames (no hitch), then the result", function()
    local M, ns = boot(nil)
    local sess = startSpell(M, ns, "challenger")
    local sp = sess.spell
    for _ = 1, 400 do
      if sess.phase ~= "playing" then break end
      sess:press("hardDrop"); M.frames_step(1); sess:release("hardDrop")
    end
    eq(sp.me.game.gameOver, true, "you topped out")
    ok(sp.settling or sp.result, "bot still playing or done")
    ok(ns.UI.overTitle:GetText() == "FINISHED" or sp.result, "waiting screen")
    local frames = 0
    while sp.settling and frames < 100 do M.frames_step(1); frames = frames + 1 end
    ok(not sp.settling, "bot finished")
    ok(frames <= 20, "spread over " .. frames .. " frames")
    eq(sp.opp.game.tick == 10800 or sp.opp.game.gameOver, true)
    local r, botSide = verifyLive(ns, sess)
    eq(ns.Engine.hashState(botSide.game), ns.Engine.hashState(sp.opp.game), "same bot result as the web verification")
    eq(sp.result.outcome, (r.score > botSide.game.score) and "win" or (r.score < botSide.game.score and "loss" or "draw"))
    ok(ns.UI.overTitle:GetText() == "VICTORY" or ns.UI.overTitle:GetText() == "DEFEAT" or ns.UI.overTitle:GetText() == "DRAW")
  end)
  it("time cap: 3:00 ends the match for both", function()
    local M, ns = boot(nil)
    local sess = startSpell(M, ns, "rookie")
    local sp = sess.spell
    for _ = 1, 10800 / 8 + 10 do
      if sess.phase ~= "playing" then break end
      if sp.me.game.tick % 30 == 0 then sess:press("hardDrop"); sess:release("hardDrop") end
      M.frames_step(1, 8 / 60)
    end
    if not sp.me.game.gameOver then
      eq(sp.me.game.tick, 10800); eq(sp.result.reason, "time")
    end
    eq(sess.phase, "over")
  end)
end)

describe("Spell Battle vs Bot: casting", function()
  it("spell keys (Q E R F and 1-4) cast the loadout slots; refused casts say why and log nothing", function()
    local M, ns = boot(nil)
    local sess = startSpell(M, ns, "rookie", { "lineBlast", "bomb", "garbage", "blackout" })
    local sp = sess.spell
    local down = ns.UI.keys:GetScript("OnKeyDown")
    local up = ns.UI.keys:GetScript("OnKeyUp")
    down(ns.UI.keys, "Q"); up(ns.UI.keys, "Q"); M.frames_step(1)
    eq(#sp.me.casts, 0, "no mana: nothing cast")
    eq(#sp.me.invalidCasts, 0, "and nothing logged")
    sp.me.mana = 20
    down(ns.UI.keys, "Q"); up(ns.UI.keys, "Q"); M.frames_step(1)
    eq(sp.me.casts[1].spell, "lineBlast"); eq(sp.me.mana, 15)
    down(ns.UI.keys, "R"); up(ns.UI.keys, "R"); M.frames_step(1)
    eq(#sp.me.casts, 1, "cooldown: refused")
    M.frames_step(180)
    down(ns.UI.keys, "3"); up(ns.UI.keys, "3"); M.frames_step(1)
    eq(sp.me.casts[2].spell, "garbage", "number keys work too")
    M.frames_step(100)
    ok(#sp.opp.hits > 0 and sp.opp.hits[#sp.opp.hits].spell == "garbage", "garbage landed on the bot 1.5 s later")
  end)
  it("outside a Spell Battle the spell keys do nothing (and outside a run they belong to WoW)", function()
    local M, ns = boot(nil)
    SlashCmdList.STACKRIVALS("")
    ns.App:Start("blitz"); M.frames_step(181)
    local down = ns.UI.keys:GetScript("OnKeyDown")
    down(ns.UI.keys, "Q")
    eq(ns.App.session.spell, nil)
    ns.App.session:finish("time"); M.frames_step(70)
    down(ns.UI.keys, "Q"); eq(ns.UI.keys._prop, true, "game over: Q goes to WoW")
  end)
  it("combat pauses both boards; nothing moves until you resume", function()
    local M, ns = boot(nil)
    local sess = startSpell(M, ns, "rival")
    M.frames_step(60)
    local sp = sess.spell
    local t1, t2 = sp.me.game.tick, sp.opp.game.tick
    M.combat = true; M.fire("PLAYER_REGEN_DISABLED"); M.frames_step(300)
    eq(sess.phase, "paused"); eq(sp.me.game.tick, t1); eq(sp.opp.game.tick, t2)
    M.combat = false; M.fire("PLAYER_REGEN_ENABLED"); ns.App:Resume(); M.frames_step(200)
    ok(sp.me.game.tick > t1 and sp.opp.game.tick == sp.me.game.tick)
  end)
end)

describe("Spell Battle vs Bot: /reload and saved data", function()
  it("a match interrupted by /reload is rebuilt exactly (both boards, mana, pending spells)", function()
    local M, ns = boot(nil)
    local sess = startSpell(M, ns, "elite", { "bomb", "clearBoard", "garbage", "speedUp" })
    local step = player(ns, sess, "reload")
    for _ = 1, 1500 do if sess.phase ~= "playing" then break end; step(); M.frames_step(1) end
    if sess.phase ~= "playing" then return end
    local sp = sess.spell
    local me, bot = ns.Engine.hashState(sp.me.game), ns.Engine.hashState(sp.opp.game)
    local mana, omana, pend = sp.me.mana, sp.opp.mana, #sp.pendingMe + #sp.pendingOpp
    M.fire("PLAYER_LOGOUT")
    local saved = StackRivalsDB
    ok(saved.suspended and saved.suspended.mode == "spellbot", "saved")
    local M2, ns2 = boot(saved)
    SlashCmdList.STACKRIVALS("")
    ns2.App:ContinueSuspended()
    local s2 = ns2.App.session
    ok(s2 and s2.spell, "restored")
    eq(ns2.Engine.hashState(s2.spell.me.game), me); eq(ns2.Engine.hashState(s2.spell.opp.game), bot)
    eq(s2.spell.me.mana, mana); eq(s2.spell.opp.mana, omana); eq(#s2.spell.pendingMe + #s2.spell.pendingOpp, pend)
    eq(s2.phase, "paused")
    -- and it plays on identically to an uninterrupted match
    ns2.App:Resume(); M2.frames_step(400)
    local r, botSide = verifyLive(ns2, s2)
    eq(r.hash, ns2.Engine.hashState(s2.spell.me.game))
  end)
  it("garbled saved Spell Battle data never breaks loading", function()
    for _, raw in ipairs({
      { spell = { loadout = "9999", difficulty = "god", stats = { rival = { wins = "x" } } } },
      { spell = "nope", suspended = { mode = "spellbot", seed = "a", slog = "1,2 3,4", loadout = "0000", difficulty = "rival", ticks = 5 } },
      { suspended = { mode = "spellbot", seed = 5 } },
    }) do
      local M, ns = boot(raw)
      SlashCmdList.STACKRIVALS("")
      ok(ns.Spells.decodeLoadout(ns.db.spell.loadout), "valid loadout")
      ns.App:ContinueSuspended()
      ns.App:Start("spellbot"); M.frames_step(250)
      eq(ns.App.session.phase, "playing")
    end
  end)
end)

describe("Pick Spells", function()
  it("clicking a spell swaps it into its group; the loadout always stays 2 self + 2 rival", function()
    local M, ns = boot(nil)
    SlashCmdList.STACKRIVALS("")
    ns.UI:ShowSheet("spell")
    ok(ns.UI.spellSheet:IsShown())
    for _, b in ipairs(ns.UI.spellCards) do b:GetScript("OnClick")(b) end
    local lo = ns.Spells.decodeLoadout(ns.db.spell.loadout)
    ok(ns.Spells.isValidLoadout(lo))
    eq(lo[1] .. lo[2], "swapclearBoard", "the last two self spells clicked")
    eq(lo[3] .. lo[4], "speedUpscramble", "the last two new rival spells clicked")
    ns.UI.diffButtons.elite:GetScript("OnClick")(ns.UI.diffButtons.elite)
    eq(ns.db.spell.difficulty, "elite")
    ns.UI.spellStart:GetScript("OnClick")(ns.UI.spellStart)
    local s = ns.App.session
    eq(s.mode.key, "spellbot"); eq(s.spell.difficulty, "elite"); eq(s.spell.me.loadout[1], "swap")
  end)
end)

return H
