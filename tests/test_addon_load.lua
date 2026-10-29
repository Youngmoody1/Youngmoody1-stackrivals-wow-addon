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

--- Boot with the API of an older client (Classic Era style): newer namespaces/methods removed.
local function bootOldApi(saved)
  local M = dofile(testdir .. "/wowmock.lua")
  M.install()
  _G.C_AddOns = nil
  _G.GetAddOnMetadata = function(_, field) if field == "Version" then return "0.2.0-era" end end
  M.oldChat = {}
  _G.C_ChatInfo = {} -- exists, but without SendChatMessage / InChatMessagingLockdown
  _G.SendChatMessage = function(msg, channel) M.oldChat[#M.oldChat + 1] = { msg, channel } end
  _G.StackRivalsDB = saved
  local ns = {}
  for _, f in ipairs(tocFiles()) do assert(loadfile(root .. "/" .. f))("StackRivals", ns) end
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

describe("client API variants (simulated, not a real client)", function()
  it("older-client API: metadata and chat fall back to the global functions", function()
    local M, ns = bootOldApi(nil)
    eq(ns.VERSION, "0.2.0-era")
    M.inGuild = true
    ns.App:Start("blitz"); ns.App.session:finish("time"); M.frames_step(1)
    ns.UI.shareGuild:Click()
    eq(#M.oldChat, 1); eq(M.oldChat[1][2], "GUILD")
  end)
  it("secret combat values (Midnight/Forever) never raise errors", function()
    local M, ns = boot(nil)
    _G.issecretvalue = function(v) return v == "SECRET" end
    _G.UnitAffectingCombat = function() return "SECRET" end
    ns.App:Start("classic"); M.frames_step(200)
    eq(ns.UI.inCombat(), false)
    M.combat = true
    eq(ns.UI.inCombat(), true, "InCombatLockdown still decides")
    _G.issecretvalue = nil
  end)
end)

describe("hygiene", function()
  it("creates no accidental globals (only the documented ones)", function()
    -- a fresh, isolated client environment, so names left over by other tests can't hide a leak
    local NS = assert(loadfile(testdir .. "/netsim.lua"))(root, testdir)
    local net = NS.new({ seed = 3 })
    local before = {}
    local c = net.add({ name = "Hygiene", guild = "G" })
    local allowed = { StackRivalsDB = 1, StackRivalsFrame = 1, StackRivalsMinimapButton = 1, SLASH_STACKRIVALS1 = 1,
      SLASH_STACKRIVALS2 = 1, StackRivals_OnAddonCompartmentClick = 1 }
    -- everything the mock itself installs
    local M2 = dofile(testdir .. "/wowmock.lua")
    local mockEnv = {}
    M2.install(mockEnv)
    for k in pairs(mockEnv) do before[k] = true end
    c.env.SlashCmdList.STACKRIVALS(""); c.ns.App:Start("classic"); net.step(400)
    c.ns.Duel.findPlayers(); net.step(60)
    c.M.fire("PLAYER_REGEN_DISABLED"); c.M.fire("PLAYER_LOGOUT")
    local leaked = {}
    for k in pairs(c.env) do
      if not before[k] and not allowed[k] and k ~= "math" and k ~= "IsInGuild" and k ~= "IsInGroup" and k ~= "IsInRaid" then
        leaked[#leaked + 1] = tostring(k)
      end
    end
    table.sort(leaked)
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
    -- paused: the window only listens for the pause key; every other key goes to WoW
    eq(ns.UI.keys._kb, true, "listening for the pause key only")
    ns.UI.keys:GetScript("OnKeyDown")(ns.UI.keys, "W"); eq(ns.UI.keys._prop, true, "W goes to WoW")
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

describe("pause and help", function()
  it("first /sr: the menu is one click from playing; How to play is offered, never forced", function()
    local M, ns = boot(nil)
    SlashCmdList.STACKRIVALS("")
    ok(ns.UI.menu:IsShown(), "mode menu on first open")
    ok(not (ns.UI.help and ns.UI.help:IsShown()), "help is not forced")
    eq(ns.UI.howBtn.fs:GetText(), "New? How to play", "first visit points at the help")
    ns.UI.howBtn:Click()
    ok(ns.UI.help:IsShown())
    ns.UI.help.done:Click()
    eq(ns.UI.help:IsShown(), false)
    eq(ns.UI.howBtn.fs:GetText(), "How to play", "nudge gone once seen")
    -- the help sheet can start a game directly
    ns.UI.howBtn:Click(); ns.UI.help.play:Click()
    eq(ns.App.session.mode.key, "blitz"); eq(ns.App.session.phase, "countdown")
    ok(ns.UI.controlsStrip:IsShown(), "first runs: controls shown on the board during the countdown")
    local M2, ns2 = boot(StackRivalsDB)
    SlashCmdList.STACKRIVALS("")
    eq(ns2.UI.howBtn.fs:GetText(), "How to play", "remembered after reload")
  end)
  it("while paused: P resumes, every other key (incl. Esc and movement) goes to WoW", function()
    local M, ns = boot(nil)
    ns.App:Start("classic"); playFrames(M, 181)
    key(ns, "P")
    eq(ns.App.session.phase, "paused")
    eq(ns.UI.keys._kb, true, "listening for the pause key")
    local down = ns.UI.keys:GetScript("OnKeyDown")
    down(ns.UI.keys, "W"); eq(ns.UI.keys._prop, true, "W to WoW")
    down(ns.UI.keys, "ESCAPE"); eq(ns.UI.keys._prop, true, "Esc to WoW")
    eq(ns.App.session.phase, "paused")
    down(ns.UI.keys, "P"); eq(ns.UI.keys._prop, false)
    eq(ns.App.session.phase, "countdown", "resumed")
    ns.UI.keys:GetScript("OnKeyUp")(ns.UI.keys, "P"); eq(ns.UI.keys._prop, false, "P release consumed")
    playFrames(M, 121); eq(ns.App.session.phase, "playing", "2 s resume countdown")
  end)
  it("combat while paused releases the keyboard too", function()
    local M, ns = boot(nil)
    ns.App:Start("classic"); playFrames(M, 181); key(ns, "P")
    eq(ns.UI.keys._kb, true)
    M.fire("PLAYER_REGEN_DISABLED"); M.combat = true
    eq(ns.UI.keys._kb, false)
    eq(#M.blocked, 0)
  end)
  it("Records sheet lists top runs and lifetime stats", function()
    local M, ns = boot(nil)
    ns.App:Start("blitz"); ns.App.session:finish("time"); playFrames(M, 1)
    ns.App:Start("blitz")
    for _ = 1, 3 do key(ns, "SPACE") end
    playFrames(M, 200); key(ns, "SPACE"); playFrames(M, 5); ns.App.session:finish("time"); playFrames(M, 1)
    ns.App:ShowMenu()
    ns.UI:ShowSheet("records")
    ok(ns.UI.records:IsShown())
    local card = ns.UI.records.cards[2]
    eq(card.stats[1]:GetText(), "2", "Blitz runs")
    ok(card.best:GetText() ~= "-", "best shown")
    eq(ns.UI.records.cards[1].top[1].sc:GetText(), "No runs yet")
  end)
  it("window never gets bigger than the screen", function()
    local M, ns = boot(nil)
    UIParent:SetSize(800, 450)
    SlashCmdList.STACKRIVALS("")
    ok(StackRivalsFrame._scale < 1 and StackRivalsFrame._scale * ns.UI.H <= 450, "scale " .. StackRivalsFrame._scale)
    eq(ns.db.settings.scale, 1.0, "saved preference untouched")
  end)
end)

describe("0.3.0 polish", function()
  it("game over: hard-drop key plays again only after a 1 s grace; other keys go to WoW", function()
    local M, ns = boot(nil)
    ns.App:Start("blitz"); playFrames(M, 181)
    ns.App.session:finish("time"); playFrames(M, 1)
    local down = ns.UI.keys:GetScript("OnKeyDown")
    eq(ns.UI.keys._kb, false, "not listening during the grace period")
    playFrames(M, 61)
    eq(ns.UI.keys._kb, true, "listening after 1 s")
    down(ns.UI.keys, "W"); eq(ns.UI.keys._prop, true)
    eq(ns.App.session.phase, "over")
    down(ns.UI.keys, "SPACE"); eq(ns.UI.keys._prop, false)
    eq(ns.App.session.phase, "countdown"); eq(ns.App.session.mode.key, "blitz")
  end)
  it("game over: Space is a normal WoW key again after 6 s, with the cursor away, after closing, and under Settings", function()
    local M, ns = boot(nil)
    ns.App:Start("blitz"); playFrames(M, 181); ns.App.session:finish("time"); playFrames(M, 63)
    eq(ns.UI.keys._kb, true)
    -- cursor elsewhere: Space jumps in WoW and doesn't start a run
    M.mouseOver = false
    local down = ns.UI.keys:GetScript("OnKeyDown")
    down(ns.UI.keys, "SPACE"); eq(ns.UI.keys._prop, true, "passed to WoW"); eq(ns.App.session.phase, "over")
    M.mouseOver = nil
    playFrames(M, 4 * 60)
    eq(ns.UI.keys._kb, true, "still listening at 5 s")
    playFrames(M, 2 * 60)
    eq(ns.UI.keys._kb, false, "stopped listening after the window")
    -- reopen: no listening
    ns.App:Start("blitz"); playFrames(M, 181); ns.App.session:finish("time"); playFrames(M, 63)
    SlashCmdList.STACKRIVALS(""); SlashCmdList.STACKRIVALS("")
    eq(ns.UI.keys._kb, false, "not after closing and reopening")
    -- Settings over the result: Space must not start a run
    ns.App:Start("blitz"); playFrames(M, 181); ns.App.session:finish("time"); playFrames(M, 63)
    ns.UI:ShowSettings(true)
    eq(ns.UI.keys._kb, false, "Settings open: not listening")
    eq(ns.App.session.phase, "over")
  end)
  it("HUD best value is cleared after Quit to menu (no stale cached text)", function()
    local M, ns = boot(nil)
    ns.App:Start("blitz"); playFrames(M, 181); ns.App.session.state.score = 5000
    ns.App.session:finish("time"); playFrames(M, 2)
    ns.App:Quit(); playFrames(M, 2)
    eq(ns.UI.bestText:GetText(), "-")
    ns.App:Start("classic"); playFrames(M, 2); ns.App:Quit(); playFrames(M, 2)
    eq(ns.UI.bestText:GetText(), "-")
    ns.App:Start("blitz"); playFrames(M, 2)
    eq(ns.UI.bestText:GetText(), "5,000")
  end)
  it("daily button shows when the pieces change (UTC midnight)", function()
    local M, ns = boot(nil)
    SlashCmdList.STACKRIVALS("")
    local txt = ns.UI.modeButtons.daily.side:GetText()
    ok(txt:find("^new pieces in %d+h %d%dm$") ~= nil, txt)
    ok(ns.UI.modeButtons.daily.tip:find("00:00 UTC") ~= nil)
    local left = ns.App:SecondsToUtcMidnight()
    ok(left > 0 and left <= 86400)
  end)
  it("diagnostics record the client build and interface in SavedVariables", function()
    local M, ns = boot(nil)
    local c = StackRivalsDB.diag.clients["16001"]
    ok(c, "client entry")
    eq(c.interface, 16001); eq(c.build, "70338"); eq(c.loads, 1)
    local M2, ns2 = boot(StackRivalsDB)
    eq(StackRivalsDB.diag.clients["16001"].loads, 2); eq(StackRivalsDB.diag.loads, 2)
  end)
  it("UI scale / resolution change re-fits the window", function()
    local M, ns = boot(nil)
    SlashCmdList.STACKRIVALS("")
    local auto = ns.UI.autoScale
    ok(math.abs(StackRivalsFrame._scale - auto) < 1e-9 and auto > 0.95 and auto < 1.1, "100% = fitted to a 768-high UI")
    UIParent:SetSize(700, 400)
    M.fire("UI_SCALE_CHANGED")
    playFrames(M, 1)
    ok(StackRivalsFrame._scale < 1)
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
    eq(ns.db.settings.scale, 1.3); ok(math.abs(StackRivalsFrame._scale - 1.3 * ns.UI.autoScale) < 1e-9)
    SlashCmdList.STACKRIVALS("scale 9")
    eq(ns.db.settings.scale, 1.4, "clamped")
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
