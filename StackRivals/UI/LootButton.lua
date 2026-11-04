--[[
  StackRivals - Loot Duel quick access: a small gold "Loot Duel" button near the group frames, so a
  party or raid leader can open the Loot Duel lobby without the main menu first.

  Safe by design (works the same in every client):
    * its OWN plain button on UIParent: it never parents to, hooks or moves Blizzard's party / raid
      frames (protected frames), so it can't taint them or break in combat;
    * shown only in a party or raid, and hidden in combat (the lobby can't start a race then);
    * a click only OPENS the lobby: no invite, no message is sent;
    * Shift + drag moves it (the place is saved), right-click hides it; Settings or
      "/sr lootbutton" shows it again, "/sr lootbutton reset" puts it back.
]]
local _, ns = ...
local T = ns.T
local C = T.C

local LB = {}
ns.LootButton = LB
-- default place: top left, between the player frame and the first party frame (UI units)
LB.DEFAULT = { point = "TOPLEFT", x = 18, y = -112 }

local function settings() return ns.db and ns.db.settings or {} end
local function inCombat() return (ns.UI and ns.UI.inCombat and ns.UI.inCombat()) or (InCombatLockdown and InCombatLockdown()) or false end
local function inGroup() return ns.LootDuel and ns.LootDuel.channel() ~= nil end

function LB:Place()
  local b = self.button
  if not b then return end
  local pos = settings().lootButtonPos or LB.DEFAULT
  b:ClearAllPoints()
  b:SetPoint(pos.point or "TOPLEFT", UIParent, pos.point or "TOPLEFT", pos.x or LB.DEFAULT.x, pos.y or LB.DEFAULT.y)
end

function LB:Create()
  if self.button or not UIParent then return end
  if ns.BUILD and not ns.BUILD.duels then return end -- vs-Bot test build: no Loot Duel
  local b = CreateFrame("Button", "StackRivalsLootDuelButton", UIParent)
  self.button = b
  b:SetSize(96, 24)
  b:SetFrameStrata("MEDIUM")
  b:SetClampedToScreen(true)
  b:SetMovable(true)
  b:EnableMouse(true)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  local bg = T.tex(b, "BACKGROUND", C.navy, 0.92); bg:SetAllPoints()
  b.edge = T.tex(b, "BORDER", C.gold, 1); b.edge:SetPoint("TOPLEFT", 0, 0); b.edge:SetPoint("BOTTOMLEFT", 0, 0); b.edge:SetWidth(3)
  local line = T.tex(b, "BORDER", C.goldDeep, 1); line:SetPoint("BOTTOMLEFT", 3, 0); line:SetPoint("BOTTOMRIGHT", 0, 0); line:SetHeight(1)
  b.hl = T.tex(b, "ARTWORK", C.gold, 0); b.hl:SetAllPoints()
  b.icon = b:CreateTexture(nil, "OVERLAY"); b.icon:SetSize(18, 18); b.icon:SetPoint("LEFT", 6, 0); b.icon:SetTexture(T.MEDIA .. "lootduel")
  b.label = T.text(b, T.SIZE.label, C.gold); b.label:SetPoint("LEFT", 28, 0); b.label:SetText("Loot Duel")
  b:SetScript("OnEnter", function(self)
    self.hl:SetAlpha(0.12)
    if GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("StackRivals: Loot Duel")
      GameTooltip:AddLine("Race your group for an item instead of /roll: 2-10 players at once, same pieces.", 1, 1, 1, true)
      GameTooltip:AddLine("Click: open the lobby (nothing is sent). Shift + drag: move. Right-click: hide (Settings shows it again).", 0.75, 0.75, 0.75, true)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self) self.hl:SetAlpha(0); if GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown and IsShiftKeyDown() and not inCombat() then self.moving = true; self:StartMoving() end
  end)
  b:SetScript("OnDragStop", function(self)
    if not self.moving then return end
    self.moving = false
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint(1)
    if type(x) == "number" and type(y) == "number" then
      ns.db.settings.lootButtonPos = { point = point or "TOPLEFT", x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
      LB:Place() -- re-anchor to UIParent with the saved offsets
    end
  end)
  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      ns.db.settings.lootButton = false
      LB:Update()
      if ns.App and ns.App.Print then ns.App:Print("Loot Duel button hidden. Settings or /sr lootbutton shows it again.") end
      return
    end
    LB:Open()
  end)
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PARTY_LEADER_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
  end
  ev:SetScript("OnEvent", function() LB:Update() end)
  self:Place()
  self:Update()
end

--- Open the StackRivals window on the Loot Duel lobby (sends nothing).
function LB:Open()
  local UI = ns.UI
  if not UI then return end
  if inCombat() then
    if ns.App and ns.App.Print then ns.App:Print("Loot Duel opens after combat.") end
    return
  end
  UI:Create()
  if not UI.frame:IsShown() then UI.frame:Show() end
  UI:ShowSheet("loot")
end

--- Shown only when the setting is on, you're in a party or raid, and not in combat.
function LB:Update()
  local b = self.button
  if not b then return end
  local show = settings().lootButton ~= false and inGroup() and not inCombat()
  b:SetShown(show and true or false)
end

--- /sr lootbutton [reset]
function LB:Toggle(arg)
  if arg == "reset" then
    ns.db.settings.lootButtonPos = nil
    ns.db.settings.lootButton = true
  else
    ns.db.settings.lootButton = not (ns.db.settings.lootButton ~= false)
  end
  self:Place(); self:Update()
  return ns.db.settings.lootButton ~= false
end
