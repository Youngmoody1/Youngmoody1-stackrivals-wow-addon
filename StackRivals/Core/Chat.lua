--[[
  StackRivals - match chat between the two players of a duel / Quickplay match, inside the
  StackRivals window only (never posted to guild, party or any public channel).

  * Both must have match chat on (Settings / the chat panel); each side says so in its card (PRF).
  * Free text only between players of the SAME faction. WoW doesn't let the factions talk to each
    other (except via Battle.net), so the addon doesn't either: across factions (or when a faction is
    unknown) only the four quick messages (Good luck!, GG!, Well played!, Rematch?) work.
  * Rate limits: you send at most 1 line per 1.5 s and 8 per 30 s; a rival's lines beyond 10 per 30 s
    are dropped (spam). Lines are at most 80 bytes; WoW's "|" escape codes are neutralised, so a
    line can't inject links, colours or textures.
  * Mute: you stop seeing that player's lines (remembered); they are not told.
  Transport: addon whispers of the duel (CH / QM). Not tested in a real client yet.
]]
local _, ns = ...
ns = ns or {}

local Chat = {}
ns.Chat = Chat

Chat.SEND_GAP = 1.5
Chat.SEND_MAX, Chat.SEND_WINDOW = 8, 30
Chat.RECV_MAX = 10
Chat.KEEP = 40

local function now() return GetTime and GetTime() or 0 end
local function db() return ns.db and ns.db.chat or { enabled = true, muted = {} } end

--- Clean a line for display: no control characters, "|" escaped (no links / colours / textures).
function Chat.clean(text)
  text = tostring(text or ""):gsub("[%c]", " ")
  text = text:sub(1, ns.Protocol and ns.Protocol.CHAT_MAX or 80)
  -- don't leave a cut UTF-8 sequence at the end
  text = text:gsub("[\192-\255][\128-\191]*$", function(s)
    local lead = s:byte(1)
    local need = lead >= 240 and 4 or lead >= 224 and 3 or 2
    return #s == need and s or ""
  end)
  return (text:gsub("|", "||"))
end

function Chat.muted(name)
  local m = db().muted
  return type(name) == "string" and m and m[name:lower()] or false
end

--- What chat can do in match m: "free" (text + quick), "quick" (cross-faction / unknown faction),
--- or "off" with a reason.
function Chat.mode(m)
  if not m then return "off", "no match" end
  if db().enabled == false then return "off", "you turned match chat off" end
  if m.endReason == "rival_disconnected" or m.endReason == "rival_offline" or m.rivalGone then return "off", "lost contact with your rival" end
  if m.state == "cancelled" then return "off", "the match was cancelled" end
  if m.state == "inviting" or m.state == "invited" then return "off", "chat opens in the lobby" end
  local rc = m.rivalCard
  if not rc then return "off", "waiting for your rival's card" end
  if not rc.chat then return "off", "your rival has match chat off" end
  local mine = ns.Card and ns.Card.mine() or {}
  if mine.faction and rc.faction and mine.faction == rc.faction and mine.faction ~= "Neutral" then return "free" end
  -- Battle.net friends may already write to each other across factions (Battle.net whispers):
  -- a match that runs over Battle.net allows text too
  if ns.BNet and ns.BNet.route(m.rival) then return "free" end
  return "quick", "only quick messages across factions"
end

local function push(m, line)
  m.chat = m.chat or {}
  m.chat[#m.chat + 1] = line
  while #m.chat > Chat.KEEP do table.remove(m.chat, 1) end
  if ns.UI and ns.UI.RefreshChat then ns.UI:RefreshChat() end
end

local function canSend(m)
  local t = now()
  m.chatSent = m.chatSent or {}
  local recent = 0
  for _, at in ipairs(m.chatSent) do if t - at < Chat.SEND_WINDOW then recent = recent + 1 end end
  if m.chatLastAt and t - m.chatLastAt < Chat.SEND_GAP then return false, "slow down" end
  if recent >= Chat.SEND_MAX then return false, "slow down" end
  return true
end
local function noteSent(m)
  local t = now()
  m.chatLastAt = t
  local keep = {}
  for _, at in ipairs(m.chatSent or {}) do if t - at < Chat.SEND_WINDOW then keep[#keep + 1] = at end end
  keep[#keep + 1] = t
  m.chatSent = keep
end

local function hex(s) return (s:gsub(".", function(ch) return string.format("%02x", ch:byte()) end)) end

--- Send a free-text line. Returns true, or false + reason.
function Chat.send(m, text)
  local mode, why = Chat.mode(m)
  if mode ~= "free" then return false, why or "chat is off" end
  local raw = tostring(text or ""):gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if raw == "" then return false, "empty" end
  raw = raw:sub(1, ns.Protocol.CHAT_MAX)
  local okS, w = canSend(m)
  if not okS then return false, w end
  noteSent(m)
  m.chatN = (m.chatN or 0) + 1
  ns.Comm.send(ns.Protocol.encode("CH", m.mid, m.chatN, hex(raw)), "WHISPER", m.rival, nil, { key = "CH:" .. m.mid .. ":" .. m.chatN })
  push(m, { me = true, text = Chat.clean(raw) })
  return true
end

--- Send quick message 1..4 (works across factions).
function Chat.quick(m, code)
  local mode, why = Chat.mode(m)
  if mode == "off" then return false, why end
  local P = ns.Protocol
  if not P.QUICK[code] then return false, "bad" end
  local okS, w = canSend(m)
  if not okS then return false, w end
  noteSent(m)
  m.chatN = (m.chatN or 0) + 1
  ns.Comm.send(P.encode("QM", m.mid, m.chatN, code), "WHISPER", m.rival, nil, { key = "QM:" .. m.mid .. ":" .. m.chatN })
  push(m, { me = true, text = P.QUICK[code], quick = true })
  return true
end

function Chat.mute(m, on)
  if not (m and m.rival) then return end
  local d = db()
  d.muted = d.muted or {}
  d.muted[m.rival:lower()] = on and true or nil
  if ns.UI and ns.UI.RefreshChat then ns.UI:RefreshChat() end
end

local function receive(m, msg, text, quick)
  if Chat.muted(m.rival) or db().enabled == false then return end
  m.chatIn = m.chatIn or {}
  if m.chatIn[msg.n] then return end -- a repeat
  local t = now()
  local recent = 0
  for _, at in pairs(m.chatIn) do if t - at < Chat.SEND_WINDOW then recent = recent + 1 end end
  if recent >= Chat.RECV_MAX then m.chatDropped = (m.chatDropped or 0) + 1; return end
  m.chatIn[msg.n] = t
  push(m, { me = false, text = text, quick = quick })
end

local function onLine(msg, sender)
  local m = ns.Duel and ns.Duel.matchOf and ns.Duel.matchOf(msg, sender)
  if not m then return end
  if Chat.mode(m) ~= "free" then return end -- free text only when both sides could send it
  receive(m, msg, Chat.clean(msg.text), false)
end

local function onQuick(msg, sender)
  local m = ns.Duel and ns.Duel.matchOf and ns.Duel.matchOf(msg, sender)
  if not m or Chat.mode(m) == "off" then return end
  receive(m, msg, ns.Protocol.QUICK[msg.code], true)
end

function Chat.init()
  if ns.Comm then ns.Comm.on("CH", onLine); ns.Comm.on("QM", onQuick) end
end

return Chat
