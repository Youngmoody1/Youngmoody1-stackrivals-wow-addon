-- Account link (one-time code), profile snapshots, Account / Profile UI (DRAFT v1 formats).
-- The website side is simulated here with the reference encoder; nothing talks to stackrivals.io.
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local NS = assert(loadfile(testdir .. "/netsim.lua"))(root, testdir)
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe

local pure = H.load(root, { "Engine/Prng.lua", "Engine/Pieces.lua", "Engine/Engine.lua", "Net/Protocol.lua", "Net/Codes.lua", "Net/AccountCodes.lua" })
local A = pure.AccountCodes

local T0 = 1793000000
local function snap(o)
  local p = {
    linkId = "abcdefghij12", player = "Alice-Realm", accountId = "acc_7f3k2", name = "Alice Stack",
    issued = T0, expires = T0 + 7 * 86400, level = 12, xp = 1240, xpNext = 2000, rank = "Gold II", season = "Season 3",
    seasonPct = 45, wins = 12, losses = 8, draws = 1,
    history = { { mode = "b120", res = "w", my = 12300, their = 9800, at = T0 - 3600 }, { mode = "s180", res = "l", my = 8000, their = 15000, at = T0 - 7200 } },
    achUnlocked = 14, achTotal = 60, cosOwned = 5, cosEquipped = "Neon Grid",
  }
  for k, v in pairs(o or {}) do p[k] = v end
  if o and o.noHistory then p.history = {} end
  return A.profile(p)
end

describe("web link code (Crockford base32 + check symbol)", function()
  it("normalises case, dashes, spaces and O / I / L; rejects other symbols and lengths", function()
    local code = A.makeWebCode("A7K9P2X")
    eq(#code, 8)
    eq(A.parseWebCode(code), code)
    eq(A.parseWebCode(A.prettyWebCode(code):lower()), code)
    eq(A.parseWebCode(" " .. code:sub(1, 4) .. " - " .. code:sub(5) .. " "), code)
    local withZero = A.makeWebCode("0011ABC")
    eq(A.parseWebCode(("OOIL" .. withZero:sub(5)):lower()), withZero, "O -> 0, I / L -> 1")
    local _, why = A.parseWebCode("A7K9P2U" .. code:sub(8)); eq(why, "format", "U is not Crockford")
    _, why = A.parseWebCode(code:sub(1, 7)); eq(why, "format")
    _, why = A.parseWebCode(code .. "Q"); eq(why, "format")
    _, why = A.parseWebCode(""); eq(why, "format")
  end)
  it("every single wrong symbol is caught by the check symbol", function()
    local alpha = A.CROCKFORD
    local code = A.makeWebCode("K4M9TQ2")
    for i = 1, 8 do
      for j = 1, #alpha do
        local ch = alpha:sub(j, j)
        if ch ~= code:sub(i, i) then
          local typo = code:sub(1, i - 1) .. ch .. code:sub(i + 1)
          local r, why = A.parseWebCode(typo)
          ok(r == nil and why == "check", "typo not caught: " .. typo)
        end
      end
    end
  end)
end)

describe("link request (SRL1) and profile snapshot (SRP1)", function()
  local req = { code = A.makeWebCode("A7K9P2X"), platform = "wow-classic", player = "Alice-Realm", linkId = "abcdefghij12", addon = "0.6.1", engine = 1, issued = T0 }
  it("link request round-trips and carries nothing secret", function()
    local s = A.linkRequest(req)
    ok(s:match("^SRL1%."), s)
    local r = assert(A.parseLinkRequest(s))
    eq(r.code, req.code); eq(r.platform, "wow-classic"); eq(r.player, "Alice-Realm"); eq(r.linkId, req.linkId)
    eq(r.addon, "0.6.1"); eq(r.engine, 1); eq(r.issued, T0)
    ok(not s:find("@"), "no e-mail"); ok(#s < 120, "short enough to copy: " .. #s)
    local typo = s:sub(1, 10) .. (s:sub(11, 11) == "a" and "b" or "a") .. s:sub(12)
    local _, why = A.parseLinkRequest(typo); eq(why, "check")
    _, why = A.parseLinkRequest("SRL2" .. s:sub(5)); eq(why, "version")
  end)
  it("profile snapshot round-trips every field", function()
    local p = assert(A.parseProfile(snap()))
    eq(p.linkId, "abcdefghij12"); eq(p.player, "Alice-Realm"); eq(p.accountId, "acc_7f3k2"); eq(p.name, "Alice Stack")
    eq(p.level, 12); eq(p.xp, 1240); eq(p.xpNext, 2000); eq(p.rank, "Gold II"); eq(p.season, "Season 3"); eq(p.seasonPct, 45)
    eq(p.wins, 12); eq(p.losses, 8); eq(p.draws, 1); eq(#p.history, 2); eq(p.history[1].mode, "b120"); eq(p.history[2].their, 15000)
    eq(p.achUnlocked, 14); eq(p.achTotal, 60); eq(p.cosOwned, 5); eq(p.cosEquipped, "Neon Grid"); eq(p.sig, nil)
    local q = assert(A.parseProfile(snap({ rank = false, season = false, noHistory = true, achUnlocked = false, cosOwned = false })))
    eq(q.rank, nil); eq(q.season, nil); eq(#q.history, 0); eq(q.achUnlocked, nil); eq(q.cosOwned, nil)
    -- UTF-8 names survive (a Danish display name)
    eq(assert(A.parseProfile(snap({ name = "Søren Æblegrød" }))).name, "Søren Æblegrød")
  end)
  it("rejects manipulated, cut, foreign and out-of-range snapshots", function()
    local good = snap()
    local function bad(code, want)
      local p, why = A.parseProfile(code)
      ok(p == nil, "accepted: " .. code:sub(1, 60))
      if want then eq(why, want, code:sub(1, 40)) end
    end
    bad(good:sub(1, -2) .. (good:sub(-1) == "0" and "1" or "0"), "check")
    bad(good:sub(1, #good - 20), nil)
    bad("SRP2" .. good:sub(5), "version")
    bad(pure.Codes.challenge("b120", "abc"), "wrong_kind")
    bad("hello", "format")
    bad("", "empty")
    bad(string.rep("x", 5000), "size")
    bad(snap({ name = "Bad\nName" }), "name")
    bad(snap({ level = 10000 }), "numbers")
    bad(snap({ expires = T0 }), "time")
    bad(snap({ expires = T0 + 31 * 86400 }), "time")
    bad(snap({ achUnlocked = 61, achTotal = 60 }), "achievements")
    bad(snap({ sig = "short" }), "sig")
    bad(snap({ accountId = "has.dot" }), nil)
    bad(snap({ player = "x" }), nil)
    local many = {}
    for i = 1, 11 do many[i] = { mode = "b120", res = "w", my = 1, their = 0, at = T0 } end
    ok(not pcall(snap, { history = many }), "the encoder refuses 11 entries")
    -- hand-made code with 11 entries: the parser refuses too
    local f = {}
    for part in (good .. "."):gmatch("([^.]*)%.") do f[#f + 1] = part end
    local h = {}
    for i = 1, 11 do h[i] = "b120-w-1-0-1" end
    f[17] = table.concat(h, "~"); table.remove(f)
    local body = table.concat(f, ".")
    bad(body .. "." .. string.format("%08x", pure.Prng.hashString(body)), "history")
  end)
end)

describe("shared vectors docs/vectors/account_v1.json", function()
  it("is current (regenerate: lua5.1 tests/account_vectors.lua StackRivals tests > docs/vectors/account_v1.json)", function()
    local f = assert(io.open(root .. "/../docs/vectors/account_v1.json", "rb"))
    local disk = f:read("*a"); f:close()
    local VEC = assert(loadfile(testdir .. "/account_vectors.lua"))(root, testdir)
    ok(disk == VEC.text(), "docs/vectors/account_v1.json is out of date")
  end)
end)

describe("handoff vectors (docs/ACCOUNT_SYNC_HANDOFF.md section 4) stay exact", function()
  it("web codes, SRL1 and SRP1 match the documented strings byte for byte", function()
    eq(A.makeWebCode("A7K9P2X"), "A7K9P2XJ"); eq(A.makeWebCode("0000000"), "00000000"); eq(A.makeWebCode("ZZZZZZZ"), "ZZZZZZZF")
    eq(A.linkRequest({ code = "A7K9P2XJ", platform = "wow-classic", player = "Alice-Realm", linkId = "k3v9q2m7x1aa", addon = "0.6.1", engine = 1, issued = 1793000000 }),
      "SRL1.A7K9P2XJ.wow-classic.416c6963652d5265616c6d.k3v9q2m7x1aa.0-6-1.1.tni7nk.f1b8a2c8")
    eq(A.profile({ linkId = "k3v9q2m7x1aa", player = "Alice-Realm", accountId = "acc_7f3k2", name = "Alice Stack", issued = 1793000060, expires = 1793604860,
      level = 12, xp = 1240, xpNext = 2000, rank = "Gold II", season = "Season 3", seasonPct = 45, wins = 12, losses = 8, draws = 1,
      history = { { mode = "b120", res = "w", my = 12300, their = 9800, at = 1792996400 } }, achUnlocked = 14, achTotal = 60, cosOwned = 5, cosEquipped = "Neon Grid" }),
      "SRP1.k3v9q2m7x1aa.416c6963652d5265616c6d.acc_7f3k2.416c69636520537461636b.tni7p8.tnv6d8.c.yg.1jk.476f6c64204949.536561736f6e2033.45.c.8.1.b120-w-9ho-7k8-tni4vk.e-1o.5-4e656f6e2047726964.-.a06ade80")
    eq(A.profile({ linkId = "k3v9q2m7x1aa", player = "Alice-Realm", accountId = "acc_7f3k2", name = "Alice", issued = 1793000060, expires = 1793086460, history = {} }),
      "SRP1.k3v9q2m7x1aa.416c6963652d5265616c6d.acc_7f3k2.416c696365.tni7p8.tnk2d8.0.0.0.-.-.0.0.0.0.-.-.-.-.4146f9ee")
  end)
end)

describe("account link state (simulated client)", function()
  local function client(seed, o)
    local net = NS.new({ seed = seed })
    o = o or {}; o.name = o.name or "Alice"
    local c = net.add(o)
    c.M.serverTime = T0
    return net, c, c.ns.Account
  end
  local function webAnswer(reqCode, o)
    local r = assert(A.parseLinkRequest(reqCode))
    o = o or {}
    o.linkId = o.linkId or r.linkId; o.player = o.player or r.player
    o.issued = o.issued or T0 + 60; o.expires = o.expires or T0 + 60 + 7 * 86400
    return snap(o)
  end

  it("not linked -> typed code = PENDING (never Linked) -> web snapshot with the same linkId = LINKED", function()
    local _, c, Acc = client(1)
    eq(Acc.state(), "not_linked")
    local _, why = Acc.startLink("hello!"); eq(why, "webcode_format")
    local code = A.makeWebCode("A7K9P2X")
    _, why = Acc.startLink(code:sub(1, 7) .. (code:sub(8) == "0" and "1" or "0")); eq(why, "webcode_check")
    eq(Acc.state(), "not_linked")
    local req = assert(Acc.startLink(A.prettyWebCode(code)))
    eq(Acc.state(), "pending", "a typed code alone proves nothing")
    local r = assert(A.parseLinkRequest(req))
    eq(r.player, "Alice-Realm"); eq(r.platform, "wow-forever", "the mock runs interface 16001 = WoW Forever"); eq(r.code, code); eq(r.engine, c.ns.Engine.ENGINE_VERSION)
    eq(Acc.requestCode(), req, "the same request every time it is shown")
    c.M.serverTime = T0 + 120
    local okI, res = Acc.import(webAnswer(req))
    ok(okI, tostring(res)); eq(res, "linked")
    local st, rec = Acc.state()
    eq(st, "linked"); eq(rec.profile.name, "Alice Stack"); eq(rec.link.accountId, "acc_7f3k2")
  end)

  it("only the right snapshot confirms a link", function()
    local _, c, Acc = client(2)
    local req = assert(Acc.startLink(A.makeWebCode("QQQQ222")))
    c.M.serverTime = T0 + 60
    local function try(o, want) local okI, why = Acc.import(webAnswer(req, o)); ok(not okI); eq(why, want); eq(Acc.state(), "pending") end
    try({ linkId = "zzzzzzzzzzzz" }, "link_other")
    try({ player = "Bob-Realm" }, "player")
    try({ issued = T0 - 3600, expires = T0 + 86400 }, "too_old_for_link")
    try({ issued = T0 + 86400, expires = T0 + 2 * 86400 }, "future")
    try({ issued = T0 - 2 * 86400, expires = T0 - 86400 }, "expired")
    ok(not Acc.import("garbage")); ok(not Acc.import(""))
  end)

  it("a snapshot without a pending link is refused; the pending request expires after 15 minutes", function()
    local _, c, Acc = client(3)
    local fake = snap({ issued = T0, expires = T0 + 86400 })
    local okI, why = Acc.import(fake); ok(not okI); eq(why, "not_pending")
    local req = assert(Acc.startLink(A.makeWebCode("ABCDEFG")))
    c.M.serverTime = T0 + Acc.PENDING_TTL + 1
    eq(Acc.state(), "not_linked")
    okI, why = Acc.import(webAnswer(req, { issued = T0 + Acc.PENDING_TTL, expires = T0 + 86400 }))
    ok(not okI); eq(why, "pending_expired")
  end)

  it("later syncs: newer updates, older / same are refused (no rollback), stale = NOT SYNCED", function()
    local _, c, Acc = client(4)
    local req = assert(Acc.startLink(A.makeWebCode("SYNC123")))
    c.M.serverTime = T0 + 100
    ok(Acc.import(webAnswer(req, { issued = T0 + 60, level = 12 })))
    local newer = webAnswer(req, { issued = T0 + 90, level = 13 })
    local okI, res = Acc.import(newer); ok(okI); eq(res, "updated")
    local _, rec = Acc.state(); eq(rec.profile.level, 13)
    okI, res = Acc.import(newer); ok(not okI); eq(res, "duplicate")
    okI, res = Acc.import(webAnswer(req, { issued = T0 + 70, level = 99 })); ok(not okI); eq(res, "older")
    _, rec = Acc.state(); eq(rec.profile.level, 13, "never rolled back")
    c.M.serverTime = T0 + 90 + Acc.STALE_AFTER + 1
    eq(Acc.state(), "not_synced")
    okI = Acc.import(webAnswer(req, { issued = c.M.serverTime - 10, expires = c.M.serverTime + 86400, level = 14 }))
    ok(okI); eq(Acc.state(), "linked")
  end)

  it("a profile can't touch local records, duel results or anything else", function()
    local _, c, Acc = client(5)
    local db = c.ns.db
    local before = { db.duels.wins, db.duels.losses, db.records.blitz.best, db.spell.stats.challenger.wins }
    local req = assert(Acc.startLink(A.makeWebCode("SAFE123")))
    c.M.serverTime = T0 + 100
    ok(Acc.import(webAnswer(req, { wins = 999999, level = 9999, xp = 1e12 })))
    eq(db.duels.wins, before[1]); eq(db.duels.losses, before[2]); eq(db.records.blitz.best, before[3]); eq(db.spell.stats.challenger.wins, before[4])
  end)

  it("unlink forgets it here; the old link's snapshots are refused afterwards", function()
    local _, c, Acc = client(6)
    local req = assert(Acc.startLink(A.makeWebCode("VNMKNK1")))
    c.M.serverTime = T0 + 100
    ok(Acc.import(webAnswer(req)))
    Acc.unlink()
    eq(Acc.state(), "not_linked")
    local okI, why = Acc.import(webAnswer(req, { issued = T0 + 99 })); ok(not okI); eq(why, "not_pending")
  end)

  it("survives /reload; the link is per character", function()
    local net, c, Acc = client(7)
    local req = assert(Acc.startLink(A.makeWebCode("REWAD21")))
    c.M.serverTime = T0 + 100
    ok(Acc.import(webAnswer(req)))
    local c2 = net.reload(c)
    c2.M.serverTime = T0 + 200
    eq(c2.ns.Account.state(), "linked")
    eq(c2.ns.db.accounts["Alice-Realm"].profile.name, "Alice Stack")
    -- another character on the same WoW account (same SavedVariables): not linked
    local other = net.add({ name = "Zed", saved = c2.env.StackRivalsDB })
    other.M.serverTime = T0 + 200
    eq(other.ns.Account.state(), "not_linked")
  end)

  it("manipulated SavedVariables are cleaned on load", function()
    local net = NS.new({ seed = 8 })
    local evil = {}
    for i = 1, 80 do evil["Char" .. string.char(96 + (i % 26) + 1) .. "-Realm" .. i] = { note = "unlinked" } end
    evil["Alice-Realm"] = {
      link = { linkId = "abcdefghij12", accountId = "acc_7f3k2" },
      profile = { linkId = "abcdefghij12", name = "|cffff0000Admin|r", issued = T0, expires = T0 + 86400, level = 1e9, wins = -5, history = { { mode = "b120", res = "x" }, "junk" } },
      pending = { code = "short", linkId = "x", at = "now" },
    }
    evil["Bad|Name-Realm"] = { note = "unlinked" }
    evil["Bob-Realm"] = { profile = { name = "No link" } }
    local c = net.add({ name = "Alice", saved = { accounts = evil } })
    local acc = c.ns.db.accounts
    local n = 0
    for _ in pairs(acc) do n = n + 1 end
    ok(n <= c.ns.Account.MAX_CHARS, "bounded: " .. n)
    ok(acc["Bad|Name-Realm"] == nil); ok(acc["Bob-Realm"] == nil, "a profile without a link is dropped")
    local a = acc["Alice-Realm"]
    ok(a and a.link and a.profile, "Alice kept")
    eq(a.pending, nil, "broken pending dropped")
    eq(a.profile.level, 0, "out-of-range level reset"); eq(a.profile.wins, 0)
    eq(#a.profile.history, 0, "bad history rows dropped")
  end)
end)

describe("Account sheet (simulated client)", function()
  it("type the code, copy the request, paste the snapshot: LINKED and the Profile tab fills", function()
    local net = NS.new({ seed = 20 })
    local c = net.add({ name = "Alice", saved = { seenHelp = true } })
    c.M.serverTime = T0
    c.env.SlashCmdList.STACKRIVALS("")
    local UI = c.ns.UI
    UI.accBtn:Click()
    local s = UI.accountSheet
    ok(s:IsShown(), "Account sheet")
    eq(s.acc.status.chip:GetText(), "NOT LINKED")
    s.acc.code:SetText("wrong")
    s.acc.link:Click()
    ok(UI.accountNote and UI.accountNote:find("8 letters"), tostring(UI.accountNote))
    s.acc.code:SetText(A.prettyWebCode(A.makeWebCode("VXFZW21")))
    s.acc.link:Click()
    eq(s.acc.status.chip:GetText(), "PENDING")
    local req = s.acc.request:GetText()
    ok(A.parseLinkRequest(req), "the box holds the request: " .. req)
    -- typing into the copy box can't change it
    s.acc.request:SetText("hacked")
    eq(s.acc.request:GetText(), req)
    local r = A.parseLinkRequest(req)
    c.M.serverTime = T0 + 60
    s.acc.paste:SetText(snap({ linkId = r.linkId, issued = T0 + 30, expires = T0 + 86400 }))
    s.acc.import:Click()
    eq(s.acc.status.chip:GetText(), "LINKED")
    ok(UI.accountNote:find("Linked"), UI.accountNote)
    s.tabs.profile:Click()
    ok(s.prof:IsShown())
    eq(s.prof.name:GetText(), "Alice Stack"); eq(s.prof.rank:GetText(), "GOLD II")
    eq(s.prof.hist[1].mode:GetText(), "Duel 2:00"); eq(s.prof.hist[1].res:GetText(), "W")
    ok(s.prof.foot:GetText():find("Display only"), s.prof.foot:GetText())
    -- unlink needs two clicks
    s.tabs.account:Click()
    s.acc.unlink:Click()
    eq(s.acc.status.chip:GetText(), "LINKED", "first click only arms it")
    s.acc.unlink:Click()
    eq(s.acc.status.chip:GetText(), "NOT LINKED")
  end)
  it("a name with WoW escape codes from the website is shown as text, not colours or links", function()
    local net = NS.new({ seed = 21 })
    local c = net.add({ name = "Alice", saved = { seenHelp = true } })
    c.M.serverTime = T0
    local req = assert(c.ns.Account.startLink(A.makeWebCode("ESCAPE1")))
    local r = A.parseLinkRequest(req)
    c.M.serverTime = T0 + 60
    ok(c.ns.Account.import(snap({ linkId = r.linkId, issued = T0 + 30, expires = T0 + 86400, name = "|cffff0000Red|r", rank = "|Hitem:1|h" })))
    c.env.SlashCmdList.STACKRIVALS("")
    c.ns.UI:ShowSheet("account")
    c.ns.UI.accountSheet.tabs.profile:Click()
    eq(c.ns.UI.accountSheet.prof.name:GetText(), "||cffff0000Red||r")
    eq(c.ns.UI.accountSheet.prof.rank:GetText(), "||HITEM:1||H")
  end)
end)

return H
