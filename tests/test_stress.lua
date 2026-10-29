-- Stress and robustness: random UI/input fuzzing with combat, reloads and odd frame times;
-- long sessions with memory checks; corrupted SavedVariables; client-flavour API variants.
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

--- Boot a fresh client. `flavor` adjusts the mocked API: forever | retail | classic.
local function boot(saved, flavor)
  local M = dofile(testdir .. "/wowmock.lua")
  M.install()
  flavor = flavor or "forever"
  if flavor == "forever" then
    _G.GetBuildInfo = function() return "1.60.1", "70338", "Oct 2026", 16001 end
    _G.WOW_PROJECT_ID = 18
    _G.issecretvalue = function(v) return v == "SECRET" end
    _G.UnitAffectingCombat = function() return M.combat and "SECRET" or false end
    C_ChatInfo.InChatMessagingLockdown = function() return M.chatLocked or false end
  elseif flavor == "retail" then
    _G.GetBuildInfo = function() return "12.1.5", "71000", "Oct 2026", 120105 end
    _G.WOW_PROJECT_ID = 1
    _G.issecretvalue = function() return false end
  elseif flavor == "classic" then
    _G.GetBuildInfo = function() return "1.15.9", "65000", "Oct 2026", 11509 end
    _G.WOW_PROJECT_ID = 2
    _G.issecretvalue = nil
    _G.C_AddOns = nil
    _G.GetAddOnMetadata = function(_, f) if f == "Version" then return "0.3.0" end end
    M.oldChat = {}
    _G.C_ChatInfo = {}
    _G.SendChatMessage = function(msg, ch) M.chat[#M.chat + 1] = { msg, ch } end
  end
  _G.StackRivalsDB = saved
  local ns = {}
  for _, f in ipairs(tocFiles()) do assert(loadfile(root .. "/" .. f))("StackRivals", ns) end
  M.fire("ADDON_LOADED", "StackRivals")
  M.fire("PLAYER_LOGIN")
  return M, ns
end

-- deterministic LCG for fuzzing (independent of math.random, which the addon uses for seeds)
local function rng(seed)
  local x = seed
  return function(n)
    x = (x * 1103515245 + 12345) % 2147483648
    -- use the high bits: the low bits of this LCG repeat with a very short period
    return (math.floor(x / 65536) % n) + 1
  end
end

local KEYS = { "LEFT", "RIGHT", "UP", "DOWN", "SPACE", "Z", "C", "P", "A", "D", "W", "S", "ESCAPE", "ENTER", "1", "F", "LSHIFT", "PRINTSCREEN", "J" }

describe("UI fuzzing (random keys, clicks, combat, reloads, frame times)", function()
  for _, flavor in ipairs({ "forever", "retail", "classic" }) do
    it(flavor .. ": 20 sessions x 600 random steps keep every invariant", function()
      local seen = { reload = 0, combat = 0 }
      for seed = 1, 20 do
        local r = rng(seed * 7919 + ({ forever = 1, retail = 2, classic = 3 })[flavor] * 104729)
        local M, ns = boot(nil, flavor)
        SlashCmdList.STACKRIVALS("")
        local held = {}
        for step = 1, 600 do
          local k = r(100)
          if k <= 30 then
            local key = KEYS[r(#KEYS)]
            if ns.UI.keys._kb then
              ns.UI.keys:GetScript("OnKeyDown")(ns.UI.keys, key)
              held[key] = true
            end
          elseif k <= 45 then
            for key in pairs(held) do
              if ns.UI.keys._kb then ns.UI.keys:GetScript("OnKeyUp")(ns.UI.keys, key) end
              held[key] = nil
              break
            end
          elseif k <= 55 then
            -- click a random visible, enabled button inside our window
            local list = {}
            for _, f in ipairs(M.frames) do
              local cur, vis = f, true
              while cur do if not cur._shown then vis = false break end cur = cur._parent end
              if vis and f._kind == "Button" and f._enabled and f._name ~= "StackRivalsMinimapButton" then list[#list + 1] = f end
            end
            if #list > 0 then list[r(#list)]:Click() end
          elseif k <= 58 then
            if not M.combat then M.fire("PLAYER_REGEN_DISABLED"); M.combat = true; seen.combat = seen.combat + 1
            else M.combat = false; M.fire("PLAYER_REGEN_ENABLED") end
          elseif k <= 59 then
            M.fire("LOADING_SCREEN_ENABLED")
          elseif k <= 60 then
            SlashCmdList.STACKRIVALS("")
          elseif k <= 62 then
            -- /reload: logout event, then a new client with the saved data
            seen.reload = seen.reload + 1
            M.fire("PLAYER_LOGOUT")
            local saved = StackRivalsDB
            local wasCombat = M.combat
            M, ns = boot(saved, flavor)
            M.combat = false
            if wasCombat then M.fire("PLAYER_REGEN_DISABLED"); M.combat = true end
            held = {}
            SlashCmdList.STACKRIVALS("")
          elseif k <= 63 then
            M.chatLocked = not M.chatLocked
          elseif k <= 67 then
            -- end the run the way the Blitz clock or a top-out does
            local s = ns.App.session
            if s and s.phase == "playing" then
              if r(2) == 1 then s:finish("time") else for _ = 1, 60 do s:press("hardDrop"); s:update(1 / 60) end end
            end
          else
            local dts = { 1 / 240, 1 / 144, 1 / 60, 1 / 30, 1 / 12, 0.4 }
            local counts = { 1, 3, 10, 40, 120, 200 }
            M.frames_step(counts[r(#counts)], dts[r(#dts)])
          end
          -- invariants
          if #M.blocked > 0 then error("blocked action at step " .. step .. ": " .. M.blocked[1]) end
          if M.combat and ns.UI.keys and ns.UI.keys._kb then
            -- the keyboard may only be held in combat if it was never released, which must not happen
            error("keyboard captured during combat at step " .. step)
          end
          local s = ns.App.session
          if s and M.combat and s.phase == "playing" then error("still playing in combat at step " .. step) end
          if s then
            ok(s.state.score >= 0 and s.state.lines >= 0)
            seen[s.phase] = (seen[s.phase] or 0) + 1
            if M.combat and s.phase == "paused" then seen.combatPaused = (seen.combatPaused or 0) + 1 end
          end
        end
      end
      -- the fuzzer must actually reach every state, or it proves nothing
      for _, k in ipairs({ "countdown", "playing", "paused", "over", "combatPaused" }) do
        ok((seen[k] or 0) > 0, "fuzzer never reached " .. k)
      end
      print(string.format("    %s: playing %d, paused %d (in combat %d), over %d, reloads %d, combats %d", flavor,
        seen.playing or 0, seen.paused or 0, seen.combatPaused or 0, seen.over or 0, seen.reload, seen.combat))
      ok(seen.reload > 5 and seen.combat > 20, "reloads " .. seen.reload .. ", combats " .. seen.combat)
    end)
  end
end)

describe("long sessions", function()
  it("60 simulated minutes of play (with restarts): memory stays flat", function()
    local M, ns = boot(nil, "forever")
    local r = rng(42)
    ns.App:Start("classic")
    local samples = {}
    for minute = 1, 60 do
      for f = 1, 3600 do
        local s = ns.App.session
        if s.phase == "playing" then
          if f % 23 == 0 then local key = ({ "LEFT", "RIGHT", "UP" })[r(3)]; ns.UI.keys:GetScript("OnKeyDown")(ns.UI.keys, key); ns.UI.keys:GetScript("OnKeyUp")(ns.UI.keys, key) end
          if f % 47 == 0 then ns.UI.keys:GetScript("OnKeyDown")(ns.UI.keys, "SPACE"); ns.UI.keys:GetScript("OnKeyUp")(ns.UI.keys, "SPACE") end
        elseif s.phase == "over" then
          ns.App:Start(r(2) == 1 and "classic" or "blitz")
        end
        M.frames_step(1)
      end
      if minute % 10 == 0 then
        collectgarbage("collect")
        samples[#samples + 1] = collectgarbage("count")
      end
    end
    local games = StackRivalsDB.records.classic.games + StackRivalsDB.records.blitz.games
    ok(games > 20, "played many runs: " .. games)
    local growth = samples[#samples] - samples[1]
    print(string.format("    live memory over 60 min: %.0f KB -> %.0f KB (%d runs)", samples[1], samples[#samples], games))
    ok(growth < 512, "memory growth " .. growth .. " KB")
  end)
  it("a 2-hour run keeps a restorable log; restore takes < 1 s here", function()
    local H2 = dofile(testdir .. "/harness.lua")
    local ns = H2.load(root, { "Engine/Prng.lua", "Engine/Pieces.lua", "Engine/Engine.lua", "Engine/Input.lua", "Core/Session.lua", "Core/DB.lua" })
    local E = ns.Engine
    -- an "immortal" run: only rotations and sideways moves (never locks faster than gravity)
    -- on the slowest level would top out; instead log many inputs on a short replayable run and
    -- check the serialized size of a 2 h input rate against the stored-log limit.
    local s = E.createGame("long")
    local acts = { "left", "right", "rotateCW", "rotateCCW" }
    local ticks = 0
    while not s.gameOver and ticks < 20000 do
      if ticks % 5 == 0 then E.applyInput(s, acts[(ticks / 5) % 4 + 1]) end
      E.tick(s); ticks = ticks + 1
    end
    local log = E.serializeLog(s)
    local perInput = #log / (#s.inputLog / 2)
    local twoHours = 7200 * 12 * perInput -- 12 inputs/s is a very fast player
    ok(twoHours < ns.DB.MAX_LOG, string.format("2 h log ~%.0f KB fits in %d KB", twoHours / 1024, ns.DB.MAX_LOG / 1024))
    local t0 = os.clock()
    local d = E.deserializeLog(log)
    local r = E.replay(d.seed, { startLevel = d.startLevel }, d.log, d.ticks)
    eq(E.hashState(r), E.hashState(s))
    local tps = d.ticks / math.max(1e-6, os.clock() - t0)
    print(string.format("    replay speed %.0f ticks/s -> a 2 h run restores in ~%.2f s", tps, 432000 / tps))
    ok(432000 / tps < 1.0, "2 h restore under 1 s")
  end)
  it("20 reload/restore cycles in a row give the exact same game", function()
    local M, ns = boot(nil, "forever")
    ns.App:Start("classic"); M.frames_step(181)
    local r = rng(5)
    for cycle = 1, 20 do
      for _ = 1, 30 do
        local key = ({ "LEFT", "RIGHT", "UP", "Z" })[r(4)]
        ns.UI.keys:GetScript("OnKeyDown")(ns.UI.keys, key); ns.UI.keys:GetScript("OnKeyUp")(ns.UI.keys, key)
        M.frames_step(r(5))
      end
      if ns.App.session.phase ~= "playing" then break end
      local hash = ns.Engine.hashState(ns.App.session.state)
      M.fire("PLAYER_LOGOUT")
      M, ns = boot(StackRivalsDB, "forever")
      SlashCmdList.STACKRIVALS("")
      ns.UI.continueBtn:Click()
      eq(ns.Engine.hashState(ns.App.session.state), hash, "cycle " .. cycle)
      ns.UI.resumeBtn:Click(); M.frames_step(121)
    end
  end)
end)

describe("SavedVariables fuzzing", function()
  it("300 random/garbled saved files load without errors and give a valid db", function()
    local r = rng(99)
    local junk = { 0, -1, 1e308, -1e308, 0 / 0, "", "x", "|cffff0000", string.rep("A", 5000), true, false, {}, { 1, 2, 3 } }
    local function rnd(depth)
      local k = r(10)
      if depth > 3 or k <= 6 then return junk[r(#junk)] end
      local t = {}
      for _ = 1, r(6) do
        local keys = { "settings", "bindings", "records", "window", "suspended", "diag", "classic", "blitz", "daily",
          "dailyToday", "best", "top", "sound", "scale", "left", "hold", "mode", "log", "clients", "loads", "schema" }
        t[keys[r(#keys)]] = rnd(depth + 1)
      end
      return t
    end
    for i = 1, 300 do
      local saved = rnd(0)
      local M, ns = boot(type(saved) == "table" and saved or nil, ({ "forever", "retail", "classic" })[i % 3 + 1])
      local db = ns.db
      ok(type(db.settings.scale) == "number" and db.settings.scale >= 0.6 and db.settings.scale <= 1.6)
      ok(db.settings.scale == db.settings.scale, "no NaN")
      for _, m in ipairs({ "classic", "blitz", "daily" }) do
        ok(type(db.records[m].best) == "number" and db.records[m].best >= 0)
      end
      local seen = {}
      for _, k in pairs(db.bindings) do ok(not seen[k], "duplicate key " .. k); seen[k] = true end
      SlashCmdList.STACKRIVALS(""); M.frames_step(3)
    end
  end)
  it("a saved file from a FUTURE addon version (schema 99) still loads", function()
    local M, ns = boot({ schema = 99, settings = { scale = 1.2, sound = false, newThing = { a = 1 } }, records = { blitz = { best = 500, extra = "x" } } }, "retail")
    eq(ns.db.settings.scale, 1.2); eq(ns.db.settings.sound, false); eq(ns.db.records.blitz.best, 500)
  end)
end)

describe("client flavours (simulated APIs, not real clients)", function()
  for _, flavor in ipairs({ "forever", "retail", "classic" }) do
    it(flavor .. ": load, play, combat, game over, share, reload", function()
      local M, ns = boot(nil, flavor)
      M.inGuild = true
      local c = StackRivalsDB.diag.clients
      local any
      for _, v in pairs(c) do any = v end
      ok(any and any.interface > 0, "diag recorded")
      SlashCmdList.STACKRIVALS("blitz"); M.frames_step(181)
      for _ = 1, 5 do ns.UI.keys:GetScript("OnKeyDown")(ns.UI.keys, "SPACE"); ns.UI.keys:GetScript("OnKeyUp")(ns.UI.keys, "SPACE"); M.frames_step(10) end
      M.fire("PLAYER_REGEN_DISABLED"); M.combat = true
      ok(not ns.UI.keys._kb)
      M.combat = false; M.fire("PLAYER_REGEN_ENABLED")
      ns.UI.resumeBtn:Click(); M.frames_step(121)
      ns.App.session:finish("time"); M.frames_step(2)
      ns.UI.shareGuild:Click()
      eq(#M.chat, 1, "shared once")
      eq(#M.blocked, 0)
      M.fire("PLAYER_LOGOUT")
      local M2, ns2 = boot(StackRivalsDB, flavor)
      eq(ns2.db.records.blitz.games, 1)
    end)
  end
end)

return H
