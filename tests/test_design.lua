-- Design guardrails: readable at every resolution / UI scale, a type scale floor, the brand font
-- never makes text invisible, animations are built once. (Simulated: real WoW look still needs
-- in-client screenshots.)
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local L = dofile(testdir .. "/layout.lua")
local S = assert(loadfile(testdir .. "/screens.lua"))(root, testdir)
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe

local function tocFiles()
  local files = {}
  for line in io.lines(root .. "/StackRivals.toc") do
    if line ~= "" and not line:match("^##") then files[#files + 1] = (line:gsub("\\", "/")) end
  end
  return files
end

local function boot(opts)
  opts = opts or {}
  local M = dofile(testdir .. "/wowmock.lua")
  M.install()
  M.failFonts = opts.failFonts
  if opts.ui then UIParent:SetSize(opts.ui[1], opts.ui[2]) end
  _G.StackRivalsDB = opts.saved
  local ns = {}
  for _, f in ipairs(tocFiles()) do assert(loadfile(root .. "/" .. f))("StackRivals", ns) end
  M.fire("ADDON_LOADED", "StackRivals")
  M.fire("PLAYER_LOGIN")
  return M, ns
end

describe("size on real screens", function()
  -- physical resolution, WoW UI scale. UIParent (UI units) = physical * 768 / height / uiScale.
  local SETUPS = {
    { 1366, 768, 1.0 }, { 1920, 1080, 1.0 }, { 1920, 1080, 0.71 }, { 2560, 1440, 1.0 }, { 2560, 1440, 0.53 },
    { 3440, 1440, 0.64 }, { 3840, 2160, 0.36 }, { 3840, 2160, 1.0 }, { 1280, 800, 0.8 }, { 1024, 768, 1.15 },
  }
  for _, st in ipairs(SETUPS) do
    local pw, ph, us = st[1], st[2], st[3]
    it(string.format("%dx%d at UI scale %.2f: fits, ~62%% of the screen height, text >= 11 px", pw, ph, us), function()
      local uh = 768 / us
      local uw = pw * uh / ph
      for _, factor in ipairs({ 0.7, 1.0, 1.4 }) do
        local M, ns = boot({ ui = { uw, uh }, saved = { settings = { scale = factor } } })
        SlashCmdList.STACKRIVALS("")
        local sc = StackRivalsFrame._scale
        local physPerUnit = sc * ph / uh
        local wPx, hPx = ns.UI.W * physPerUnit, ns.UI.H * physPerUnit
        ok(wPx <= pw - 20 and hPx <= ph - 20, string.format("fits the screen (%.0fx%.0f px at %.0f%%)", wPx, hPx, factor * 100))
        if factor == 1.0 then
          local share = hPx / ph
          ok(share > 0.5 and share < 0.75, string.format("window is %.0f%% of the screen height", share * 100))
          local smallest = ns.T.SIZE.label * physPerUnit
          ok(smallest >= 10.5, string.format("smallest text %.1f px", smallest))
        end
      end
    end)
  end
end)

describe("type scale", function()
  for _, sc in ipairs(S.list) do
    it(sc[1] .. ": no visible text below the label size", function()
      local M, ns = sc[3]()
      local R, items = L.collect(M, StackRivalsFrame)
      local min = ns.T.SIZE.label
      local bad = {}
      for _, o in ipairs(items) do
        if o._kind == "FontString" and type(o._text) == "string" and o._text ~= "" and R.alpha(o) > 0.05 then
          if (o._font and o._font[2] or 0) < min then bad[#bad + 1] = string.format("%q at %s", o._text:sub(1, 30), tostring(o._font and o._font[2])) end
        end
      end
      if #bad > 0 then error(table.concat(bad, "; ")) end
    end)
  end
end)

describe("brand font", function()
  it("display text uses the bundled Chakra Petch; body text uses WoW's own font", function()
    local M, ns = boot()
    SlashCmdList.STACKRIVALS("")
    ok(ns.UI.scoreText:GetFont():find("ChakraPetch%-Bold%.ttf"), "score in the display font")
    ok(ns.UI.callout:GetFont():find("ChakraPetch%-BoldItalic%.ttf"), "callouts in the italic display font")
    eq(ns.UI.hint:GetFont(), "Fonts\\FRIZQT__.TTF", "body text in WoW's font (every locale)")
  end)
  it("if the font file can't be loaded, every text falls back to WoW's font (never invisible)", function()
    local M, ns = boot({ failFonts = true })
    SlashCmdList.STACKRIVALS("")
    ns.UI:ShowSheet("help"); ns.UI:ShowSheet("records"); ns.UI:ShowSettings(true); ns.UI:ShowSettings(false)
    ns.App:Start("blitz"); M.frames_step(200)
    local missing = 0
    for _, r in ipairs(M.regions) do
      if r._kind == "FontString" and not r._font then missing = missing + 1 end
    end
    eq(missing, 0, "font strings without a font")
    eq(ns.UI.scoreText:GetFont(), "Fonts\\FRIZQT__.TTF")
  end)
end)

describe("animations", function()
  it("are built once; a whole run only plays them (no per-frame or per-event allocation)", function()
    local M, ns = boot()
    SlashCmdList.STACKRIVALS("")
    local function groups()
      local n = 0
      for _, f in ipairs(M.frames) do n = n + #(f._groups or {}) end
      for _, r in ipairs(M.regions) do n = n + #(r._groups or {}) end
      return n
    end
    local before = groups()
    ok(before >= 8, "callout, score pop, score pulse, countdown, rim, pause, game over, badge, menu")
    ns.App:Start("blitz")
    local s = ns.App.session
    M.frames_step(181)
    for i = 1, 400 do
      if s.phase ~= "playing" then break end
      s:press(i % 3 == 0 and "hardDrop" or (i % 3 == 1 and "left" or "rotateCW")); M.frames_step(2); s:release("hardDrop"); s:release("left"); s:release("rotateCW")
    end
    s:finish("time"); M.frames_step(5)
    eq(groups(), before, "no new animation groups during play")
    ok((M.animPlays or 0) > 10, "animations played: " .. tostring(M.animPlays))
  end)
end)

return H
