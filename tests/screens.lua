-- Builds every StackRivals screen in the WoW API mock, deterministically. Used by the layout
-- tests (overlap / bounds checks) and by tools/render_preview.py (developer previews).
local root, testdir = ...

local S = {}

local function tocFiles()
  local files = {}
  for line in io.lines(root .. "/StackRivals.toc") do
    if line ~= "" and not line:match("^##") then files[#files + 1] = (line:gsub("\\", "/")) end
  end
  return files
end

local function boot()
  math.randomseed(7)
  local M = dofile(testdir .. "/wowmock.lua")
  M.install()
  UIParent:SetSize(1920, 1080)
  _G.StackRivalsDB = { seenHelp = true }
  local ns = {}
  for _, f in ipairs(tocFiles()) do assert(loadfile(root .. "/" .. f))("StackRivals", ns) end
  M.fire("ADDON_LOADED", "StackRivals")
  M.fire("PLAYER_LOGIN")
  return M, ns
end

-- A few finished runs so menus and records have real numbers.
local function seedRecords(ns)
  local DB = ns.DB
  local today = ns.App:Today()
  for _, r in ipairs({ { "blitz", 18450, 31 }, { "blitz", 12900, 22 }, { "blitz", 9300, 17 }, { "classic", 41250, 64 }, { "daily", 15780, 27 } }) do
    DB.recordRun(ns.db, r[1], { score = r[2], lines = r[3], level = 1 + math.floor(r[3] / 10), clears = { quad = 2 } }, 120, today, nil, today)
  end
end

-- Mid-game board: a ragged stack with a few gaps.
local function fillBoard(s)
  local w = s.config.width
  local rows = s.config.height + s.config.hiddenRows
  local heights = { 3, 5, 4, 6, 2, 0, 5, 7, 6, 4 }
  local k = 0
  for x = 0, w - 1 do
    for h = 1, heights[x + 1] do
      k = k + 1
      local y = rows - h
      if (x * 7 + h * 3) % 11 ~= 0 then s.board[y * w + x + 1] = (k % 7) + 1 end
    end
  end
end

local function play(M, ns, mode)
  ns.App:Start(mode)
  M.frames_step(181)
  local s = ns.App.session.state
  fillBoard(s)
  -- a little real play so hold / queue / score are populated
  ns.App.session:press("hold"); M.frames_step(2)
  ns.App.session:release("hold")
  for _ = 1, 3 do ns.App.session:press("left"); M.frames_step(2); ns.App.session:release("left") end
  M.frames_step(40)
  s.score, s.lines, s.level = s.score + 12650, 23, 3
  ns.UI.dirty = true
  M.frames_step(1)
  return s
end

-- Two simulated clients for the duel screens (Alice's view is captured).
local function duelPair()
  local NS = assert(loadfile(testdir .. "/netsim.lua"))(root, testdir)
  local net = NS.new({ seed = 5 })
  local a = net.add({ name = "Alice", guild = "G", saved = { seenHelp = true } })
  local b = net.add({ name = "Bob", guild = "G", saved = { seenHelp = true } })
  a.env.UIParent:SetSize(1920, 1080)
  return net, a, b, NS
end

-- Spell Battle: the web's spell bot plays your side through the real keys (like the web's DEV autoplay)
local function spellAutoplay(M, ns, frames)
  local sess = ns.App.session
  local bot = ns.Bot.SpellBot.new("preview-player", "elite")
  for _ = 1, frames do
    if sess.phase ~= "playing" then break end
    local sp = sess.spell
    local c = bot:act(sp.me, sp.opp)
    if c then
      local spell = ns.Spells.spellOfCode(c)
      if spell then
        for i, x in ipairs(sp.me.loadout) do if x == spell then sess:press("spell" .. i) end end
      else
        local a = ns.Engine.INPUT_ACTIONS[c + 1]
        sess:press(a); sess:release(a)
      end
    end
    M.frames_step(1)
  end
end

S.list = {
  { "1-menu", "Mode menu", function()
    local M, ns = boot(); seedRecords(ns); SlashCmdList.STACKRIVALS(""); M.frames_step(1); return M, ns
  end },
  { "1b-menu-first-time", "Mode menu - first time", function()
    local M, ns = boot(); ns.db.seenHelp = false; SlashCmdList.STACKRIVALS(""); M.frames_step(1); return M, ns
  end },
  { "1c-menu-continue", "Mode menu - a run to continue", function()
    local M, ns = boot(); seedRecords(ns)
    ns.db.suspended = { mode = "classic", log = "", playSeconds = 95, date = ns.App:Today() } -- as left by /reload mid-run
    SlashCmdList.STACKRIVALS(""); M.frames_step(1); return M, ns
  end },
  { "2-how-to-play", "How to play", function()
    local M, ns = boot(); ns.db.seenHelp = false; SlashCmdList.STACKRIVALS(""); ns.UI:ShowSheet("help"); M.frames_step(1); return M, ns
  end },
  { "2b-first-run", "First run - countdown shows the controls", function()
    local M, ns = boot(); ns.db.seenHelp = false; SlashCmdList.STACKRIVALS(""); ns.UI.modeButtons.blitz:Click(); M.frames_step(70); return M, ns
  end },
  { "3-classic", "Classic - mid game", function()
    local M, ns = boot(); seedRecords(ns); play(M, ns, "classic")
    ns.UI:OnEvent({ kind = "clear", a = 2, b = { points = 950, combo = 1 } }); M.frames_step(1); return M, ns
  end },
  { "3b-quad", "Quad, back-to-back - the biggest callout", function()
    local M, ns = boot(); seedRecords(ns); play(M, ns, "classic")
    ns.UI:OnEvent({ kind = "clear", a = 4, b = { points = 1800, combo = 2, backToBack = true } }); M.frames_step(3); return M, ns
  end },
  { "4-blitz", "Blitz 2:00 - timer", function()
    local M, ns = boot(); seedRecords(ns); play(M, ns, "blitz"); M.frames_step(1); return M, ns
  end },
  { "4b-blitz-last-seconds", "Blitz - last seconds", function()
    local M, ns = boot(); seedRecords(ns); play(M, ns, "blitz")
    local sess = ns.App.session
    sess.state.tick = sess.mode.limitTicks - 4 * 60 + 1 -- the 4-second mark (no play needed)
    ns.UI.dirty = true; M.frames_step(1); return M, ns
  end },
  { "5-paused-combat", "Paused by combat (window back after the fight)", function()
    local M, ns = boot(); play(M, ns, "classic")
    M.fire("PLAYER_REGEN_DISABLED"); M.fire("PLAYER_REGEN_ENABLED"); M.frames_step(1); return M, ns
  end },
  { "6-game-over", "Blitz finished - new best", function()
    local M, ns = boot(); seedRecords(ns); M.inGuild = true
    play(M, ns, "blitz"); ns.App.session.state.score = 21300
    ns.App.session:finish("time"); M.frames_step(70); return M, ns
  end },
  { "7-settings", "Settings", function()
    local M, ns = boot(); SlashCmdList.STACKRIVALS("settings"); M.frames_step(1); return M, ns
  end },
  { "9-duel-sheet", "Duel - find players", function()
    local net, a, b = duelPair()
    net.add({ name = "Carol", guild = "G", saved = { seenHelp = true } })
    a.env.SlashCmdList.STACKRIVALS("")
    a.ns.UI:ShowSheet("duel")
    a.ns.Duel.findPlayers(); net.step(60)
    a.ns.UI:RefreshDuelSheet()
    return a.M, a.ns, a.env.StackRivalsFrame
  end },
  { "10-duel-lobby", "Duel - lobby (Ready)", function()
    local net, a, b = duelPair()
    a.ns.Duel.challenge("Bob"); net.step(30); b.ns.Duel.accept(); net.step(30)
    b.ns.Duel.ready(); net.step(30)
    return a.M, a.ns, a.env.StackRivalsFrame
  end },
  { "11-duel-playing", "Duel - live rival score", function()
    local net, a, b, NS = duelPair()
    a.ns.Duel.challenge("Bob"); net.step(30); b.ns.Duel.accept(); net.step(30)
    a.ns.Duel.ready(); b.ns.Duel.ready(); net.step(30)
    local pa, pb = NS.autoplay(a, "fast"), NS.autoplay(b, "slow")
    for _ = 1, 1800 do pa(); pb(); net.step(1) end
    return a.M, a.ns, a.env.StackRivalsFrame
  end },
  { "12-duel-result", "Duel - result (peer-checked)", function()
    local net, a, b, NS = duelPair()
    a.ns.Duel.challenge("Bob"); net.step(30); b.ns.Duel.accept(); net.step(30)
    a.ns.Duel.ready(); b.ns.Duel.ready(); net.step(30)
    local pa, pb = NS.autoplay(a, "fast"), NS.autoplay(b, "slow")
    for _ = 1, 7200 + 900 do pa(); pb(); net.step(1) end
    return a.M, a.ns, a.env.StackRivalsFrame
  end },
  { "13-spell-pick", "Spell Battle - Pick Spells", function()
    local M, ns = boot(); SlashCmdList.STACKRIVALS(""); ns.UI:ShowSheet("spell"); M.frames_step(1); return M, ns
  end },
  { "14-spell-battle", "Spell Battle vs Bot - mid match", function()
    local M, ns = boot(); SlashCmdList.STACKRIVALS("")
    ns.db.spell.difficulty = "contender"
    ns.App:Start("spellbot"); M.frames_step(241)
    spellAutoplay(M, ns, 2400)
    local sp = ns.App.session.spell
    sp.me.mana = math.max(sp.me.mana, 9) -- show castable and not-yet-castable spells side by side
    sp.lastCastTick = nil
    sp.me.lastCastTick = sp.me.game.tick - 70 -- a cast 1.2 s ago: the cooldown curtain and seconds
    ns.UI.dirty = true; M.frames_step(1)
    return M, ns
  end },
  { "15-spell-victory", "Spell Battle vs Bot - Victory (bot topped out, you ahead)", function()
    local M, ns = boot(); SlashCmdList.STACKRIVALS("")
    ns.App:Start("spellbot"); M.frames_step(241)
    spellAutoplay(M, ns, 900)
    local sp = ns.App.session.spell
    for y = 2, 21 do for x = 0, 9 do if x ~= y % 10 then sp.opp.game.board[y * 10 + x + 1] = 8 end end end
    sp.me.game.score = sp.me.game.score + 4000
    M.frames_step(200)
    return M, ns
  end },
  { "16-spell-finishing", "Spell Battle vs Bot - you topped out, the bot plays on", function()
    local M, ns = boot(); SlashCmdList.STACKRIVALS("")
    ns.App:Start("spellbot"); M.frames_step(241)
    local sess = ns.App.session
    for _ = 1, 400 do
      if sess.phase ~= "playing" then break end
      sess:press("hardDrop"); M.frames_step(1); sess:release("hardDrop")
    end
    return M, ns
  end },
  { "17-spell-duel-lobby", "Spell Battle duel - lobby with your spells", function()
    local net, a, b = duelPair()
    a.ns.Duel.challenge("Bob", "s180"); net.step(30); b.ns.Duel.accept(); net.step(30)
    b.ns.Duel.ready(); net.step(30)
    a.ns.UI:RefreshPhase()
    return a.M, a.ns, a.env.StackRivalsFrame
  end },
  { "18-spell-duel-playing", "Spell Battle duel - live (rival's spells land on your board)", function()
    local net, a, b = duelPair()
    a.ns.Duel.challenge("Bob", "s180"); net.step(30); b.ns.Duel.accept(); net.step(30)
    a.ns.Duel.ready(); b.ns.Duel.ready(); net.step(30)
    local function player(c, seed, diff)
      local bot = c.ns.Bot.SpellBot.new(seed, diff)
      return function()
        local s = c.ns.App.session
        if not (s and s.spell and s.phase == "playing") then return end
        local code = bot:act(s.spell.me, { game = { score = s.duel.rival_.score or 0 } })
        if not code then return end
        local spell = c.ns.Spells.spellOfCode(code)
        if spell then for i, x in ipairs(s.spell.me.loadout) do if x == spell then s:press("spell" .. i) end end
        else local k = c.ns.Engine.INPUT_ACTIONS[code + 1]; s:press(k); s:release(k) end
      end
    end
    local pa, pb = player(a, "sa", "elite"), player(b, "sb", "rival")
    for _ = 1, 2400 do pa(); pb(); net.step(1) end
    return a.M, a.ns, a.env.StackRivalsFrame
  end },
  { "19-spell-duel-rival-paused", "Spell Battle duel - the rival is in combat: both runs wait", function()
    local net, a, b = duelPair()
    a.ns.Duel.challenge("Bob", "s180"); net.step(30); b.ns.Duel.accept(); net.step(30)
    a.ns.Duel.ready(); b.ns.Duel.ready(); net.step(30)
    net.step(600)
    b.M.combat = true; b.M.fire("PLAYER_REGEN_DISABLED")
    net.step(120)
    a.ns.UI:RefreshPhase()
    return a.M, a.ns, a.env.StackRivalsFrame
  end },
  { "8-records", "Records", function()
    local M, ns = boot(); seedRecords(ns); SlashCmdList.STACKRIVALS(""); ns.UI:ShowSheet("records"); M.frames_step(1); return M, ns
  end },
}

return S
