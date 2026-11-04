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


-- Loot Duel previews: a simulated party / raid of n (n > 5 = raid), every client runs the addon.
local LOOT_CLS = { "WARRIOR", "SHAMAN", "MAGE", "ROGUE", "PRIEST", "DRUID", "HUNTER", "WARLOCK", "PALADIN" }
local LOOT_NAMES = { "Lead", "Ann", "Ben", "Cid", "Dee", "Eve", "Fay", "Gus", "Hal", "Ivy", "Jon", "Kim", "Lou", "Max", "Ned",
  "Oda", "Pia", "Quin", "Rex", "Sue", "Tam", "Uma", "Vic", "Wes", "Xan", "Yara", "Zed", "Abe", "Bea", "Cal", "Dot", "Eli",
  "Flo", "Gil", "Hux", "Ida", "Jem", "Kai", "Liv", "Mo" }
local function lootGroup(seed, n)
  local _, _, _, NS = duelPair()
  local net = NS.new({ seed = seed })
  local list = {}
  for i = 1, n do
    list[i] = net.add({ name = LOOT_NAMES[i], group = "R", raid = n > 5, lead = (i == 1), class = LOOT_CLS[(i - 1) % #LOOT_CLS + 1], saved = { seenHelp = true } })
    list[i].env.UIParent:SetSize(1920, 1080)
  end
  net.step(30)
  return net, list
end
--- Invite players 1..k (or `inv`), answers: true = join, false = pass, nil = no answer yet.
local function lootInvite(net, list, k, answer)
  local names = {}
  for i = 1, k do names[i] = list[i].name end
  list[1].ns.LootDuel.create(19019, "l060", names); net.step(60 * 4)
  for i = 2, k do
    local a = answer and answer(i)
    if a ~= nil then list[i].ns.LootDuel.answer(a) end
  end
  net.step(60 * 6)
end
--- Race: player i drops a piece every pace(i) frames, for `frames` frames (nil = until all are done).
local function lootRace(net, list, k, frames, pace)
  for f = 1, frames or 7000 do
    local running = false
    for i = 1, k do
      local sx = list[i].ns.App.session
      if sx and sx.loot and not sx.recorded then
        running = true
        if sx.phase == "playing" and f % pace(i) == 0 then
          -- spread the pieces over the board (each player its own pattern), so runs last and differ
          local shift = ((math.floor(f / pace(i)) * (i % 4 + 1)) % 9) - 4
          for _ = 1, math.abs(shift) do local k = shift < 0 and "left" or "right"; sx:press(k); sx:release(k) end
          if (f + i) % 5 == 0 then sx:press("rotateCW"); sx:release("rotateCW") end
          sx:press("hardDrop"); sx:release("hardDrop")
        end
      end
    end
    net.step(1)
    if not frames and not running then break end
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
  { "4-blitz", "Time Trial (2:00) - timer", function()
    local M, ns = boot(); seedRecords(ns); play(M, ns, "blitz"); M.frames_step(1); return M, ns
  end },
  { "4b-blitz-last-seconds", "Time Trial - last seconds", function()
    local M, ns = boot(); seedRecords(ns); play(M, ns, "blitz")
    local sess = ns.App.session
    sess.state.tick = sess.mode.limitTicks - 4 * 60 + 1 -- the 4-second mark (no play needed)
    ns.UI.dirty = true; M.frames_step(1); return M, ns
  end },
  { "5-paused-combat", "Paused by combat (window back after the fight)", function()
    local M, ns = boot(); play(M, ns, "classic")
    M.fire("PLAYER_REGEN_DISABLED"); M.fire("PLAYER_REGEN_ENABLED"); M.frames_step(1); return M, ns
  end },
  { "6-game-over", "Time Trial finished - new best", function()
    local M, ns = boot(); seedRecords(ns); M.inGuild = true
    play(M, ns, "blitz"); ns.App.session.state.score = 21300
    ns.App.session:finish("time"); M.frames_step(70); return M, ns
  end },
  { "7-settings", "Settings", function()
    local M, ns = boot(); SlashCmdList.STACKRIVALS("settings"); M.frames_step(1); return M, ns
  end },
  { "9-duel-sheet", "Guild Duels - guild (after Refresh)", function()
    local net, a, b = duelPair()
    net.add({ name = "Carol", guild = "G", saved = { seenHelp = true } })
    a.env.SlashCmdList.STACKRIVALS("")
    a.ns.UI:ShowSheet("duel")
    a.ns.UI.duelSheet.refresh:Click(); net.step(60)
    a.ns.UI:RefreshDuelSheet()
    return a.M, a.ns, a.env.StackRivalsFrame
  end },
  { "9b-challenge-bnet", "Guild Duels - Battle.net friends", function()
    local _, _, _, NS = duelPair()
    local net = NS.new({ seed = 9 })
    local a = net.add({ name = "Alice", saved = { seenHelp = true }, alsoOnline = { Gina = true },
      bnet = { { name = "Bob" }, { name = "Frank", realm = "Faraway" }, { name = "Gina", project = 5 }, { name = "Hana" } } })
    net.add({ name = "Frank", realm = "Faraway", saved = { seenHelp = true }, bnet = { { name = "Alice" } } }) -- other realm: over Battle.net
    net.add({ name = "Bob", saved = { seenHelp = true } })
    a.env.UIParent:SetSize(1920, 1080)
    net.step(30)
    a.env.SlashCmdList.STACKRIVALS("")
    a.ns.UI:ShowSheet("duel")
    a.ns.UI.duelSource = "bnet"
    a.ns.UI.duelSheet.refresh:Click(); net.step(60)
    a.ns.UI:RefreshDuelSheet()
    return a.M, a.ns, a.env.StackRivalsFrame
  end },
  { "9c-duel-invite", "Duel invite popup (works with the window closed)", function()
    local net, a, b = duelPair()
    a.ns.Duel.challenge("Bob"); net.step(30)
    return b.M, b.ns, b.ns.UI.invite
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
  { "16-spell-defeat", "Spell Battle vs Bot - you topped out first: the bot wins", function()
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
  { "20-quickplay-search", "Quickplay - searching (guild + group + friends you can reach)", function()
    local _, _, _, NS = duelPair()
    local net = NS.new({ seed = 20 })
    local a = net.add({ name = "Alice", guild = "G", group = "P", saved = { seenHelp = true } })
    net.add({ name = "Bob", guild = "G", saved = { seenHelp = true } })
    net.step(30)
    a.env.SlashCmdList.STACKRIVALS("")
    a.ns.UI:ShowSheet("quickplay")
    a.ns.Quickplay.start("b120")
    net.step(60 * 42)
    a.ns.UI:RefreshQuickplay()
    return a.M, a.ns, a.env.StackRivalsFrame
  end },
  { "20b-quickplay-menu", "Main menu while Quickplay searches", function()
    local _, _, _, NS = duelPair()
    local net = NS.new({ seed = 21 })
    local a = net.add({ name = "Alice", guild = "G", saved = { seenHelp = true } })
    net.step(30)
    a.env.SlashCmdList.STACKRIVALS("")
    a.ns.Quickplay.start("s180")
    net.step(60 * 17)
    return a.M, a.ns, a.env.StackRivalsFrame
  end },
  { "21-quickplay-found", "Quickplay - match found: lobby with both character cards (ready check)", function()
    local _, _, _, NS = duelPair()
    local net = NS.new({ seed = 22 })
    local a = net.add({ name = "Alice", guild = "G", faction = "Alliance", race = "Human", class = "WARRIOR", level = 42, saved = { seenHelp = true } })
    local b = net.add({ name = "Bob", guild = "G", faction = "Horde", race = "Orc", class = "SHAMAN", level = 38, saved = { seenHelp = true } })
    net.step(30)
    a.env.SlashCmdList.STACKRIVALS("")
    a.ns.Quickplay.start("b120"); b.ns.Quickplay.start("b120")
    net.step(300)
    b.ns.Duel.ready(); net.step(30)
    a.ns.UI:RefreshPhase()
    return a.M, a.ns, a.env.StackRivalsFrame
  end },
  { "22-match-chat", "Match chat panel (beside the window, same faction)", function()
    local _, _, _, NS = duelPair()
    local net = NS.new({ seed = 23 })
    local a = net.add({ name = "Alice", guild = "G", saved = { seenHelp = true } })
    local b = net.add({ name = "Bob", guild = "G", saved = { seenHelp = true } })
    net.step(30)
    a.env.SlashCmdList.STACKRIVALS("")
    a.ns.Quickplay.start("b120"); b.ns.Quickplay.start("b120")
    net.step(300)
    b.ns.Chat.quick(b.ns.Duel.current, 1); net.step(120)
    a.ns.Chat.send(a.ns.Duel.current, "You too! Best of luck, see you at the top"); net.step(120)
    b.ns.Chat.send(b.ns.Duel.current, "gg in advance :)"); net.step(60)
    a.ns.UI:RefreshPhase()
    return a.M, a.ns, a.ns.UI.chat
  end },
  { "22b-match-chat-factions", "Match chat across factions: quick messages only", function()
    local _, _, _, NS = duelPair()
    local net = NS.new({ seed = 24 })
    local a = net.add({ name = "Alice", guild = "G", faction = "Alliance", saved = { seenHelp = true } })
    local b = net.add({ name = "Bob", guild = "G", faction = "Horde", saved = { seenHelp = true } })
    net.step(30)
    a.env.SlashCmdList.STACKRIVALS("")
    a.ns.Quickplay.start("b120"); b.ns.Quickplay.start("b120")
    net.step(300)
    b.ns.Chat.quick(b.ns.Duel.current, 1); net.step(120)
    a.ns.Chat.quick(a.ns.Duel.current, 2); net.step(60)
    a.ns.UI:RefreshPhase()
    return a.M, a.ns, a.ns.UI.chat
  end },
  { "23-account-start", "Account - not linked: step 1 of 3 (type the one-time code from the website)", function()
    local M, ns = boot(); SlashCmdList.STACKRIVALS("")
    M.serverTime = 1793000000
    ns.UI:ShowSheet("account"); M.frames_step(1)
    return M, ns
  end },
  { "23-account-pending", "Account - linking: code typed, request to copy (PENDING, not linked yet)", function()
    local M, ns = boot(); SlashCmdList.STACKRIVALS("")
    M.serverTime = 1793000000
    ns.Account.startLink(ns.AccountCodes.makeWebCode("A7K9P2X"))
    M.serverTime = 1793000000 + 75
    ns.UI:ShowSheet("account"); M.frames_step(1)
    return M, ns
  end },
  { "23b-account-linked", "Account - LINKED after importing the stackrivals.io snapshot", function()
    local M, ns = boot(); SlashCmdList.STACKRIVALS("")
    M.serverTime = 1793000000
    local AC = ns.AccountCodes
    local r = AC.parseLinkRequest(ns.Account.startLink(AC.makeWebCode("A7K9P2X")))
    M.serverTime = 1793000000 + 300
    ns.Account.import(AC.profile({ linkId = r.linkId, player = r.player, accountId = "acc_7f3k2", name = "Alice Stack",
      issued = 1793000000 + 200, expires = 1793000000 + 8 * 86400, level = 12, xp = 1240, xpNext = 2000, rank = "Gold II",
      season = "Season 3", seasonPct = 45, wins = 12, losses = 8, draws = 1, history = {} }))
    ns.UI:ShowSheet("account"); M.frames_step(1)
    return M, ns
  end },
  { "23c-profile", "Account - Profile tab (display only, from the snapshot)", function()
    local M, ns = boot(); SlashCmdList.STACKRIVALS("")
    M.serverTime = 1793000000
    local AC = ns.AccountCodes
    local r = AC.parseLinkRequest(ns.Account.startLink(AC.makeWebCode("A7K9P2X")))
    M.serverTime = 1793000000 + 300
    local T0 = 1793000000
    ns.Account.import(AC.profile({ linkId = r.linkId, player = r.player, accountId = "acc_7f3k2", name = "Alice Stack",
      issued = T0 + 200, expires = T0 + 8 * 86400, level = 12, xp = 1240, xpNext = 2000, rank = "Gold II",
      season = "Season 3", seasonPct = 45, wins = 12, losses = 8, draws = 1, achUnlocked = 14, achTotal = 60, cosOwned = 5, cosEquipped = "Neon Grid",
      history = { { mode = "b120", res = "w", my = 12300, their = 9800, at = T0 - 3600 }, { mode = "s180", res = "l", my = 8000, their = 15000, at = T0 - 86400 },
        { mode = "daily", res = "w", my = 21000, their = 0, at = T0 - 2 * 86400 }, { mode = "spellbot", res = "d", my = 9000, their = 9000, at = T0 - 3 * 86400 } } }))
    ns.UI:ShowSheet("account"); ns.UI.accountTab = "profile"; ns.UI:RefreshAccount(); M.frames_step(1)
    return M, ns
  end },
  { "23c2-profile-stale", "Account - Profile tab, worst case: snapshot older than 7 days, 5 matches, longest name / rank / season / cosmetic", function()
    local M, ns = boot(); SlashCmdList.STACKRIVALS("")
    local T0 = 1793000000
    M.serverTime = T0
    local AC = ns.AccountCodes
    local r = AC.parseLinkRequest(ns.Account.startLink(AC.makeWebCode("A7K9P2X")))
    M.serverTime = T0 + 300
    ns.Account.import(AC.profile({ linkId = r.linkId, player = r.player, accountId = "acc_7f3k2", name = "Wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww",
      issued = T0 + 200, expires = T0 + 30 * 86400, level = 9999, xp = 123456789, xpNext = 987654321, rank = "Grandmaster Champion III",
      season = "Season of the Long Night", seasonPct = 100, wins = 123456, losses = 98765, draws = 4321, achUnlocked = 9999, achTotal = 9999,
      cosOwned = 99999, cosEquipped = "Wwwwwwwwwwwwwwwwwwwwwwww", sig = "abcdefghijklmnopqrstuvwxyz012345",
      history = { { mode = "b120", res = "w", my = 123456789, their = 98765432, at = T0 - 3600 }, { mode = "s180", res = "l", my = 8000, their = 15000, at = T0 - 86400 },
        { mode = "daily", res = "w", my = 21000, their = 0, at = T0 - 2 * 86400 }, { mode = "spellbot", res = "d", my = 9000, their = 9000, at = T0 - 3 * 86400 },
        { mode = "zzzzzzzzzzzz", res = "w", my = 1, their = 0, at = T0 - 4 * 86400 } } }))
    M.serverTime = T0 + 12 * 86400
    ns.UI:ShowSheet("account"); ns.UI.accountTab = "profile"; ns.UI:RefreshAccount(); M.frames_step(1)
    return M, ns
  end },
  { "23c3-profile-shards", "Account - Profile tab with a Shards balance (SIMULATED future format: SRP1 has no Shards; shown only once the website approves one)", function()
    local M, ns = boot(); SlashCmdList.STACKRIVALS("")
    local T0 = 1793000000
    M.serverTime = T0
    local AC = ns.AccountCodes
    local r = AC.parseLinkRequest(ns.Account.startLink(AC.makeWebCode("A7K9P2X")))
    M.serverTime = T0 + 300
    ns.Account.import(AC.profile({ linkId = r.linkId, player = r.player, accountId = "acc_7f3k2", name = "Alice Stack",
      issued = T0 + 200, expires = T0 + 8 * 86400, level = 12, xp = 1240, xpNext = 2000, rank = "Gold II",
      season = "Season 3", seasonPct = 45, wins = 12, losses = 8, draws = 1, achUnlocked = 14, achTotal = 60, cosOwned = 5, cosEquipped = "Neon Grid",
      history = { { mode = "b120", res = "w", my = 12300, their = 9800, at = T0 - 3600 }, { mode = "s180", res = "l", my = 8000, their = 15000, at = T0 - 86400 },
        { mode = "daily", res = "w", my = 21000, their = 0, at = T0 - 2 * 86400 }, { mode = "spellbot", res = "d", my = 9000, their = 9000, at = T0 - 3 * 86400 },
        { mode = "blitz", res = "w", my = 31000, their = 0, at = T0 - 4 * 86400 } } }))
    local real = ns.Account.profileView
    ns.Account.profileView = function() local v, st = real(); if v then v.shards = 12480 end; return v, st end
    M.serverTime = T0 + 2 * 3600
    ns.UI:ShowSheet("account"); ns.UI.accountTab = "profile"; ns.UI:RefreshAccount(); M.frames_step(1)
    return M, ns
  end },
  { "23d-sync", "Account - Sync: play a challenge code, copy result codes (manual copy / paste)", function()
    local M, ns = boot(); SlashCmdList.STACKRIVALS("")
    M.serverTime = 1793000000
    ns.App:StartChallenge(ns.Codes.challenge("b120", "srchal-7f3k2p9d01"))
    local s = ns.App.session
    for _ = 1, 3000 do
      if s.recorded then break end
      if s.phase == "playing" then s:press("hardDrop"); s:release("hardDrop") end
      M.frames_step(1)
    end
    ns.App:ShowMenu()
    ns.UI:ShowSheet("account"); ns.UI.accountTab = "sync"; ns.UI:RefreshAccount()
    ns.UI.accountSheet.sync.rows[1].btn:Click()
    M.frames_step(1)
    return M, ns
  end },
  { "24-loot-setup", "Loot Duel - dungeon party of 5: item picked, Invite Party / Invite Selected", function()
    local _, _, _, NS = duelPair()
    local net = NS.new({ seed = 40 })
    local cs = {}
    local cls = { "WARRIOR", "MAGE", "PRIEST", "ROGUE", "HUNTER" }
    for i, n in ipairs({ "Lead", "Ann", "Ben", "Cid", "Dee" }) do cs[n] = net.add({ name = n, group = "P", lead = (i == 1), class = cls[i], saved = { seenHelp = true } }) end
    net.step(30)
    local a = cs.Lead
    a.env.SlashCmdList.STACKRIVALS("")
    a.ns.UI.lootItemId = 19019
    a.ns.UI:ShowSheet("loot"); net.step(60 * 3)
    local s = a.ns.UI.lootSheet
    for i = 1, 3 do s.rows[i]:Click() end
    return a.M, a.ns, a.env.StackRivalsFrame
  end },
  { "24a-loot-party-joined", "Loot Duel - party of 5 invited: 3 joined, 1 passed, 1 still invited", function()
    local _, _, _, NS = duelPair()
    local net = NS.new({ seed = 44 })
    local cs = {}
    local cls = { "WARRIOR", "MAGE", "PRIEST", "ROGUE", "HUNTER" }
    for i, n in ipairs({ "Lead", "Ann", "Ben", "Cid", "Dee" }) do cs[n] = net.add({ name = n, group = "P", lead = (i == 1), class = cls[i], saved = { seenHelp = true } }) end
    net.step(30)
    local a = cs.Lead
    a.env.SlashCmdList.STACKRIVALS("")
    a.ns.LootDuel.create(19019, "l060", { "Lead-Realm", "Ann-Realm", "Ben-Realm", "Cid-Realm", "Dee-Realm" }); net.step(60)
    cs.Ann.ns.LootDuel.answer(true); cs.Ben.ns.LootDuel.answer(true); cs.Cid.ns.LootDuel.answer(false); net.step(120)
    a.ns.UI:ShowSheet("loot")
    return a.M, a.ns, a.env.StackRivalsFrame
  end },
  { "24b-loot-invite", "Loot Duel - the invite popup (accept / decline)", function()
    local _, _, _, NS = duelPair()
    local net = NS.new({ seed = 41 })
    local lead = net.add({ name = "Lead", group = "P", lead = true, saved = { seenHelp = true } })
    local ann = net.add({ name = "Ann", group = "P", class = "SHAMAN", saved = { seenHelp = true } })
    net.add({ name = "Ben", group = "P", class = "MAGE", saved = { seenHelp = true } })
    net.step(30)
    lead.ns.LootDuel.create(19019, "l060", { "Ann-Realm", "Ben-Realm" }); net.step(60)
    return ann.M, ann.ns, ann.ns.UI.lootPopup
  end },
  { "24c-loot-result", "Loot Duel - final results (winner's view): CONGRATULATIONS, WINNER green, LOST red, PASSED red", function()
    local net, list = lootGroup(42, 5)
    lootInvite(net, list, 5, function(i) return i ~= 5 end) -- Dee passes
    list[1].ns.LootDuel.start(); net.step(60 * 4)
    local pace = { 9, 5, 13, 11 }
    lootRace(net, list, 4, nil, function(i) return pace[i] end)
    net.step(60 * 20)
    local w = list[1].ns.LootDuel.history[1].winner
    local c = list[1]
    for _, x in ipairs(list) do if x.name == w then c = x end end
    c.ns.App:ShowMenu(); c.ns.UI:ShowSheet("loot")
    return c.M, c.ns, c.env.StackRivalsFrame
  end },
  { "24c2-loot-result-lost", "Loot Duel - the same result on a loser's PC: everyone sees who won (no auto-loot)", function()
    local net, list = lootGroup(42, 5)
    lootInvite(net, list, 5, function(i) return i ~= 5 end)
    list[1].ns.LootDuel.start(); net.step(60 * 4)
    local pace = { 9, 5, 13, 11 }
    lootRace(net, list, 4, nil, function(i) return pace[i] end)
    net.step(60 * 20)
    local d = list[1].ns.LootDuel.history[1]
    local c = list[4]
    for _, x in ipairs(list) do if x.name ~= d.winner and x ~= list[5] then c = x end end
    c.ns.App:ShowMenu(); c.ns.UI:ShowSheet("loot")
    return c.M, c.ns, c.env.StackRivalsFrame
  end },
  { "24d-loot-raid-pick", "Loot Duel - 20-player raid: the leader picks (level, class, group, StackRivals); Invite All / Selected", function()
    local _, _, _, NS = duelPair()
    local net = NS.new({ seed = 43 })
    local cls = { "WARRIOR", "SHAMAN", "MAGE", "ROGUE", "PRIEST", "DRUID", "HUNTER", "WARLOCK", "PALADIN" }
    local nm = { "Lead", "Ann", "Ben", "Cid", "Dee", "Eve", "Fay", "Gus", "Hal", "Ivy", "Jon", "Kim", "Lou", "Max", "Ned", "Oda", "Pia", "Quin", "Rex", "Sue" }
    local lead
    for i, n in ipairs(nm) do
      local c = net.add({ name = n, group = "R", raid = true, lead = (i == 1), class = cls[(i - 1) % #cls + 1], saved = { seenHelp = true } })
      lead = lead or c
    end
    net.step(30)
    lead.env.SlashCmdList.STACKRIVALS("")
    lead.ns.UI.lootItemId = 19019
    lead.ns.UI:ShowSheet("loot"); net.step(60 * 3)
    local s = lead.ns.UI.lootSheet
    for i = 2, 7 do s.rows[i]:Click() end
    return lead.M, lead.ns, lead.env.StackRivalsFrame
  end },
  { "24e-loot-live-board", "Loot Duel - 10 players racing: the live list beside the window (provisional until replayed)", function()
    local _, _, _, NS = duelPair()
    local net = NS.new({ seed = 45 })
    local cls = { "WARRIOR", "SHAMAN", "MAGE", "ROGUE", "PRIEST", "DRUID", "HUNTER", "WARLOCK", "PALADIN", "MAGE" }
    local nm = { "Lead", "Ann", "Ben", "Cid", "Dee", "Eve", "Fay", "Gus", "Hal", "Ivy" }
    local cs = {}
    for i, n in ipairs(nm) do cs[n] = net.add({ name = n, group = "R", raid = true, lead = (i == 1), class = cls[i], saved = { seenHelp = true } }) end
    net.step(30)
    local names = {}
    for _, n in ipairs(nm) do names[#names + 1] = n .. "-Realm" end
    cs.Lead.ns.LootDuel.create(19019, "l060", names); net.step(60)
    for i = 2, 10 do cs[nm[i]].ns.LootDuel.answer(true) end
    net.step(120)
    cs.Lead.ns.LootDuel.start(); net.step(60 * 6)
    local pace = { 7, 5, 9, 11, 6, 13, 8, 10, 4, 12 }
    for f = 1, 60 * 14 do
      for i, n in ipairs(nm) do
        local s = cs[n].ns.App.session
        if s and s.loot and s.phase == "playing" and f % (pace[i] * 22) == 0 then s:press("hardDrop"); s:release("hardDrop") end
      end
      net.step(1)
    end
    cs.Gus.online = false
    net.step(60 * 18)
    local a = cs.Ann
    if not a.ns.UI.frame:IsShown() then a.env.SlashCmdList.STACKRIVALS("") end
    a.ns.UI:RefreshPhase(); a.ns.UI:RefreshLootBoard()
    return a.M, a.ns, a.ns.UI.lootBoard
  end },
  { "24g-loot-raid-10", "Loot Duel - 10-player raid: everyone joined, ready, Start", function()
    local net, list = lootGroup(47, 10)
    lootInvite(net, list, 10, function() return true end)
    local a = list[1]
    a.env.SlashCmdList.STACKRIVALS(""); a.ns.UI:ShowSheet("loot")
    return a.M, a.ns, a.env.StackRivalsFrame
  end },
  { "24h-loot-raid-40", "Loot Duel - 40-player raid after Invite All: joined / passed / no answer yet, page 1 of 4", function()
    local net, list = lootGroup(48, 40)
    lootInvite(net, list, 40, function(i) if i % 9 == 0 then return false elseif i % 7 == 0 then return nil end return true end)
    local a = list[1]
    a.env.SlashCmdList.STACKRIVALS(""); a.ns.UI:ShowSheet("loot")
    return a.M, a.ns, a.env.StackRivalsFrame
  end },
  { "24i-loot-live-40", "Loot Duel - 40 racing at once: live top list (provisional), your own place pinned below", function()
    local net, list = lootGroup(49, 40)
    lootInvite(net, list, 40, function() return true end)
    list[1].ns.LootDuel.start(); net.step(60 * 5)
    lootRace(net, list, 40, 60 * 12, function(i) return 30 + (i * 7) % 31 end)
    list[31].online = false
    net.step(60 * 4)
    local a = list[27]
    if not a.ns.UI.frame:IsShown() then a.env.SlashCmdList.STACKRIVALS("") end
    a.ns.UI:RefreshPhase(); a.ns.UI:RefreshLootBoard(true)
    return a.M, a.ns, a.ns.UI.lootBoard
  end },
  { "24j-loot-result-40", "Loot Duel - 40-player final results: best 10 replay-checked, the rest listed as unchecked (can't win)", function()
    local net, list = lootGroup(50, 40)
    lootInvite(net, list, 40, function(i) return i ~= 38 end)
    list[1].ns.LootDuel.start(); net.step(60 * 5)
    lootRace(net, list, 40, nil, function(i) return 20 + (i * 7) % 23 end)
    net.step(60 * 30)
    local a = list[1]
    a.ns.App:ShowMenu(); a.ns.UI:ShowSheet("loot")
    return a.M, a.ns, a.env.StackRivalsFrame
  end },
  { "24f-loot-quick-button", "Loot Duel quick-access button near the group frames (own button; Shift-drag, right-click hides)", function()
    local _, _, _, NS = duelPair()
    local net = NS.new({ seed = 46 })
    local a = net.add({ name = "Lead", group = "P", lead = true, saved = { seenHelp = true } })
    net.add({ name = "Ann", group = "P", class = "MAGE", saved = { seenHelp = true } })
    net.step(30)
    return a.M, a.ns, a.ns.LootButton.button
  end, { minText = 1 } },
  { "8-records", "Records", function()
    local M, ns = boot(); seedRecords(ns); SlashCmdList.STACKRIVALS(""); ns.UI:ShowSheet("records"); M.frames_step(1); return M, ns
  end },
}

return S
