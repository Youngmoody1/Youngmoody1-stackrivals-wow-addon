--[[
  StackRivals - effects in three tiers, so the size of the feedback matches the size of the moment.

    SMALL   (every piece)      hard drop: the four landed cells flash for 0.14 s. No text, never in the way.
    MEDIUM  (every few pieces) line clears, combos, spells: the callouts and flashes in Window.lua / SpellUI.lua;
                               here: the last 10 seconds of a timed run (red rim pulse + a tick on 5..1).
    BIG     (rare)             QUAD, BACK-TO-BACK, a long combo, a new best, a win, a Loot Duel win: a glow
                               burst behind the callout / the result.

  Rules: client-side AnimationGroups only (no Lua per frame); a handful of pooled textures; everything stops
  in UI:ClearFx (another run, the result, the window hiding). "Reduce effects" (Settings) keeps the texts and
  sounds and drops the flashes, bursts and the pulsing rim.
]]
local _, ns = ...
local T = ns.T
local C = T.C
local UI = ns.UI

local Fx = {}
UI.fx = Fx

local function reduced() return ns.db and ns.db.settings and ns.db.settings.reduceEffects == true end

local function alphaAnim(region, from, to, dur, smoothing)
  local g = region:CreateAnimationGroup()
  local a = g:CreateAnimation("Alpha")
  a:SetFromAlpha(from); a:SetToAlpha(to); a:SetDuration(dur); a:SetOrder(1)
  if smoothing and a.SetSmoothing then a:SetSmoothing(smoothing) end
  return g
end

function UI:FxInit()
  if Fx.ready or not self.field then return Fx.ready end
  Fx.ready = true
  local field = self.field
  local layer = CreateFrame("Frame", nil, field)
  layer:SetAllPoints(field)
  layer:SetFrameLevel(field:GetFrameLevel() + 2) -- over the cells, under the callouts (+5) and overlays
  Fx.layer = layer

  -- SMALL: four cell flashes (base alpha 0: an interrupted animation can't leave one lit)
  Fx.lock = {}
  for i = 1, 4 do
    local t = T.tex(layer, "OVERLAY", C.paper, 1)
    t:SetAlpha(0)
    Fx.lock[i] = { t = t, g = alphaAnim(t, 0.5, 0, 0.14, "OUT") }
  end

  -- BIG: a soft glow that grows and fades (Media/glow.tga, additive)
  -- (one behind the line-clear callout, one behind the result: no re-parenting at run time)
  local function burst(parent, drawLayer, anchor, dy)
    local b = parent:CreateTexture(nil, drawLayer)
    b:SetTexture(T.MEDIA .. "glow")
    b:SetBlendMode("ADD")
    b:SetSize(field:GetWidth() * 1.25, 150)
    b:SetPoint("CENTER", anchor, "CENTER", 0, dy)
    b:SetAlpha(0)
    local bg = b:CreateAnimationGroup()
    local sc = bg:CreateAnimation("Scale")
    sc:SetDuration(0.6); sc:SetOrder(1)
    if sc.SetScaleFrom then sc:SetScaleFrom(0.55, 0.55); sc:SetScaleTo(1.45, 1.45) end
    if sc.SetSmoothing then sc:SetSmoothing("OUT") end
    local al = bg:CreateAnimation("Alpha")
    al:SetFromAlpha(0.65); al:SetToAlpha(0); al:SetDuration(0.6); al:SetOrder(1)
    return b, bg
  end
  Fx.burst, Fx.burstAnim = burst(layer, "OVERLAY", self.callout, -6)
  Fx.resultBurst, Fx.resultBurstAnim = burst(self.over, "BACKGROUND", self.overScore, 6)

  -- MEDIUM: the last seconds of a timed run: a red rim that breathes
  local rim = CreateFrame("Frame", nil, self.frame)
  rim:SetPoint("TOPLEFT", field, "TOPLEFT", -2, 2); rim:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", 2, -2)
  rim:SetFrameLevel(field:GetFrameLevel() + 1)
  for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 }, { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
    local l = T.tex(rim, "OVERLAY", C.redLight, 1)
    l:SetPoint(side[1]); l:SetPoint(side[2])
    if side[3] then l:SetWidth(side[3]) else l:SetHeight(side[4]) end
  end
  rim:SetAlpha(0)
  local dg = alphaAnim(rim, 0.15, 0.75, 0.5, "IN_OUT")
  if dg.SetLooping then dg:SetLooping("BOUNCE") end
  Fx.danger, Fx.dangerAnim = rim, dg
  return true
end

--- SMALL: flash the cells a hard-dropped piece landed on. drop = { id, rotation, x, y } (y = landing row).
function UI:FxLock(drop)
  if reduced() or not (drop and drop.y) or not self:FxInit() then return end
  local field = self.field
  local shape = ns.Pieces.SHAPES[drop.id] and ns.Pieces.SHAPES[drop.id][drop.rotation + 1]
  local sess = ns.App.session
  if not (shape and sess) then return end
  local hidden = sess.state.config.hiddenRows
  for k = 1, 4 do
    local slot, c = Fx.lock[k], shape[k]
    local cell = c and field.cells[(drop.y + c[2] - hidden) * field.width + drop.x + c[1] + 1]
    if cell and drop.y + c[2] - hidden >= 0 and drop.x + c[1] >= 0 and drop.x + c[1] < field.width then
      slot.t:ClearAllPoints(); slot.t:SetAllPoints(cell.base)
      slot.g:Stop(); slot.g:Play()
    end
  end
end

--- BIG: a glow burst. where: "callout" (behind the line-clear callout) or "result" (behind the result title).
function UI:FxBurst(color, where)
  if reduced() or not self:FxInit() then return end
  local b, g = Fx.burst, Fx.burstAnim
  if where == "result" then b, g = Fx.resultBurst, Fx.resultBurstAnim end
  color = color or C.gold
  b:SetVertexColor(color[1], color[2], color[3])
  g:Stop(); g:Play()
end

--- MEDIUM: the red rim of the last 10 seconds (on / off; safe to call every frame).
function UI:FxDanger(on)
  on = on and not reduced() or false
  if Fx.dangerOn == on then return end
  if on and not self:FxInit() then return end
  Fx.dangerOn = on
  if not Fx.ready then return end
  Fx.dangerAnim:Stop()
  Fx.danger:SetAlpha(0)
  if on then Fx.dangerAnim:Play() end
end

--- Session events (called first in UI:OnEvent).
function UI:FxEvent(ev)
  local k = ev.kind
  if k == "harddrop" then
    self:FxLock(ev.b)
  elseif k == "clear" then
    local info = ev.b or {}
    if ev.a >= 4 or info.backToBack then
      self:FxBurst(C.gold, "callout")
    elseif (info.combo or 0) >= 4 then
      self:FxBurst(C.steel, "callout") -- a long combo is a big moment too
    end
  end
end

--- A win, a new best, a Loot Duel win: the glow behind the result.
function UI:FxResult(kind)
  if kind == "win" or kind == "best" then self:FxBurst(kind == "best" and C.gold or C.green, "result") end
end

function UI:FxClear()
  if not Fx.ready then return end
  for _, slot in ipairs(Fx.lock) do slot.g:Stop(); slot.t:SetAlpha(0) end
  Fx.burstAnim:Stop(); Fx.burst:SetAlpha(0)
  -- (the result's own burst plays over the result screen: it ends by itself)
  self:FxDanger(false)
end

-- Built once with the window (never during play: tests/test_design.lua counts animation groups).
local create = UI.Create
function UI:Create(...)
  local had = self.frame ~= nil
  local r = create(self, ...)
  if not had and self.frame then self:FxInit() end
  return r
end
