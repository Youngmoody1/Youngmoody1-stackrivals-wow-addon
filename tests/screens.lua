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
  { "24-loot-setup", "Loot Duel - leader picks the item and players, invites sent", function()
    local _, _, _, NS = duelPair()
    local net = NS.new({ seed = 40 })
    local cs = {}
    local cls = { "WARRIOR", "SHAMAN", "MAGE", "PRIEST" }
    for i, n in ipairs({ "Lead", "Ann", "Ben", "Cid" }) do cs[n] = net.add({ name = n, group = "P", lead = (i == 1), class = cls[i], saved = { seenHelp = true } }) end
    net.step(30)
    local a = cs.Lead
    a.env.SlashCmdList.STACKRIVALS("")
    a.ns.LootDuel.create(19019, "l060", { "Ann-Realm", "Ben-Realm", "Cid-Realm" }); net.step(60)
    cs.Ann.ns.LootDuel.answer(true); cs.Cid.ns.LootDuel.answer(false); net.step(120)
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
  { "24c-loot-result", "Loot Duel - result: replay-checked standings and the winner", function()
    local _, _, _, NS = duelPair()
    local net = NS.new({ seed = 42 })
    local cs = {}
    local cls = { "WARRIOR", "SHAMAN", "MAGE" }
    for i, n in ipairs({ "Lead", "Ann", "Ben" }) do cs[n] = net.add({ name = n, group = "P", lead = (i == 1), class = cls[i], saved = { seenHelp = true } }) end
    net.step(30)
    cs.Lead.ns.LootDuel.create(19019, "l060", { "Lead-Realm", "Ann-Realm", "Ben-Realm" }); net.step(60)
    cs.Ann.ns.LootDuel.answer(true); cs.Ben.ns.LootDuel.answer(true); net.step(120)
    cs.Lead.ns.LootDuel.start(); net.step(240)
    local pace = { Lead = 9, Ann = 5, Ben = 13 }
    for f = 1, 6000 do
      local running = false
      for n, c in pairs(cs) do
        local s = c.ns.App.session
        if s and s.loot and not s.recorded then running = true; if s.phase == "playing" and f % pace[n] == 0 then s:press("hardDrop"); s:release("hardDrop") end end
      end
      net.step(1)
      if not running then break end
    end
    net.step(60 * 20)
    cs.Lead.ns.App:ShowMenu()
    cs.Lead.ns.UI:ShowSheet("loot")
    return cs.Lead.M, cs.Lead.ns, cs.Lead.env.StackRivalsFrame
  end },
  { "8-records", "Records", function()
    local M, ns = boot(); seedRecords(ns); SlashCmdList.STACKRIVALS(""); ns.UI:ShowSheet("records"); M.frames_step(1); return M, ns
  end },
}

return S
