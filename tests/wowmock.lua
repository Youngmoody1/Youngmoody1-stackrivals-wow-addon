--[[
  Minimal, STRICT mock of the WoW UI API, just enough to load the whole addon outside the game
  and drive it like a player: frames, textures, font strings, buttons, events, keyboard, combat.

  Strict on purpose: calling a widget method that the mock doesn't know raises an error, so a
  typo or an API we never verified shows up here instead of as a Lua error in the client.
  It does NOT prove the addon works in WoW (rendering, real API quirks) - that needs the client.
]]
local M = { events = {}, frames = {}, regions = {}, log = {}, combat = false, time = 0, blocked = {} }

local function strict(obj, kind)
  return setmetatable(obj, {
    -- WoW API methods are PascalCase: an unknown one is an error. Lowercase keys are the
    -- addon's own fields on its frames, which read as nil in WoW too.
    __index = function(_, k)
      if type(k) == "string" and k:match("^%u") then
        error("mock: " .. kind .. " has no method '" .. k .. "'", 2)
      end
      return nil
    end,
  })
end

local region = {}
function region.SetPoint(o, ...) o._points[#o._points + 1] = { ... } end
function region.ClearAllPoints(o) o._points = {} end
function region.SetAllPoints(o, rel) o._points = { "ALL" }; o._allRel = rel end
function region.GetPoint(o, i) local p = o._points[i or 1]; if type(p) == "table" then return p[1], p[2], p[3] or p[1], p[4] or 0, p[5] or 0 end return "CENTER", nil, "CENTER", 0, 0 end
function region.SetSize(o, w, h) o._w, o._h = w, h end
function region.SetWidth(o, w) o._w = w end
function region.SetHeight(o, h) o._h = h end
function region.GetWidth(o) return o._w or 0 end
function region.GetHeight(o) return o._h or 0 end
function region.Show(o) o:SetShown(true) end
function region.Hide(o) o:SetShown(false) end
function region.IsShown(o) return o._shown end
function region.SetAlpha(o, a) o._alpha = a end
function region.GetAlpha(o) return o._alpha end

local function newRegion(kind, extra)
  local o = { _points = {}, _shown = true, _alpha = 1, _kind = kind }
  for k, v in pairs(region) do o[k] = v end
  o.SetShown = function(self, v) self._shown = v and true or false end
  for k, v in pairs(extra) do o[k] = v end
  return o
end

local order = 0
local function nextOrder() order = order + 1; return order end

local function newTexture(parent, layer, sub)
  return strict(newRegion("Texture", {
    _parent = parent, _layer = layer or "ARTWORK", _sub = sub or 0, _order = nextOrder(),
    SetColorTexture = function(o, r, g, b, a) assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "SetColorTexture needs numbers"); o._r, o._g, o._b, o._a = r, g, b, a end,
    SetTexture = function(o, path) o._tex = path end,
    SetDrawLayer = function() end,
  }), "Texture")
end

local function newFontString(parent, layer)
  return strict(newRegion("FontString", {
    _parent = parent, _layer = layer or "OVERLAY", _sub = 0, _order = nextOrder(),
    SetFont = function(o, f, s, fl) assert(type(f) == "string" and type(s) == "number", "SetFont(path, size)"); o._font = { f, s, fl } end,
    SetText = function(o, t) o._text = t end,
    GetText = function(o) return o._text end,
    SetTextColor = function(o, r, g, b) o._tr, o._tg, o._tb = r, g, b end,
    SetShadowColor = function() end,
    SetShadowOffset = function() end,
    SetJustifyH = function(o, j) o._justify = j end,
    SetJustifyV = function() end,
    SetSpacing = function() end,
  }), "FontString")
end

local KNOWN_EVENTS = {
  ADDON_LOADED = 1, PLAYER_LOGIN = 1, PLAYER_LOGOUT = 1, PLAYER_REGEN_DISABLED = 1, PLAYER_REGEN_ENABLED = 1,
  LOADING_SCREEN_ENABLED = 1, PLAYER_LEAVING_WORLD = 1, PLAYER_DEAD = 1,
  DISPLAY_SIZE_CHANGED = 1, UI_SCALE_CHANGED = 1,
}

local function newFrame(ftype, name, parent)
  local f
  f = newRegion(ftype, {
    _scripts = {}, _parent = parent, _level = parent and (parent._level or 0) + 1 or 0, _kb = false, _prop = false,
    _scale = 1, _enabled = true, _order = nextOrder(), _name = name,
    SetScript = function(o, ev, fn) o._scripts[ev] = fn end,
    GetScript = function(o, ev) return o._scripts[ev] end,
    HookScript = function(o, ev, fn) local old = o._scripts[ev]; o._scripts[ev] = function(...) if old then old(...) end fn(...) end end,
    SetFrameStrata = function() end,
    SetFrameLevel = function(o, l) o._level = l end,
    GetFrameLevel = function(o) return o._level end,
    SetToplevel = function() end,
    SetDontSavePosition = function() end,
    SetClampedToScreen = function() end,
    SetMovable = function() end,
    EnableMouse = function() end,
    RegisterForDrag = function() end,
    StartMoving = function() end,
    StopMovingOrSizing = function() end,
    SetScale = function(o, s) o._scale = s end,
    GetEffectiveScale = function(o) return o._scale end,
    GetCenter = function() return 100, 100 end,
    CreateTexture = function(o, _, layer, _, sub) local t = newTexture(o, layer, sub); M.regions[#M.regions + 1] = t; return t end,
    CreateFontString = function(o, _, layer) local t = newFontString(o, layer); M.regions[#M.regions + 1] = t; return t end,
    EnableKeyboard = function(o, v)
      if M.combat then M.blocked[#M.blocked + 1] = "EnableKeyboard"; error("ADDON_ACTION_BLOCKED EnableKeyboard") end
      o._kb = v and true or false
    end,
    SetPropagateKeyboardInput = function(o, v)
      if M.combat then M.blocked[#M.blocked + 1] = "SetPropagateKeyboardInput"; error("ADDON_ACTION_BLOCKED SetPropagateKeyboardInput") end
      o._prop = v and true or false
    end,
    RegisterEvent = function(o, ev)
      if not KNOWN_EVENTS[ev] then error("Attempt to register unknown event \"" .. ev .. "\"") end
      M.events[ev] = M.events[ev] or {}
      table.insert(M.events[ev], o)
    end,
    UnregisterEvent = function() end,
  })
  f.SetShown = function(self, v)
    v = v and true or false
    if self._shown == v then return end
    self._shown = v
    local s = self._scripts[v and "OnShow" or "OnHide"]
    if s then s(self) end
  end
  if ftype == "Button" then
    f.RegisterForClicks = function() end
    f.SetHighlightTexture = function() end
    f.Enable = function(o) o._enabled = true; local s = o._scripts.OnEnable; if s then s(o) end end
    f.Disable = function(o) o._enabled = false; local s = o._scripts.OnDisable; if s then s(o) end end
    f.IsEnabled = function(o) return o._enabled end
    f.SetEnabled = function(o, v) if v then o:Enable() else o:Disable() end end
    f.Click = function(o, button) if o._enabled and o._scripts.OnClick then o._scripts.OnClick(o, button or "LeftButton") end end
  end
  f = strict(f, ftype .. "(" .. tostring(name) .. ")")
  M.frames[#M.frames + 1] = f
  if name then _G[name] = f end
  return f
end

function M.install()
  _G.CreateFrame = function(ftype, name, parent, template)
    assert(ftype == "Frame" or ftype == "Button", "mock: unsupported frame type " .. tostring(ftype))
    return newFrame(ftype, name, parent)
  end
  _G.UIParent = newFrame("Frame", "UIParent")
  UIParent:SetSize(1366, 768) -- a small laptop screen at default UI scale
  _G.Minimap = newFrame("Frame", "Minimap")
  Minimap:SetSize(140, 140)
  _G.GameTooltip = setmetatable({}, { __index = function() return function() end end })
  _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) M.log[#M.log + 1] = msg end }
  _G.UISpecialFrames = {}
  _G.SlashCmdList = {}
  _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
  _G.GetTime = function() return M.time end
  _G.InCombatLockdown = function() return M.combat end
  _G.UnitAffectingCombat = function() return M.combat end
  M.sounds = {}
  _G.PlaySoundFile = function(path, channel) M.sounds[#M.sounds + 1] = path; return true end
  _G.PlaySound = function() return true end
  _G.SOUNDKIT = { IG_MAINMENU_OPEN = 850 }
  _G.C_AddOns = { GetAddOnMetadata = function(_, field) if field == "Version" then return "0.1.0-test" end end }
  _G.GetBuildInfo = function() return "1.15.0", "70338", "Oct 2026", 16001 end
  _G.date = os.date
  _G.tinsert = table.insert
  _G.IsInGuild = function() return M.inGuild or false end
  _G.IsInGroup = function() return false end
  _G.IsInRaid = function() return false end
  M.chat = {}
  _G.C_ChatInfo = { SendChatMessage = function(msg, channel) M.chat[#M.chat + 1] = { msg, channel } end }
  _G.GetCursorPosition = function() return 0, 0 end
end

--- Fire a game event to every frame that registered it.
function M.fire(ev, ...)
  for _, f in ipairs(M.events[ev] or {}) do
    local s = f._scripts.OnEvent
    if s then s(f, ev, ...) end
  end
end

--- Advance real time by n frames of dt seconds, calling every visible frame's OnUpdate.
function M.frames_step(n, dt)
  dt = dt or (1 / 60)
  for _ = 1, n do
    M.time = M.time + dt
    for _, f in ipairs(M.frames) do
      local s = f._scripts.OnUpdate
      if s and f._shown then s(f, dt) end
    end
  end
end

return M
