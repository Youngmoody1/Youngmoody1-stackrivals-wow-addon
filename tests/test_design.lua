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
    it(string.format("%dx%d at UI scale %.2f: fits, ~58%% of the screen height, text >= 11 px", pw, ph, us), function()
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

describe("brand lockup (same as stackrivals.io: red X mark, STACK white, RIVALS red)", function()
  it("the header wordmark is STACK in paper and RIVALS in the site's brand red, Chakra Petch Bold Italic, on every screen", function()
    local M, ns = boot()
    SlashCmdList.STACKRIVALS("")
    local UI = ns.UI
    local w = UI.wordmark
    eq(w:GetText(), "STACK|cffe0242fRIVALS|r", "RIVALS in #E0242F (--brand-red), nothing else coloured")
    local r, g, b = w:GetTextColor()
    eq(string.format("%02X%02X%02X", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)), "F6F4F0", "STACK in --foreground")
    ok(w:GetFont():find("ChakraPetch%-BoldItalic%.ttf"), "the site's wordmark font")
    ok(tostring(UI.mark._tex):find("mark$"), "the red X mark beside it")
    -- one shared header: the same lockup stays visible over the menu, a run, sheets and results
    local function shown() return w:IsShown() and UI.mark:IsShown() and UI.frame:IsShown() end
    ok(shown(), "menu")
    for _, sheet in ipairs({ "help", "records", "spell", "duel" }) do UI:ShowSheet(sheet); ok(shown(), sheet) end
    UI:ShowSettings(true); ok(shown(), "settings"); UI:ShowSettings(false)
    for _, mode in ipairs({ "classic", "blitz", "daily", "spellbot" }) do
      ns.App:Start(mode); M.frames_step(300); ok(shown(), mode)
      ns.App:Pause("manual"); ok(shown(), mode .. " paused"); ns.App:Quit()
    end
  end)
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

describe("game feel and menu behaviour", function()
  local function run(M, ns, mode)
    ns.App:Start(mode or "blitz"); M.frames_step(181)
    return ns.App.session
  end
  it("callouts are tiered: single is small and quiet, quad is the biggest and gold with the rim", function()
    local M, ns = boot()
    SlashCmdList.STACKRIVALS("")
    local s = run(M, ns)
    local UI, C = ns.UI, ns.T.C
    UI:OnEvent({ kind = "clear", a = 1, b = { points = 100, combo = 0 } })
    eq(select(2, UI.callout:GetFont()), ns.T.SIZE.title, "single at title size")
    UI:OnEvent({ kind = "clear", a = 4, b = { points = 800, combo = 2, backToBack = true } })
    eq(select(2, UI.callout:GetFont()), 34, "quad at 34")
    eq(UI.calloutTop:GetText(), "BACK-TO-BACK")
    eq(UI.callout2:GetText(), "COMBO \195\1513", "combo counted like the site (engine combo + 1)")
    local r, g, b = UI.callout:GetTextColor()
    ok(math.abs(r - C.gold[1]) < 1e-6 and math.abs(g - C.gold[2]) < 1e-6, "quad in gold")
    UI:OnEvent({ kind = "clear", a = 2, b = { points = 300, combo = 0 } })
    eq(UI.calloutTop:GetText(), "", "b2b line clears on the next callout")
    eq(UI.callout2:GetText(), "")
  end)
  it("the controls strip leaves the board at GO", function()
    local M, ns = boot({ saved = { seenHelp = false } })
    SlashCmdList.STACKRIVALS("")
    ns.App:Start("blitz"); M.frames_step(60)
    ok(ns.UI.controlsStrip:IsShown(), "shown during the first countdown")
    ok(ns.UI.controlsKeys:GetText():find("SPACE") or ns.UI.controlsKeys:GetText():find("Space"), "keys column has hard drop")
    M.frames_step(130)
    ok(not ns.UI.controlsStrip:IsShown(), "gone once the run starts")
  end)
  it("a brand-new player sees 'Start here' on Blitz; a returning player sees the best score", function()
    local M, ns = boot()
    SlashCmdList.STACKRIVALS("")
    eq(ns.UI.modeButtons.blitz.best:GetText(), "Start here")
    local s = run(M, ns); s.state.score = 4200; s:finish("time"); M.frames_step(2); ns.App:Quit(); M.frames_step(2)
    eq(ns.UI.modeButtons.blitz.best:GetText(), "4,200")
  end)
  it("Continue moves the cards down and names the mode", function()
    local M, ns = boot()
    SlashCmdList.STACKRIVALS("")
    local _, _, _, _, y0 = ns.UI.modeButtons.classic:GetPoint(1)
    ns.db.suspended = { mode = "classic", log = "", playSeconds = 30 }
    ns.UI:RefreshMenu()
    ok(ns.UI.continueBtn:IsShown())
    ok(ns.UI.continueBtn.fs:GetText():find("Classic"), ns.UI.continueBtn.fs:GetText())
    local _, _, _, _, y1 = ns.UI.modeButtons.classic:GetPoint(1)
    ok(y1 < y0, "cards moved down")
  end)
  it("menu says so when you're in combat", function()
    local M, ns = boot()
    SlashCmdList.STACKRIVALS("")
    M.combat = true; M.fire("PLAYER_REGEN_DISABLED"); M.frames_step(1)
    ns.UI:RefreshMenu()
    eq(ns.UI.statsLine:GetText(), "In combat. Play after the fight.")
    M.combat = false; M.fire("PLAYER_REGEN_ENABLED"); M.frames_step(1)
    SlashCmdList.STACKRIVALS(""); SlashCmdList.STACKRIVALS("")
    ok(not ns.UI.statsLine:GetText():find("In combat"), "line back to normal after the fight")
  end)
  it("game over: zero quads are not mentioned", function()
    local M, ns = boot()
    SlashCmdList.STACKRIVALS("")
    local s = run(M, ns); s:finish("time"); M.frames_step(2)
    ok(not ns.UI.overDetail:GetText():find("quad"), ns.UI.overDetail:GetText())
  end)
  it("window position is kept as a centre: changing the size doesn't move it; old saves still load", function()
    local M, ns = boot({ saved = { window = { cx = 1500, cy = 600 } } })
    SlashCmdList.STACKRIVALS("")
    local p, rel, rp, x, y = StackRivalsFrame:GetPoint(1)
    eq(p, "CENTER"); eq(rp, "BOTTOMLEFT")
    local sc = StackRivalsFrame._scale
    ok(math.abs(x * sc - 1500) < 1e-6 and math.abs(y * sc - 600) < 1e-6, "centre in UIParent units")
    ns.db.settings.scale = 1.3; ns.UI:ApplyScale()
    local _, _, _, x2, y2 = StackRivalsFrame:GetPoint(1)
    local sc2 = StackRivalsFrame._scale
    ok(math.abs(x2 * sc2 - 1500) < 1e-6 and math.abs(y2 * sc2 - 600) < 1e-6, "same centre after resizing")
    local M2, ns2 = boot({ saved = { window = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 40, y = -50 } } })
    SlashCmdList.STACKRIVALS("")
    local p2, _, rp2, x3, y3 = StackRivalsFrame:GetPoint(1)
    eq(p2, "TOPLEFT"); eq(x3, 40); eq(y3, -50)
    local M3, ns3 = boot({ saved = { window = { cx = "evil", cy = 1e9 } } })
    eq(ns3.db.window.cx, nil); ok(ns3.db.window.cy <= 20000, "clamped (the frame is also clamped to the screen)")
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
