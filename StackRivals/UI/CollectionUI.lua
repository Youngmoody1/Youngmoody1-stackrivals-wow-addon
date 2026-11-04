--[[
  StackRivals - Account > Collection tab: the website's Shards balance, events and cosmetics, from the SRP2
  profile code (spec: the website's docs/WOW_SRP2.md). DISPLAY ONLY:
    * Shards: the website's balance "as of" when the code was made; nothing is added, spent or bought here.
    * Events (Shard Storm, XP Overdrive): shown with the code's time; claimed only on stackrivals.io; a WoW match
      earns nothing from them.
    * Cosmetics: names from the website's catalog (Core/CosmeticsCatalog.lua); Equipped / Owned / Locked from
      the code. WoW draws no cosmetics yet; when it does, only from a VERIFIED (signed) code
      (Account.canApplyCosmetic). The Shop isn't open on the website: purchasable items show as Upcoming.
]]
local _, ns = ...
local T = ns.T
local C = T.C
local UI = ns.UI
local SZ = T.SIZE

local ROWS = 5
local SLOT_NAME = { skin = "Skin", frame = "Frame", victory = "Victory" }
local RARITY_COLOR = { common = C.body, rare = C.steel, epic = C.violet, legendary = C.gold, season = C.green }
local ACQUIRE = { level_reward = "Level reward", season_reward = "Season reward", default = "Default" }

local function when(t) return date("%d %b %Y, %H:%M", t) end
local function short(t) return date("%d %b %H:%M", t) end
local function safe(s) return s and (s:gsub("|", "||")) or nil end

--- "2x" / "1.5x" / "1.01x" from the code's value (XP multiplier x 100: 200 = 2x).
function UI.overdriveText(v)
  local s = string.format("%.2f", v / 100):gsub("0+$", ""):gsub("%.$", "")
  return s .. "x"
end

--- One event line, worded with the code's time (never "now" from a code alone).
function UI.eventText(e, asOf, now)
  local name = (e.kind == "storm") and "SHARD STORM" or ("XP OVERDRIVE " .. UI.overdriveText(e.value))
  if now and now > e["end"] then return name .. "  ended " .. short(e["end"]) .. " (by this PC's clock)", "over" end
  local what
  if e.state == "up" then
    what = "upcoming " .. short(e.start) .. " - " .. date("%H:%M", e["end"])
  else
    what = "live until " .. short(e["end"]) .. ", as of " .. date("%H:%M", asOf)
  end
  local extra = (e.kind == "storm") and ("  -  " .. T.commas(e.value) .. " Shards per claim") or ""
  return name .. "  " .. what .. extra, e.state
end

--- Status of one catalog item in this view: "equipped" | "owned" | "locked".
function UI.cosmeticStatus(v, id)
  for _, eid in pairs(v.equipped or {}) do if eid == id then return "equipped" end end
  for _, oid in ipairs(v.owned or {}) do if oid == id then return "owned" end end
  return "locked"
end

function UI:CreateCollection(sheet)
  local L = 24
  local cw = self.frame:GetWidth() - 2 * L - 2
  local y = CreateFrame("Frame", nil, sheet)
  y:SetPoint("TOPLEFT", 0, 0); y:SetPoint("BOTTOMRIGHT", 0, 0)
  sheet.coll = y
  local function line(fs, w) fs:SetWidth(w); fs:SetWordWrap(false); fs:SetJustifyH("LEFT"); return fs end

  -- Shards
  y.shardsHead = T.label(y, "SHARDS (WEBSITE BALANCE)"); y.shardsHead:SetPoint("TOPLEFT", L, -92)
  y.shards = line(T.display(y, SZ.title, C.gold), 200); y.shards:SetPoint("TOPLEFT", L, -106)
  y.asOf = line(T.text(y, SZ.label, C.label), cw - 210); y.asOf:SetPoint("TOPRIGHT", -L - 2, -112); y.asOf:SetJustifyH("RIGHT")
  y.shardsNote = line(T.text(y, SZ.label, C.label), cw); y.shardsNote:SetPoint("TOPLEFT", L, -132)

  -- Events
  y.eventsHead = T.label(y, "EVENTS ON STACKRIVALS.IO"); y.eventsHead:SetPoint("TOPLEFT", L, -152)
  y.events = {}
  for i = 1, 4 do
    local e = line(T.text(y, SZ.label, C.body), cw); e:SetPoint("TOPLEFT", L, -167 - (i - 1) * 14)
    y.events[i] = e
  end

  -- Cosmetics
  y.cosHead = T.label(y, "COSMETICS"); y.cosHead:SetPoint("TOPLEFT", L, -230)
  y.prev = T.button(y, "<", 26, 20, "frame", function() UI.collPage = math.max(1, (UI.collPage or 1) - 1); UI:RefreshCollection() end)
  y.next = T.button(y, ">", 26, 20, "frame", function() UI.collPage = (UI.collPage or 1) + 1; UI:RefreshCollection() end)
  y.next:SetPoint("TOPRIGHT", -L - 2, -226); y.prev:SetPoint("RIGHT", y.next, "LEFT", -4, 0)
  y.page = T.text(y, SZ.label, C.label); y.page:SetPoint("RIGHT", y.prev, "LEFT", -6, 0)
  y.equipped = line(T.text(y, SZ.label, C.body), cw); y.equipped:SetPoint("TOPLEFT", L, -248)
  y.rows = {}
  for i = 1, ROWS do
    local r = {}
    local ry = -264 - (i - 1) * 15
    r.name = line(T.text(y, SZ.small, C.body), 170); r.name:SetPoint("TOPLEFT", L, ry)
    r.slot = line(T.text(y, SZ.label, C.label), 60); r.slot:SetPoint("TOPLEFT", L + 176, ry + 1)
    r.status = line(T.text(y, SZ.label, C.label), cw - 242); r.status:SetPoint("TOPRIGHT", -L - 2, ry + 1); r.status:SetJustifyH("RIGHT")
    y.rows[i] = r
  end
  y.empty = T.text(y, SZ.body, C.body); y.empty:SetPoint("TOPLEFT", L, -96); y.empty:SetWidth(cw); y.empty:SetJustifyH("LEFT")
  y.empty:SetSpacing(3)
  y.trust = line(T.text(y, SZ.label, C.gold), cw - 130); y.trust:SetPoint("TOPLEFT", L, -344)
end

function UI:RefreshCollection()
  local s = self.accountSheet
  local y = s and s.coll
  if not y or not y:IsShown() then return end
  local Acc = ns.Account
  local Cat = ns.CosmeticsCatalog
  local v = Acc.profileView()
  local has = v ~= nil and v.format == "SRP2"
  local parts = { y.shardsHead, y.shards, y.asOf, y.shardsNote, y.eventsHead, y.cosHead, y.equipped, y.trust }
  for _, x in ipairs(parts) do x:SetShown(has) end
  for _, e in ipairs(y.events) do e:SetShown(has) end
  for _, r in ipairs(y.rows) do for _, x in pairs(r) do x:SetShown(has) end end
  y.empty:SetShown(not has)
  if not has then
    y.prev:Hide(); y.next:Hide(); y.page:Hide()
    y.empty:SetText(v == nil and "No profile yet. Link your stackrivals.io account on the Account tab:\nyour Shards, events and cosmetics will show here."
      or ("This snapshot has no Shards, cosmetics or events (" .. (v.format or "SRP1") .. ").\nOn " .. Acc.WEB.export
        .. ",\nchoose the SRP2 code and paste it on the Account tab."))
    return
  end
  local now = Acc.now()
  -- Shards: the website's number, never computed here
  if v.shards then
    y.shards:SetText(T.commas(v.shards))
    y.shards:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
  else
    y.shards:SetText("NOT AVAILABLE")
    y.shards:SetTextColor(C.label[1], C.label[2], C.label[3])
  end
  y.asOf:SetText("as of " .. when(v.asOf) .. "  -  " .. UI.accountAgo(v.asOf))
  y.shardsNote:SetText(v.stale and "OUT OF DATE: paste a new snapshot. Nothing is bought, spent or claimed in WoW."
    or "Pasted by hand. Nothing is bought, spent or claimed in WoW: Shop Upcoming.")
  -- Events
  for i, fs in ipairs(y.events) do
    local e = v.events[i]
    if e then
      local text, how = UI.eventText(e, v.asOf, now)
      fs:SetText(text)
      local c = (how == "live") and C.green or (how == "over") and C.label or C.body
      fs:SetTextColor(c[1], c[2], c[3])
    elseif i == 1 then
      fs:SetText("No Shard Storm or XP Overdrive in this snapshot.")
      fs:SetTextColor(C.label[1], C.label[2], C.label[3])
    else
      fs:SetText("")
    end
  end
  if #v.events > 0 and #v.events < 4 then
    local fs = y.events[#v.events + 1]
    fs:SetText("Claims only on stackrivals.io. WoW matches earn nothing from events.")
    fs:SetTextColor(C.label[1], C.label[2], C.label[3])
  end
  -- Cosmetics: equipped line, then every catalog item (equipped, owned, locked)
  local eq = {}
  for _, slot in ipairs(Cat.SLOTS) do
    local id = v.equipped[slot]
    if id then eq[#eq + 1] = SLOT_NAME[slot] .. " " .. (Cat.byId[id] and Cat.byId[id].name or safe(id)) end
  end
  local ownedKnown = 0
  for _, id in ipairs(v.owned) do if Cat.byId[id] then ownedKnown = ownedKnown + 1 end end
  y.equipped:SetText("Owned " .. ownedKnown .. " of " .. #Cat.items .. "  -  " .. #eq .. " equipped (listed first)")
  y.equipped.full = (#eq > 0 and ("Wearing: " .. table.concat(eq, ", ")) or "Nothing equipped")
  local list = {}
  local rank = { equipped = 0, owned = 1, locked = 2 }
  local slotRank = { skin = 0, frame = 1, victory = 2 }
  for _, it in ipairs(Cat.items) do list[#list + 1] = { it = it, st = UI.cosmeticStatus(v, it.id) } end
  table.sort(list, function(a, b)
    if rank[a.st] ~= rank[b.st] then return rank[a.st] < rank[b.st] end
    if slotRank[a.it.slot] ~= slotRank[b.it.slot] then return slotRank[a.it.slot] < slotRank[b.it.slot] end
    return a.it.name < b.it.name
  end)
  local pages = math.max(1, math.ceil(#list / ROWS))
  self.collPage = math.min(math.max(1, self.collPage or 1), pages)
  y.prev:SetShown(pages > 1); y.next:SetShown(pages > 1); y.page:SetShown(pages > 1)
  y.page:SetText(self.collPage .. " / " .. pages)
  if self.collPage > 1 then y.prev:Enable() else y.prev:Disable() end
  if self.collPage < pages then y.next:Enable() else y.next:Disable() end
  for i, r in ipairs(y.rows) do
    local e = list[(self.collPage - 1) * ROWS + i]
    if e then
      r.name:SetText(e.it.name)
      local rc = RARITY_COLOR[e.it.rarity] or C.body
      r.name:SetTextColor(rc[1], rc[2], rc[3])
      r.slot:SetText(SLOT_NAME[e.it.slot] or e.it.slot)
      local st
      if e.st == "equipped" then st = "EQUIPPED"
      elseif e.st == "owned" then st = "OWNED"
      elseif e.it.acquisition == "purchase" then st = "LOCKED  -  " .. T.commas(e.it.price or 0) .. " Shards, Shop Upcoming"
      else st = "LOCKED  -  " .. (ACQUIRE[e.it.acquisition] or e.it.acquisition) end
      r.status:SetText(st)
      local sc = (e.st == "equipped") and C.green or (e.st == "owned") and C.paper or C.label
      r.status:SetTextColor(sc[1], sc[2], sc[3])
    else
      for _, x in pairs(r) do x:SetText("") end
    end
  end
  y.trust:SetText(v.verified and "VERIFIED (signed). WoW draws no skins yet."
    or "UNVERIFIED: names only, nothing applied in WoW.")
  local tc = v.verified and C.green or C.gold
  y.trust:SetTextColor(tc[1], tc[2], tc[3])
end
