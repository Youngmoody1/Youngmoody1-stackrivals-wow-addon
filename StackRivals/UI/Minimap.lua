--[[
  StackRivals - minimap button (no libraries). Left-click: open/close. Right-click: settings.
  Drag: move it around the minimap edge. Hide it in Settings or with /sr minimap.
]]
local _, ns = ...
local T = ns.T

local M = {}
ns.Minimap = M

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function place(btn, angle)
  local rad = math.rad(angle)
  local r = (Minimap:GetWidth() / 2) + 5
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
end

function M:Create()
  if self.button or not Minimap then return end
  local b = CreateFrame("Button", "StackRivalsMinimapButton", Minimap)
  self.button = b
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(T.MEDIA .. "mark")
  icon:SetSize(18, 18)
  icon:SetPoint("TOPLEFT", 7, -6)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      ns.UI:Create()
      if not ns.UI.frame:IsShown() then ns.UI.frame:Show() end
      ns.UI:ShowSettings(true)
    else
      ns.UI:Toggle()
    end
  end)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      local angle = math.deg(atan2(cy / scale - my, cx / scale - mx)) % 360
      ns.db.settings.minimapAngle = angle
      place(self, angle)
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("StackRivals", 1, 0.3, 0.35)
    GameTooltip:AddLine("Left-click: play", 1, 1, 1)
    GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
    GameTooltip:AddLine("Drag: move button", 0.6, 0.6, 0.6)
    local best = ns.App:BestFor("blitz")
    if best > 0 then GameTooltip:AddLine("Blitz best: " .. T.commas(best), 0.95, 0.81, 0.42) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  self:Update()
end

function M:Update()
  if not self.button then return end
  local s = ns.db.settings
  place(self.button, s.minimapAngle)
  self.button:SetShown(not s.minimapHide)
end
