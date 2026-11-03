--[[
  StackRivals - character cards: who you meet in a duel / Quickplay match. Each addon sends its
  own player's card once the two are in the lobby (PRF): faction, race, class, WoW level, played-out
  duel W/L and whether match chat is on. Everything is SELF-REPORTED by the rival's addon and shown
  as such; nothing here is verified (only the character name is: WoW gives the real sender).
  "Share my character card" off -> only "-" is sent (the rival sees Unknown).
  Never sent: account names, Battle.net tags, guild, location, gold, anything else.
]]
local _, ns = ...
ns = ns or {}

local Card = {}
ns.Card = Card

local FACTION_CODE = { Alliance = "A", Horde = "H", Neutral = "N" }
Card.FACTION_COLOR = { Alliance = { 0.29, 0.53, 0.95 }, Horde = { 0.86, 0.22, 0.20 }, Neutral = { 0.70, 0.70, 0.70 } }

local function safe(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if ok then return a, b end
  return nil
end
local function token(x) return (type(x) == "string" and #x <= 16 and x:match("^%a+$")) and x or nil end

--- Your own character, from WoW's API (nil fields when the client doesn't tell).
function Card.mine()
  local faction = safe(UnitFactionGroup, "player")
  local _, race = safe(UnitRace, "player")
  local _, class = safe(UnitClass, "player")
  local level = safe(UnitLevel, "player")
  local d = ns.db and ns.db.duels or {}
  return {
    name = ns.Comm and ns.Comm.me and ns.Comm.me() or "?",
    faction = FACTION_CODE[faction or ""] and faction or nil,
    race = token(race), class = token(class),
    level = (type(level) == "number" and level >= 0 and level <= 200) and math.floor(level) or nil,
    wins = d.wins or 0, losses = d.losses or 0,
    chat = not (ns.db and ns.db.chat and ns.db.chat.enabled == false),
  }
end

function Card.sharing() return not (ns.db and ns.db.social and ns.db.social.shareCard == false) end

--- Send my card for match m (in the lobby; sent twice, a whisper can be lost).
function Card.send(m)
  if not (m and m.mid and m.rival and ns.Comm) then return end
  local c = Card.mine()
  local P = ns.Protocol
  local share = Card.sharing()
  local msg = P.encode("PRF", m.mid,
    share and FACTION_CODE[c.faction or ""] or "-", share and c.race or "-", share and c.class or "-", share and c.level or 0,
    P.b36(share and c.wins or 0), P.b36(share and c.losses or 0), c.chat and 1 or 0)
  ns.Comm.send(msg, "WHISPER", m.rival, nil, { key = "PRF:" .. m.mid })
  m.prfSentAt = GetTime and GetTime() or 0
  m.prfSends = (m.prfSends or 0) + 1
end

function Card.onLobby(m)
  if m.cardSent then return end
  m.cardSent = true
  Card.send(m)
end

--- Resend once after a few seconds (called from Duel.update while in the lobby or playing).
function Card.tick(m, t)
  if m.cardSent and (m.prfSends or 0) < 2 and t - (m.prfSentAt or t) >= 3 then Card.send(m) end
end

local function onCard(msg, sender)
  local m = ns.Duel and ns.Duel.matchOf and ns.Duel.matchOf(msg, sender)
  if not m then return end
  m.rivalCard = {
    faction = msg.faction, race = msg.race, class = msg.class, level = msg.level ~= 0 and msg.level or nil,
    wins = msg.wins, losses = msg.losses, chat = msg.chat, selfReported = true,
  }
  if not m.cardSent and (m.state == "lobby" or m.state == "playing") then Card.onLobby(m) end
  if ns.UI and ns.UI.frame and ns.UI.RefreshPhase then ns.UI:RefreshPhase() end
  if ns.UI and ns.UI.RefreshChat then ns.UI:RefreshChat() end
end

--- "Orc Shaman  -  Level 38" (localized class names when the client has them; Unknown parts say so).
function Card.who(c)
  c = c or {}
  local cls = c.class and ((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c.class]) or (c.class:sub(1, 1) .. c.class:sub(2):lower())) or nil
  local race = c.race and (c.race == "Scourge" and "Undead" or (c.race:gsub("(%l)(%u)", "%1 %2"))) or nil
  local who = (race and cls) and (race .. " " .. cls) or race or cls or "Unknown"
  return who .. "  -  " .. (c.level and ("Level " .. c.level) or "Level ?")
end

--- "Horde  -  Orc Shaman  -  Level 38"
function Card.describe(c)
  if not c then return "Unknown" end
  return (c.faction or "Unknown") .. "  -  " .. Card.who(c)
end

function Card.init()
  if ns.Comm then ns.Comm.on("PRF", onCard) end
end

return Card
