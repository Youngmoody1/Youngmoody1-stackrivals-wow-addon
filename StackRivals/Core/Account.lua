--[[
  StackRivals - one StackRivals account for WoW and stackrivals.io, addon side (DRAFT v1).

  The addon has no internet access, so the link is a short exchange of text codes the player
  carries (formats: Net/AccountCodes.lua, docs/ACCOUNT_SYNC_HANDOFF.md):

    1. stackrivals.io (logged in with e-mail - never in WoW) shows a one-time code "A7K9-P2XM".
    2. The player types it here -> state PENDING; the addon shows a link request (SRL1) to paste on
       the website. Typing a code proves nothing by itself: still PENDING.
    3. The website checks the code belongs to that account, binds this character and gives back a
       profile snapshot (SRP1) carrying the same linkId -> only then LINKED.
    4. Later snapshots (same linkId, this character, newer) refresh the profile; older than
       STALE_AFTER -> NOT SYNCED (shown with the date). Unlink forgets it on this PC.

  Per character (SavedVariables are per WoW account; the link is per character). No password,
  token or secret is ever asked for or stored. The snapshot is display data: it can't change
  local records, duel results or anything on the website.
]]
local _, ns = ...
ns = ns or {}

local Acc = {}
ns.Account = Acc

Acc.PENDING_TTL = 15 * 60          -- s a typed web code stays pending here (the web's own limit is shorter)
Acc.STALE_AFTER = 7 * 86400        -- s after the snapshot was made: NOT SYNCED
Acc.CLOCK_SKEW = 10 * 60           -- s of clock difference tolerated between the website and WoW
Acc.MAX_CHARS = 50                 -- characters kept in SavedVariables

Acc.ERRORS = {
  empty = "Paste a code first.",
  chars = "The code has characters that don't belong in it (copy it again).",
  size = "That code is too long.",
  format = "That isn't a StackRivals code.",
  wrong_kind = "That's a different kind of StackRivals code (not a profile snapshot).",
  version = "This snapshot uses a newer format: update StackRivals.",
  fields = "The code is incomplete (copy all of it).",
  check = "The code has a typo or was cut off (checksum doesn't match).",
  player = "This snapshot is for another character.",
  not_pending = "Start linking first: type the code from stackrivals.io.",
  link_other = "This snapshot belongs to a different link. Unlink first, or export a new snapshot.",
  pending_expired = "The link request expired. Start again with a new code from stackrivals.io.",
  too_old_for_link = "This snapshot was made before your link request. Export a new one.",
  expired = "This snapshot has expired. Export a fresh one on stackrivals.io.",
  future = "This snapshot is dated in the future (check the date on your PC).",
  older = "This snapshot is older than the one you already have. Nothing changed.",
  duplicate = "You already imported this snapshot.",
  webcode_format = "A link code is 8 letters and digits, like A7K9-P2XM.",
  webcode_check = "That link code has a typo (check the letters).",
}

local function A() return ns.AccountCodes end
function Acc.now() return (GetServerTime and GetServerTime()) or (time and time()) or 0 end

function Acc.me() return ns.Comm and ns.Comm.me and ns.Comm.me() or nil end

--- WoW flavour -> SR1/SRL1 platform.
function Acc.platform()
  local proj = WOW_PROJECT_ID
  if proj == 1 then return "wow-retail" end
  if ns.BUILD and ns.BUILD.forever then return "wow-forever" end
  local _, _, _, iface = GetBuildInfo and GetBuildInfo()
  if iface == 16001 then return "wow-forever" end -- WoW Forever's interface (TOC)
  return "wow-classic"
end

local function store()
  local db = ns.db
  if not db then return {} end
  db.accounts = db.accounts or {}
  return db.accounts
end

--- This character's account record (created on demand).
function Acc.rec()
  local me = Acc.me()
  if not me then return nil end
  local s = store()
  s[me] = s[me] or {}
  return s[me]
end

--- State of this character: "not_linked" | "pending" | "linked" | "not_synced", and the record.
function Acc.state()
  local r = Acc.rec()
  if not r then return "not_linked" end
  local t = Acc.now()
  if r.pending and t - r.pending.at > Acc.PENDING_TTL then
    r.pending, r.note = nil, "pending_expired"
  end
  if r.link and r.profile then
    if t - r.profile.issued > Acc.STALE_AFTER or t > r.profile.expires then return "not_synced", r end
    return "linked", r
  end
  if r.pending then return "pending", r end
  return "not_linked", r
end

--- Step 2: the player typed the code from the website. Returns the link request code or nil, error.
function Acc.startLink(typed)
  local code, why = A().parseWebCode(typed)
  if not code then return nil, "webcode_" .. why end
  local r = Acc.rec()
  if not r then return nil, "player" end
  r.pending = {
    code = code, at = Acc.now(),
    linkId = A().newLinkId(function(a, b) return math.random(a, b) end),
  }
  r.note = nil
  return Acc.requestCode()
end

--- The link request for the pending link (same text every time it is shown).
function Acc.requestCode()
  local r = Acc.rec()
  if not (r and r.pending) then return nil end
  return A().linkRequest({
    code = r.pending.code, platform = Acc.platform(), player = Acc.me(), linkId = r.pending.linkId,
    addon = ns.VERSION or "dev", engine = ns.Engine and ns.Engine.ENGINE_VERSION or 1, issued = r.pending.at,
  })
end

function Acc.cancelLink()
  local r = Acc.rec()
  if r then r.pending, r.note = nil, nil end
end

--- Step 3 / later syncs: import a profile snapshot. Returns true, "linked" | "updated" or nil, error.
function Acc.import(text)
  local p, why = A().parseProfile(text)
  if not p then return nil, why end
  local me = Acc.me()
  if not me or not ns.Comm.same(p.player, me) then return nil, "player" end
  local st, r = Acc.state()
  local t = Acc.now()
  if p.issued > t + Acc.CLOCK_SKEW then return nil, "future" end
  if t > p.expires + Acc.CLOCK_SKEW then return nil, "expired" end
  local result
  if r.link then
    if p.linkId ~= r.link.linkId then return nil, "link_other" end
    local old = r.profile
    if old and p.check == old.check then return nil, "duplicate" end
    if old and p.issued < old.issued then return nil, "older" end
    if old and p.issued == old.issued then return nil, "duplicate" end
    result = "updated"
  else
    if st ~= "pending" then return nil, (r.note == "pending_expired") and "pending_expired" or "not_pending" end
    if p.linkId ~= r.pending.linkId then return nil, "link_other" end
    if p.issued < r.pending.at - Acc.CLOCK_SKEW then return nil, "too_old_for_link" end
    r.link = { linkId = p.linkId, accountId = p.accountId, at = t }
    r.pending = nil
    result = "linked"
  end
  r.profile = {
    linkId = p.linkId, accountId = p.accountId, name = p.name, issued = p.issued, expires = p.expires,
    level = p.level, xp = p.xp, xpNext = p.xpNext, rank = p.rank, season = p.season, seasonPct = p.seasonPct,
    wins = p.wins, losses = p.losses, draws = p.draws, history = p.history,
    achUnlocked = p.achUnlocked, achTotal = p.achTotal, cosOwned = p.cosOwned, cosEquipped = p.cosEquipped,
    signed = p.sig ~= nil, check = p.check,
  }
  r.lastSync = t
  r.note = nil
  return true, result
end

--- Forget the link on this PC (the website keeps its side until unlinked there).
function Acc.unlink()
  local r = Acc.rec()
  if not r then return end
  r.link, r.profile, r.pending, r.lastSync = nil, nil, nil, nil
  r.note = "unlinked"
end

--- Clean what was on disk (DB.sanitize calls this): bounded, typed, nothing unknown kept.
function Acc.sanitize(raw)
  local out, kept = {}, {}
  if type(raw) ~= "table" then return out end
  local C = ns.Codes
  local function num(v, lo, hi) return (type(v) == "number" and v == v and v >= lo and v <= hi) and math.floor(v) or nil end
  local function txt(v, max) return (type(v) == "string" and #v >= 1 and #v <= max and not v:find("[%c]") and (not C or C.utf8ok(v))) and v or nil end
  local function id(v, pat, lo, hi) return (type(v) == "string" and #v >= lo and #v <= hi and v:match(pat)) and v or nil end
  for who, r in pairs(raw) do
    if type(who) == "string" and (not C or C.nameOk(who)) and type(r) == "table" then
      local o = {}
      local pe = r.pending
      if type(pe) == "table" and id(pe.code, "^[0-9A-Z]+$", 8, 8) and id(pe.linkId, "^[a-z0-9]+$", 12, 12) and num(pe.at, 0, 1e11) then
        o.pending = { code = pe.code, linkId = pe.linkId, at = num(pe.at, 0, 1e11) }
      end
      local li, pr = r.link, r.profile
      if type(li) == "table" and id(li.linkId, "^[a-z0-9]+$", 12, 12) and id(li.accountId, "^[a-z0-9_%-]+$", 4, 40) and type(pr) == "table" then
        local issued, expires = num(pr.issued, 0, 1e11), num(pr.expires, 0, 1e11)
        local name = txt(pr.name, 32)
        if issued and expires and name and pr.linkId == li.linkId then
          o.link = { linkId = li.linkId, accountId = li.accountId, at = num(li.at, 0, 1e11) or issued }
          local hist = {}
          if type(pr.history) == "table" then
            for i = 1, math.min(#pr.history, 10) do
              local h = pr.history[i]
              if type(h) == "table" and id(h.mode, "^[a-z0-9]+$", 1, 12) and (h.res == "w" or h.res == "l" or h.res == "d") then
                hist[#hist + 1] = { mode = h.mode, res = h.res, my = num(h.my, 0, 1e12) or 0, their = num(h.their, 0, 1e12) or 0, at = num(h.at, 0, 1e11) or 0 }
              end
            end
          end
          o.profile = {
            linkId = li.linkId, accountId = li.accountId, name = name, issued = issued, expires = expires,
            level = num(pr.level, 0, 9999) or 0, xp = num(pr.xp, 0, 1e12) or 0, xpNext = num(pr.xpNext, 0, 1e12) or 0,
            rank = txt(pr.rank, 24), season = txt(pr.season, 24), seasonPct = num(pr.seasonPct, 0, 100) or 0,
            wins = num(pr.wins, 0, 1e9) or 0, losses = num(pr.losses, 0, 1e9) or 0, draws = num(pr.draws, 0, 1e9) or 0,
            history = hist, achUnlocked = num(pr.achUnlocked, 0, 9999), achTotal = num(pr.achTotal, 0, 9999),
            cosOwned = num(pr.cosOwned, 0, 99999), cosEquipped = txt(pr.cosEquipped, 24),
            signed = pr.signed == true, check = id(pr.check, "^%x+$", 8, 8) or "00000000",
          }
          o.lastSync = num(r.lastSync, 0, 1e11)
        end
      end
      if r.note == "unlinked" or r.note == "pending_expired" then o.note = r.note end
      if o.pending or o.link or o.note then kept[#kept + 1] = { who = who, o = o } end
    end
  end
  -- bounded: linked characters first, then pending, then notes; by name (deterministic)
  local function rank(e) return e.o.link and 0 or e.o.pending and 1 or 2 end
  table.sort(kept, function(x, y) if rank(x) ~= rank(y) then return rank(x) < rank(y) end return x.who < y.who end)
  for i = 1, math.min(#kept, Acc.MAX_CHARS) do out[kept[i].who] = kept[i].o end
  return out
end

return Acc
