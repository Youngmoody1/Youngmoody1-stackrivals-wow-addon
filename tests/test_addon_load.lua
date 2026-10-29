-- Loads the WHOLE addon (every file in the .toc, in order) against a strict WoW API mock and
-- plays it like a player: open, start, keys, combat, game over, records, reload, rebinding.
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

--- Fresh client: new mock, load all files, fire login events. `saved` = SavedVariables on disk.
local function boot(saved)
  local M = dofile(testdir .. "/wowmock.lua")
  M.install()
  _G.StackRivalsDB = saved
  local ns = {}
  for _, f in ipairs(tocFiles()) do
    local chunk = assert(loadfile(root .. "/" .. f))
    chunk("StackRivals", ns)
  end
  M.fire("ADDON_LOADED", "StackRivals")
  M.fire("PLAYER_LOGIN")
  return M, ns
end

local function key(ns, k) ns.UI.keys:GetScript("OnKeyDown")(ns.UI.keys, k); ns.UI.keys:GetScript("OnKeyUp")(ns.UI.keys, k) end
local function playFrames(M, n) M.frames_step(n) end
-- Drop a piece at a spread-out column so scripted play doesn't simply top out.
local SPREAD = { { "LEFT", 4 }, { "RIGHT", 4 }, { "LEFT", 2 }, { "RIGHT", 2 }, { "LEFT", 0 } }
local function dropSpread(M, ns, i)
  local d = SPREAD[(i - 1) % #SPREAD + 1]
  for _ = 1, d[2] do key(ns, d[1]); playFrames(M, 2) end
  key(ns, "SPACE"); playFrames(M, 3)
end

describe("load and open", function()
  it("loads every .toc file without errors and registers /sr and /stackrivals", function()
    local M, ns = boot(nil)
    eq(SLASH_STACKRIVALS1, "/sr"); eq(SLASH_STACKRIVALS2, "/stackrivals")
    ok(type(SlashCmdList.STACKRIVALS) == "function")
    ok(type(StackRivals_OnAddonCompartmentClick) == "function", "compartment func is global")
    ok(StackRivalsDB == ns.db, "db published to SavedVariables global")
    ok(_G.StackRivalsMinimapButton ~= nil and StackRivalsMinimapButton:IsShown(), "minimap button")
    eq(#M.blocked, 0)
  end)
  it("/sr opens the window on the mode menu with the keyboard released", function()
    local M, ns = boot(nil)
    SlashCmdList.STACKRIVALS("")
    ok(StackRivalsFrame:IsShown())
    ok(ns.UI.menu:IsShown(), "menu visible")
    eq(ns.UI.keys._kb, false, "keyboard not captured on the menu")
    SlashCmdList.STACKRIVALS("")
    eq(StackRivalsFrame:IsShown(), false, "toggle closes")
  end)
end)

describe("hygiene", function()
  it("creates no accidental globals (only the documented ones)", function()
    local allowed = { StackRivalsDB = 1, StackRivalsFrame = 1, StackRivalsMinimapButton = 1, SLASH_STACKRIVALS1 = 1,
      SLASH_STACKRIVALS2 = 1, StackRivals_OnAddonCompartmentClick = 1 }
    local leaked = {}
    local M = dofile(testdir .. "/wowmock.lua"); M.install()
    setmetatable(_G, { __newindex = function(t, k, v) if not allowed[k] then leaked[#leaked + 1] = tostring(k) end rawset(t, k, v) end })
    local okRun, err = pcall(function()
      local ns = {}
      for _, f in ipairs(tocFiles()) do assert(loadfile(root .. "/" .. f))("StackRivals", ns) end
      M.fire("ADDON_LOADED", "StackRivals"); M.fire("PLAYER_LOGIN")
      SlashCmdList.STACKRIVALS(""); ns.App:Start("classic"); M.frames_step(400)
      ns.UI.keys:GetScript("OnKeyDown")(ns.UI.keys, "SPACE"); M.frames_step(10)
      M.fire("PLAYER_REGEN_DISABLED"); M.fire("PLAYER_LOGOUT")
    end)
    setmetatable(_G, nil)
    ok(okRun, tostring(err))
    eq(table.concat(leaked, ","), "")
  end)
end)

describe("playing", function()
  it("start -> countdown -> play with keys -> score rises, keyboard captured only while live", function()
    local M, ns = boot(nil)
    SlashCmdList.STACKRIVALS("")
    ns.UI.modeButtons.classic:Click()
    eq(ns.App.session.phase, "countdown")
    eq(ns.UI.keys._kb, true, "keyboard captured during countdown")
    playFrames(M, 181)
    eq(ns.App.session.phase, "playing")
    for i = 1, 8 do key(ns, "UP"); playFrames(M, 2); dropSpread(M, ns, i) end
    local s = ns.App.session.state
    eq(ns.App.session.phase, "playing")
    ok(s.piecesPlaced >= 8, "pieces placed: " .. s.piecesPlaced)
    ok(s.score > 0, "score > 0")
    ok(ns.UI.scoreText:GetText() ~= "0", "HUD shows score")
    ok(#M.sounds > 0, "sounds played")
    -- pause key
    key(ns, "P")
    eq(ns.App.session.phase, "paused")
    eq(ns.UI.keys._kb, false, "keyboard released when paused")
    ok(ns.UI.pause:IsShown())
  end)
  it("Enter mid-game pauses and lets the key through to WoW chat", function()
    local M, ns = boot(nil)
    ns.App:Start("blitz")
    playFrames(M, 181)
    ns.UI.keys:GetScript("OnKeyDown")(ns.UI.keys, "ENTER")
    eq(ns.App.session.phase, "paused")
    eq(ns.UI.keys._prop, true, "Enter propagated")
  end)
  it("client key auto-repeat is ignored (holding Space drops one piece, not many)", function()
    local M, ns = boot(nil)
    ns.App:Start("classic")
    playFrames(M, 181)
    local down = ns.UI.keys:GetScript("OnKeyDown")
    for _ = 1, 10 do down(ns.UI.keys, "SPACE"); playFrames(M, 2) end
    eq(ns.App.session.state.piecesPlaced, 1)
    ns.UI.keys:GetScript("OnKeyUp")(ns.UI.keys, "SPACE")
    down(ns.UI.keys, "SPACE"); playFrames(M, 2)
    eq(ns.App.session.state.piecesPlaced, 2)
  end)
  it("a key released that we never took (already running when the run started) goes to WoW", function()
    local M, ns = boot(nil)
    ns.App:Start("classic")
    playFrames(M, 181)
    ns.UI.keys:GetScript("OnKeyUp")(ns.UI.keys, "W")
    eq(ns.UI.keys._prop, true)
  end)
  it("share is refused during chat messaging lockdown", function()
    local M, ns = boot(nil)
    M.inGuild = true
    C_ChatInfo.InChatMessagingLockdown = function() return true end
    ns.App:Start("blitz")
    ns.App.session:finish("time"); playFrames(M, 1)
    ns.UI.shareGuild:Click()
    eq(#M.chat, 0)
  end)
  it("unbound keys are swallowed while playing, Print Screen always passes", function()
    local M, ns = boot(nil)
    ns.App:Start("classic")
    playFrames(M, 181)
    ns.UI.keys:GetScript("OnKeyDown")(ns.UI.keys, "1")
    eq(ns.UI.keys._prop, false)
    ns.UI.keys:GetScript("OnKeyDown")(ns.UI.keys, "PRINTSCREEN")
    eq(ns.UI.keys._prop, true)
  end)
end)

describe("combat safety", function()
  it("entering combat pauses, releases keys, hides the window; it comes back paused after combat", function()
    local M, ns = boot(nil)
    ns.App:Start("classic")
    playFrames(M, 200)
    eq(ns.UI.keys._kb, true)
    -- PLAYER_REGEN_DISABLED fires just BEFORE lockdown starts
    M.fire("PLAYER_REGEN_DISABLED")
    M.combat = true
    eq(ns.App.session.phase, "paused"); eq(ns.App.session.pauseReason, "combat")
    eq(ns.UI.keys._kb, false, "keyboard released before lockdown")
    eq(StackRivalsFrame:IsShown(), false, "hidden in combat")
    playFrames(M, 60)
    -- trying to start or resume in combat is refused, without protected calls
    ns.App:Resume()
    eq(ns.App.session.phase, "paused")
    SlashCmdList.STACKRIVALS("blitz")
    eq(ns.App.session.mode.key, "classic", "no new run in combat")
    M.combat = false
    M.fire("PLAYER_REGEN_ENABLED")
    ok(StackRivalsFrame:IsShown(), "window back after combat")
    ok(ns.UI.pause:IsShown(), "still paused")
    ns.UI.resumeBtn:Click()
    eq(ns.App.session.phase, "countdown")
    eq(#M.blocked, 0, "no blocked actions: " .. table.concat(M.blocked, ","))
  end)
  it("opening the window during combat never touches the keyboard", function()
    local M, ns = boot(nil)
    M.fire("PLAYER_REGEN_DISABLED"); M.combat = true
    SlashCmdList.STACKRIVALS("")
    ok(StackRivalsFrame:IsShown())
    ns.UI.modeButtons.blitz:Click()
    eq(ns.App.session, nil, "mode buttons disabled in combat")
    playFrames(M, 30)
    eq(#M.blocked, 0, "no blocked actions")
  end)
end)

describe("game over and records", function()
  it("a full Blitz ends at 2:00, saves the record and shows NEW BEST", function()
    local M, ns = boot(nil)
    ns.App:Start("blitz")
    local frames = 0
    while ns.App.session.phase ~= "over" and frames < 9000 do
      if frames % 20 == 0 then key(ns, "SPACE") end
      playFrames(M, 1); frames = frames + 1
    end
    local s = ns.App.session
    eq(s.phase, "over")
    if s.endReason == "time" then eq(s.state.tick, 7200) end
    ok(ns.UI.over:IsShown(), "game over screen")
    eq(StackRivalsDB.records.blitz.games, 1)
    eq(StackRivalsDB.records.blitz.best, s.state.score)
    ok(StackRivalsDB.records.blitz.bestLog ~= nil, "best run log saved")
    ok(ns.UI.overBadge:GetText():find("NEW BEST") ~= nil, "badge: " .. tostring(ns.UI.overBadge:GetText()))
    eq(ns.UI.keys._kb, false, "keyboard released on game over")
    -- the saved best log replays to exactly the recorded score (future server verification)
    local d = ns.Engine.deserializeLog(StackRivalsDB.records.blitz.bestLog)
    local r = ns.Engine.replay(d.seed, { startLevel = d.startLevel }, d.log, d.ticks)
    eq(r.score, s.state.score, "replayed score")
  end)
  it("daily blitz uses the same seed for everyone on the same UTC day", function()
    local M1, ns1 = boot(nil); ns1.App:Start("daily")
    local M2, ns2 = boot(nil); ns2.App:Start("daily")
    eq(ns1.App.session.seed, ns2.App.session.seed)
    eq(table.concat(ns1.App.session.state.queue, ","), table.concat(ns2.App.session.state.queue, ","))
    ok(ns1.App.session.seed:find(os.date("!%Y-%m-%d"), 1, true) ~= nil)
  end)
  it("share posts one plain line to guild chat only when clicked", function()
    local M, ns = boot(nil)
    M.inGuild = true
    ns.App:Start("blitz")
    ns.App.session:finish("time"); playFrames(M, 1)
    ns.UI.shareGuild:Click()
    eq(#M.chat, 1); eq(M.chat[1][2], "GUILD")
    ok(M.chat[1][1]:find("^%[StackRivals%]") ~= nil)
  end)
end)

describe("SavedVariables robustness", function()
  it("corrupted saved data loads with defaults instead of errors", function()
    local bad = { settings = "oops", bindings = { left = 5, right = "RIGHT", hold = "RIGHT" },
      records = { classic = { best = "x", games = -4 }, blitz = 7 }, window = { x = "a" }, suspended = { mode = "nope" } }
    local M, ns = boot(bad)
    eq(ns.db.settings.sound, true)
    eq(ns.db.bindings.left, "LEFT")
    eq(ns.db.bindings.right, "RIGHT")
    ok(ns.db.bindings.hold ~= "RIGHT", "duplicate key dropped")
    eq(ns.db.records.classic.best, 0); eq(ns.db.records.classic.games, 0)
    eq(ns.db.suspended, nil)
    SlashCmdList.STACKRIVALS("")
    ok(StackRivalsFrame:IsShown())
  end)
  it("/reload mid-run keeps the run; Continue restores the exact same state", function()
    local M, ns = boot(nil)
    ns.App:Start("classic")
    playFrames(M, 181)
    for i = 1, 8 do dropSpread(M, ns, i); playFrames(M, 5) end
    eq(ns.App.session.phase, "playing")
    local hash = ns.Engine.hashState(ns.App.session.state)
    M.fire("PLAYER_LOGOUT") -- /reload fires PLAYER_LOGOUT, then SavedVariables are written
    local saved = StackRivalsDB
    ok(saved.suspended ~= nil, "run suspended")
    local M2, ns2 = boot(saved)
    SlashCmdList.STACKRIVALS("")
    ok(ns2.UI.continueBtn:IsShown(), "Continue button offered")
    ns2.UI.continueBtn:Click()
    eq(ns2.App.session.phase, "paused")
    eq(ns2.Engine.hashState(ns2.App.session.state), hash, "identical state after reload")
    ns2.UI.resumeBtn:Click()
    playFrames(M2, 240)
    eq(ns2.App.session.phase, "playing")
  end)
end)

describe("settings", function()
  it("rebinding a key swaps with the action that used it and survives a reload", function()
    local M, ns = boot(nil)
    SlashCmdList.STACKRIVALS("settings")
    ok(ns.UI.settings:IsShown())
    ns.UI.bindButtons.left:Click()
    eq(ns.UI.keys._kb, true, "capturing for rebind")
    ns.UI.keys:GetScript("OnKeyDown")(ns.UI.keys, "J")
    eq(ns.db.bindings.left, "J")
    eq(ns.UI.keys._kb, false)
    ns.UI.bindButtons.right:Click()
    ns.UI.keys:GetScript("OnKeyDown")(ns.UI.keys, "J")
    eq(ns.db.bindings.right, "J"); eq(ns.db.bindings.left, "RIGHT", "swapped")
    local M2, ns2 = boot(StackRivalsDB)
    eq(ns2.db.bindings.right, "J")
  end)
  it("toggles, scale and minimap command work", function()
    local M, ns = boot(nil)
    SlashCmdList.STACKRIVALS("settings")
    ns.UI.toggles[1]:Click()
    eq(ns.db.settings.sound, false); eq(ns.Sound.enabled, false)
    SlashCmdList.STACKRIVALS("scale 1.3")
    eq(ns.db.settings.scale, 1.3); eq(StackRivalsFrame._scale, 1.3)
    SlashCmdList.STACKRIVALS("scale 9")
    eq(ns.db.settings.scale, 1.6, "clamped")
    SlashCmdList.STACKRIVALS("minimap")
    eq(StackRivalsMinimapButton:IsShown(), false)
    SlashCmdList.STACKRIVALS("help"); SlashCmdList.STACKRIVALS("stats"); SlashCmdList.STACKRIVALS("version")
    ok(#M.log >= 3)
  end)
end)

describe("performance (Lua 5.1 outside WoW, indicative only)", function()
  it("one rendered frame of active play costs well under 1 ms", function()
    local M, ns = boot(nil)
    ns.App:Start("classic")
    playFrames(M, 181)
    local t0 = os.clock()
    for i = 1, 600 do
      if i % 15 == 0 then key(ns, "SPACE") elseif i % 5 == 0 then key(ns, "LEFT") end
      playFrames(M, 1)
    end
    local per = (os.clock() - t0) / 600 * 1000
    print(string.format("    avg %.3f ms per frame over 600 frames (incl. mock overhead)", per))
    ok(per < 1.0, "per-frame cost " .. per)
  end)
end)

return H
