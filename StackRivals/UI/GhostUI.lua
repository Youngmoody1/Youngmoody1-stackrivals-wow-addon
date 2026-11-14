--[[
  StackRivals - Race My Best on screen (Core/Ghost.lua has the logic):
    * the menu: a RACE MY BEST button on the Classic and Time Trial cards (only when there is a run that
      replays exactly; otherwise greyed, with the reason as its tooltip);
    * during the race: a panel under NEXT, in the rival style (steel = the other side): the best run's
      score now, how far it is (level, lines, or its final score once it ended) and a tug-of-war bar;
      the stats panel says AHEAD / BEHIND / LEVEL with the difference, in green / red;
    * the moments: passing your best's pace (a pulse), beating its final score (the big effect, once:
      a gold burst and "NEW BEST"), and the result ("BEAT YOUR BEST +N" or how far off);
    * the panel can be hidden (its "-" button, or /sr best panel): the race still runs, the stats panel
      then shows your best's final score only.
  Effects go through UI/Fx.lua, so "Reduce effects" is respected; nothing here runs Lua per frame when the
  window is closed.
]]
local _, ns = ...
local T = ns.T
local C = T.C
local UI = ns.UI
local SZ = T.SIZE

local function panelWanted() return ns.db and ns.db.settings.raceBestPanel ~= false end

--- Is the Race My Best panel on screen now? (DuelUI shortens NEXT for it, as for a rival.)
function UI:GhostPanelShown()
  local s = ns.App.session
  return s ~= nil and s.mode.ghost == true and not ns.App.inMenu and panelWanted()
end

function UI:CreateGhost()
  if self.ghostPanel then return end
  local gp = T.panel(self.frame, C.steel)
  gp:SetSize(108, 72)
  gp:SetPoint("BOTTOMLEFT", self.field, "BOTTOMRIGHT", 12, 0)
  gp.name = T.label(gp, "YOUR BEST"); gp.name:SetPoint("TOPLEFT", 10, -9); gp.name:SetJustifyH("LEFT")
  gp.name:SetTextColor(C.steel[1], C.steel[2], C.steel[3])
  local scoreBox = CreateFrame("Frame", nil, gp)
  scoreBox:SetSize(88, 22); scoreBox:SetPoint("TOPLEFT", 8, -22)
  gp.score = T.display(scoreBox, SZ.title, C.steel); gp.score:SetPoint("LEFT", 2, 0); gp.score:SetJustifyH("LEFT")
  gp.pulse = T.pulseAnim(scoreBox, 1.15, 0.25, "LEFT")
  gp.state = T.text(gp, SZ.label, C.label); gp.state:SetPoint("TOPLEFT", 10, -48); gp.state:SetJustifyH("LEFT")
  gp.state:SetWidth(90); gp.state:SetWordWrap(false)
  local track = T.tex(gp, "ARTWORK", C.line, 1); track:SetPoint("BOTTOMLEFT", 10, 6); track:SetSize(88, 3)
  gp.bar = T.tex(gp, "OVERLAY", C.red, 1); gp.bar:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT"); gp.bar:SetSize(44, 3)
  gp.hide = T.button(gp, "-", 16, 14, "frame", function()
    ns.db.settings.raceBestPanel = false
    UI:RefreshPhase()
  end)
  gp.hide:SetPoint("TOPRIGHT", gp, "TOPRIGHT", -4, -4)
  gp.hide.tip = "Hide this panel (the race goes on). Show it again with the + next to YOUR BEST."
  gp:Hide()
  self.ghostPanel = gp
  -- "+" beside the stats panel's label: the panel back
  local show = T.button(self.stats, "+", 16, 14, "frame", function()
    ns.db.settings.raceBestPanel = true
    UI:RefreshPhase()
  end)
  show:SetPoint("TOPRIGHT", self.stats, "TOPRIGHT", -6, -58)
  show.tip = "Show the Race My Best panel"
  show:Hide()
  self.ghostShow = show
end

--- Panel visibility (from RefreshPhase / RefreshDuel).
function UI:RefreshGhost()
  if not self.ghostPanel then return end
  local s = ns.App.session
  local racing = s ~= nil and s.mode.ghost == true and not ns.App.inMenu
  self.ghostPanel:SetShown(racing and panelWanted())
  self.ghostShow:SetShown(racing and not panelWanted())
end

local function lineOf(gs, done, final, runnerDone)
  if done then return runnerDone and (gs.gameOver and "topped out" or "finished") or "its final score" end
  return "LV " .. gs.level .. "  -  " .. gs.lines .. " lines"
end

--- Every frame of a race (from UI:Render). Cheap: the ghost advances as many ticks as the run did.
function UI:RenderGhost(sess)
  local g = sess.ghost
  local my = sess.state.score
  if not g or g.lost or not g.runner then
    self:SetStatLabel("BEST", C.gold)
    self:SetStatText("-")
    if self.ghostPanel:IsShown() then
      self.ghostPanel.score:SetText("-"); self.ghostPanel.state:SetText("no ghost (changed)")
    end
    return
  end
  local lead, gs = ns.Ghost.lead(sess)
  local final = g.entry.score
  -- once my run is over, the comparison is with the best's final score (as in the result)
  local done = g.runner.done or sess.phase == "over"
  -- the big moment, once per race: past your best's FINAL score (it can't come back)
  if my > final and not g.beaten and sess.phase == "playing" then
    g.beaten = true
    self:Callout("NEW BEST", "PERSONAL RECORD", C.gold, nil, "huge")
    self:FxBurst(C.gold, "callout")
    ns.Sound.play("levelup")
  end
  if not panelWanted() then
    self:SetStatLabel("YOUR BEST", C.gold)
    self:SetStatText(T.commas(final))
    self:SetStatColor(C.gold)
    return
  end
  -- stats panel: ahead / behind your best at this very moment (its final score once it ended)
  local cmp = done and (my - final) or lead
  local word = (cmp > 0 and "AHEAD") or (cmp < 0 and "BEHIND") or "LEVEL"
  local c = (cmp > 0 and C.green) or (cmp < 0 and C.redLight) or C.paper
  self:SetStatLabel(word, c)
  self:SetStatText((cmp > 0 and "+" or (cmp < 0 and "-" or "")) .. T.commas(math.abs(cmp)))
  self:SetStatColor(c)
  -- passing your best's pace (after being behind): a short pulse, no text over the board
  local ahead = cmp > 0
  if ahead and g.wasBehind and sess.phase == "playing" then self.ghostPanel.pulse:Stop(); self.ghostPanel.pulse:Play() end
  if cmp < 0 then g.wasBehind = true elseif ahead then g.wasBehind = false end
  -- the panel
  local gp = self.ghostPanel
  local shown = done and final or gs.score
  if gp.kScore ~= shown then gp.kScore = shown; gp.score:SetText(T.commas(shown)) end
  local st = lineOf(gs, done, final, g.runner.done)
  if gp.kState ~= st then gp.kState = st; gp.state:SetText(st) end
  local sc = (cmp < 0) and C.redLight or C.steel
  if gp.kC ~= sc then gp.kC = sc; gp.score:SetTextColor(sc[1], sc[2], sc[3]) end
  local total = my + shown
  local w = math.max(1, math.floor(88 * (total > 0 and (my / total) or 0.5) + 0.5))
  if gp.kW ~= w then gp.kW = w; gp.bar:SetWidth(w) end
end

--- The stats panel's label (BEST / AHEAD / BEHIND / ...), set only on a change.
function UI:SetStatText(txt)
  if self.bestText._s ~= txt then self.bestText._s, self.bestText._n = txt, nil; self.bestText:SetText(txt) end
end
function UI:SetStatLabel(txt, c)
  if self.bestLabel._s ~= txt then self.bestLabel._s, self.bestLabel._n = txt, nil; self.bestLabel:SetText(txt) end
  if c and self.bestLabel._c ~= c then self.bestLabel._c = c; self.bestLabel:SetTextColor(c[1], c[2], c[3]) end
end
function UI:SetStatColor(c)
  if self.bestText._c ~= c then self.bestText._c = c; self.bestText:SetTextColor(c[1], c[2], c[3]) end
end

--- The result of a race (from ShowOver). gr = Ghost.finish's result.
function UI:ShowGhostOver(info)
  local gr, s = info.ghost, info.state
  self.badgePulse:Stop()
  local detail
  if gr.lost then
    self.overBadge:SetText("NO GHOST")
    detail = "Your best changed while this run was saved, so it had no ghost."
  elseif gr.beat then
    self.overBadge:SetText("BEAT YOUR BEST  +" .. T.commas(gr.me - gr.best))
    self.badgePulse:Play(); self:FxResult("best")
    detail = gr.saved and "Your next race is against this run." or "Too long to keep as the next one to race."
  elseif gr.tie then
    self.overBadge:SetText("TIED YOUR BEST")
    detail = "Same score as your best."
  else
    self.overBadge:SetText("YOUR BEST " .. T.commas(gr.best) .. "  (-" .. T.commas(gr.best - gr.me) .. ")")
    self.overBadge:SetTextColor(C.steel[1], C.steel[2], C.steel[3])
    detail = "Your best stays the one to beat."
  end
  self.overDetail:SetText(string.format("%d lines  -  level %d\n%s", s.lines, s.level, detail))
end

-- Menu: RACE MY BEST on the Classic and Time Trial cards
local createMenu = UI.CreateMenu
function UI:CreateMenu(...)
  local r = createMenu(self, ...)
  for base in pairs(ns.Ghost.MODES) do
    local card = self.modeButtons and self.modeButtons[base]
    if card then
      local b = T.button(card, "RACE MY BEST", 96, 16, "frame", function() ns.App:StartGhost(base) end)
      T.setFont(b.fs, T.DISPLAY, SZ.label)
      b.fs:SetTextColor(C.steel[1], C.steel[2], C.steel[3])
      b:SetPoint("TOPRIGHT", -12, -28)
      b:SetFrameLevel(card:GetFrameLevel() + 2)
      card.race = b
    end
  end
  return r
end

local refreshMenu = UI.RefreshMenu
function UI:RefreshMenu(...)
  local r = refreshMenu(self, ...)
  if not self.modeButtons then return r end
  for base in pairs(ns.Ghost.MODES) do
    local card = self.modeButtons[base]
    local b = card and card.race
    if b then
      local e, why = ns.Ghost.source(ns.db, base)
      if e and ns.Ghost.knownBad(e.id) then why = ns.Ghost.knownBad(e.id); e = nil end
      local rec = ns.db.records[base]
      b:SetShown(e ~= nil or (rec and rec.best > 0))
      local lc = (e and not UI.inCombat()) and C.steel or C.label
      b.fs:SetTextColor(lc[1], lc[2], lc[3])
      if e and not UI.inCombat() then
        b:Enable()
        b.tip = "Race My Best: the same pieces as your best run (" .. T.commas(e.score) .. "), replayed beside you. "
          .. "Local only: never changes your records, no XP or Shards."
      else
        b:Disable()
        b.tip = e and "Not in combat." or (ns.Ghost.WHY[why] or "No run to race yet.")
      end
    end
  end
  return r
end

-- Built once with the window, like the other panels (no widgets are made during play)
local create = UI.Create
function UI:Create(...)
  local had = self.frame ~= nil
  local r = create(self, ...)
  if not had and self.frame then self:CreateGhost() end
  return r
end
