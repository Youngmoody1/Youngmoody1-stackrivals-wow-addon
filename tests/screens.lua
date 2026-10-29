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
  { "8-records", "Records", function()
    local M, ns = boot(); seedRecords(ns); SlashCmdList.STACKRIVALS(""); ns.UI:ShowSheet("records"); M.frames_step(1); return M, ns
  end },
}

return S
