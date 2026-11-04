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

describe("shared negative vectors docs/vectors/account_flow_v1.json (security)", function()
  local VEC = assert(loadfile(testdir .. "/account_flow_vectors.lua"))(root, testdir)
  it("is current (generated by running the addon; regenerate: lua5.1 tests/account_flow_vectors.lua StackRivals tests > docs/vectors/account_flow_v1.json)", function()
    local f = assert(io.open(root .. "/../docs/vectors/account_flow_v1.json", "rb"))
    local disk = f:read("*a"); f:close()
    ok(disk == VEC.text(), "docs/vectors/account_flow_v1.json is out of date")
  end)
  it("every attack the addon can see is refused, and nothing it refuses changes the profile", function()
    local want = {
      link_ok = "linked", update_ok = "updated", wrong_character = "player", other_link_while_pending = "link_other",
      other_link_when_linked = "link_other", made_before_request = "too_old_for_link", future_dated = "future", expired = "expired",
      older_than_current = "older", same_twice = "duplicate", no_request = "not_pending", request_expired = "pending_expired",
      newer_format = "version", link_request_pasted = "is_request", typo = "check", forged_but_rechecked = "updated",
    }
    local seen = 0
    for _, c in ipairs(VEC.build().addonImport) do
      seen = seen + 1
      local got = c.expect.ok and c.expect.result or c.expect.error
      eq(got, want[c.name], c.name)
      if not c.expect.ok then eq(c.profileChanged, false, c.name .. " must not change the profile") end
      if c.expect.ok then eq(c.expect.verified, false, c.name .. ": nothing is VERIFIED without a signature") end
    end
    eq(seen, 16)
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
    eq(s.acc.status.chip:GetText(), "PENDING CONFIRMATION")
    local req = s.acc.request:GetText()
    ok(A.parseLinkRequest(req), "the box holds the request: " .. req)
    -- typing into the copy box can't change it
    s.acc.request:SetText("hacked")
    eq(s.acc.request:GetText(), req)
    local r = A.parseLinkRequest(req)
    c.M.serverTime = T0 + 60
    s.acc.paste:SetText(snap({ linkId = r.linkId, issued = T0 + 30, expires = T0 + 86400 }))
    s.acc.import:Click()
    eq(s.acc.status.chip:GetText(), "LINKED - UNVERIFIED")
    ok(UI.accountNote:find("Linked"), UI.accountNote)
    s.tabs.profile:Click()
    ok(s.prof:IsShown())
    eq(s.prof.name:GetText(), "Alice Stack"); eq(s.prof.rank:GetText(), "GOLD II")
    eq(s.prof.hist[1].mode:GetText(), "Duel 2:00"); eq(s.prof.hist[1].res:GetText(), "W")
    ok(s.prof.foot:GetText():find("Nothing unlocks in WoW", 1, true), s.prof.foot:GetText())
    -- unlink needs two clicks
    s.tabs.account:Click()
    s.acc.unlink:Click()
    eq(s.acc.status.chip:GetText(), "LINKED - UNVERIFIED", "first click only arms it")
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

describe("profile view: one shape for every snapshot format, display only", function()
  local function linked(seed)
    local net = NS.new({ seed = seed })
    local c = net.add({ name = "Alice", saved = { seenHelp = true } })
    c.M.serverTime = T0
    local req = assert(c.ns.Account.startLink(A.makeWebCode("VXEW001")))
    local r = A.parseLinkRequest(req)
    c.M.serverTime = T0 + 60
    assert(c.ns.Account.import(snap({ linkId = r.linkId, issued = T0 + 30, expires = T0 + 30 + 14 * 86400 })))
    return c, c.ns.Account, r
  end
  local function openProfile(c)
    c.env.SlashCmdList.STACKRIVALS("")
    c.ns.UI:ShowSheet("account")
    c.ns.UI.accountSheet.tabs.profile:Click()
    return c.ns.UI.accountSheet.prof
  end

  it("not linked: no view", function()
    local net = NS.new({ seed = 40 })
    local c = net.add({ name = "Alice" })
    local v, st = c.ns.Account.profileView()
    eq(v, nil); eq(st, "not_linked")
  end)
  it("SRP1 maps into the view: when the website made it, when it was pasted, by hand; no Shards", function()
    local c, Acc = linked(41)
    local v, st = Acc.profileView()
    eq(st, "linked")
    eq(v.format, "SRP1"); eq(v.source, "manual"); eq(v.asOf, T0 + 30); eq(v.importedAt, T0 + 60); eq(v.stale, false)
    eq(v.name, "Alice Stack"); eq(v.level, 12); eq(v.xp, 1240); eq(v.rank, "Gold II"); eq(#v.history, 2)
    eq(v.shards, nil, "SRP1 carries no Shards; the addon never makes up a balance")
    eq(v.verified, false, "no signature check in this version")
  end)
  it("the Profile tab says when it was last updated, that it was pasted by hand and is unverified; no Shards", function()
    local c = linked(42)
    local p = openProfile(c)
    local up, foot = p.updated:GetText(), p.foot:GetText()
    ok(up:find("Last update " .. c.env.date("%d %b %Y, %H:%M", T0 + 30), 1, true), up)
    ok(foot:find("Pasted by hand, so it may be out of date", 1, true), foot)
    ok(foot:find("Nothing unlocks in WoW", 1, true), foot)
    ok(not foot:find("OUT OF DATE", 1, true), foot)
    eq(p.trust:GetText(), "UNVERIFIED", "no signature check exists yet")
    eq(p.shards:GetText(), "", "no Shards from SRP1")
    ok(not p.extra:GetText():find("Shards", 1, true), p.extra:GetText())
  end)
  it("after 7 days the view is stale and the tab says OUT OF DATE (in gold) and how to fix it", function()
    local c, Acc = linked(43)
    c.M.serverTime = T0 + 30 + 8 * 86400
    local v, st = Acc.profileView()
    eq(st, "not_synced"); eq(v.stale, true)
    local p = openProfile(c)
    ok(p.foot:GetText():find("OUT OF DATE: paste a new snapshot from stackrivals.io", 1, true), p.foot:GetText())
    ok(p.updated:GetText():find("8 days ago", 1, true), p.updated:GetText())
    local r, g, b = p.foot:GetTextColor()
    local gold = c.ns.T.C.gold
    ok(math.abs(r - gold[1]) < 0.01 and math.abs(g - gold[2]) < 0.01 and math.abs(b - gold[3]) < 0.01, "stale text is gold")
  end)
  it("'days ago' counts calendar days, not 24-hour blocks", function()
    local c, Acc = linked(46)
    local UI = c.ns.UI
    local function at(y, mo, d, h, mi) return os.time({ year = y, month = mo, day = d, hour = h, min = mi }) end
    local cases = {
      { at(2026, 10, 26, 8, 36), at(2026, 11, 7, 8, 30), "12 days ago" },   -- 11.99 x 24 h, but 12 dates later
      { at(2026, 10, 26, 23, 50), at(2026, 10, 28, 0, 10), "2 days ago" },  -- 24 h 20 min
      { at(2026, 10, 26, 22, 0), at(2026, 10, 27, 7, 0), "yesterday" },
      { at(2026, 10, 27, 1, 0), at(2026, 10, 27, 7, 0), "6 h ago" },
      { at(2026, 10, 27, 7, 0), at(2026, 10, 27, 7, 45), "45 min ago" },
      { at(2026, 10, 27, 7, 0), at(2026, 10, 27, 7, 1), "just now" },
      { at(2026, 2, 27, 12, 0), at(2026, 3, 2, 12, 0), "3 days ago" },     -- across February
      { at(2026, 12, 31, 12, 0), at(2027, 1, 1, 9, 0), "yesterday" },      -- across the year
    }
    for _, k in ipairs(cases) do
      c.M.serverTime = k[2]
      eq(UI.accountAgo(k[1]), k[3], os.date("%Y-%m-%d %H:%M", k[1]) .. " -> " .. os.date("%Y-%m-%d %H:%M", k[2]))
    end
    eq(UI.accountDayNumber(os.time({ year = 1970, month = 1, day = 1, hour = 12 })), 0)
  end)
  it("a Shards line appears only when an approved format fills the view", function()
    local c, Acc = linked(44)
    local real = Acc.profileView
    Acc.profileView = function() local v, st = real(); v.shards = 1234; return v, st end
    local p = openProfile(c)
    Acc.profileView = real
    eq(p.shards:GetText(), "1,234 SHARDS")
    ok(p.shards:IsShown())
  end)
  it("long names, ranks, seasons and cosmetics are cut with '...' instead of running into each other", function()
    local net = NS.new({ seed = 47 })
    local c = net.add({ name = "Alice", saved = { seenHelp = true } })
    c.M.serverTime = T0
    local req = assert(c.ns.Account.startLink(A.makeWebCode("VXEW002")))
    local r = A.parseLinkRequest(req)
    c.M.serverTime = T0 + 60
    ok(c.ns.Account.import(snap({ linkId = r.linkId, issued = T0 + 30, expires = T0 + 86400,
      name = "Wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww", rank = "Grandmaster Champion III", season = "Season of the Long Night",
      cosEquipped = "Wwwwwwwwwwwwwwwwwwwwwwww" })))
    local p = openProfile(c)
    for _, k in ipairs({ "name", "rank", "stats", "shards", "extra", "updated", "foot", "trust" }) do
      ok(p[k]._nowrap, k .. " is one line")
      ok((p[k]._w or 0) > 0, k .. " has a width")
    end
    ok(p.name._w + p.rank._w + 12 <= p._w - 28 + 0.5, "name and rank share the top line")
  end)
  it("a code of another kind pasted in the snapshot box says where it belongs", function()
    local c, Acc, r = linked(49)
    local before = Acc.profileView().asOf
    local req = A.linkRequest({ code = A.makeWebCode("A7K9P2X"), platform = "wow-forever", player = "Alice-Realm", linkId = r.linkId, addon = "0.9.0", engine = 1, issued = T0 })
    local _, why = Acc.import(req); eq(why, "is_request"); ok(Acc.ERRORS.is_request:find("not here", 1, true))
    _, why = Acc.import("  SR1R.wow-forever.b120.e1.x"); eq(why, "is_result"); ok(Acc.ERRORS.is_result:find("Import result", 1, true))
    _, why = Acc.import("SR1C.abc"); eq(why, "is_challenge"); ok(Acc.ERRORS.is_challenge:find("Sync tab", 1, true))
    eq(Acc.profileView().asOf, before, "nothing changed")
  end)
  it("every account screen names the website pages the same way (one table, Account.WEB)", function()
    local c = linked(50)
    local W = c.ns.Account.WEB
    for _, k in ipairs({ "link", "export", "results", "unlink" }) do ok(W[k]:find("^stackrivals%.io/wow > "), k) end
    ok(W.results:find("(planned)", 1, true), "Import result isn't built on the website yet")
    c.env.SlashCmdList.STACKRIVALS("")
    c.ns.UI:ShowSheet("account")
    local s = c.ns.UI.accountSheet
    ok(s.acc.steps:GetText():find(W.export, 1, true), s.acc.steps:GetText())
    s.acc.unlink:Click(); s.acc.unlink:Click()
    ok(c.ns.UI.accountNote:find(W.unlink, 1, true), c.ns.UI.accountNote)
    ok(s.acc.steps:GetText():find("Link WoW character", 1, true), s.acc.steps:GetText())
  end)
  it("the Account tab never shows a plain green LINKED: a pasted snapshot is LINKED - UNVERIFIED; VERIFIED needs a checked signature", function()
    local c, Acc = linked(51)
    c.env.SlashCmdList.STACKRIVALS("")
    c.ns.UI:ShowSheet("account")
    local a = c.ns.UI.accountSheet.acc
    eq(a.status.chip:GetText(), "LINKED - UNVERIFIED")
    local r, g, b = a.status.chip:GetTextColor()
    local gold = c.ns.T.C.gold
    ok(math.abs(r - gold[1]) < 0.01 and math.abs(g - gold[2]) < 0.01 and math.abs(b - gold[3]) < 0.01, "gold, not green")
    ok(a.status.trust:GetText():find("not checked", 1, true), a.status.trust:GetText())
    -- only a view that says verified (a future signature check) turns it green
    local real = Acc.profileView
    Acc.profileView = function() local v, st = real(); v.verified = true; return v, st end
    c.ns.UI:RefreshAccount()
    eq(a.status.chip:GetText(), "VERIFIED")
    Acc.profileView = real
    -- out of date
    c.M.serverTime = T0 + 30 + 8 * 86400
    c.ns.UI:RefreshAccount()
    eq(a.status.chip:GetText(), "OUT OF DATE")
    -- no snapshot field can make it VERIFIED today: profileView always says verified = false
    eq(Acc.profileView().verified, false)
  end)
  it("the second status line (what the state means) fits on one line in every state", function()
    local L = dofile(testdir .. "/layout.lua")
    local function fits(a, what)
      local t = a.status.trust
      ok(L.textWidth(t:GetText(), t._font[2], t._font[1]) <= t._w, what .. ": " .. t:GetText())
    end
    local net = NS.new({ seed = 61 })
    local c = net.add({ name = "Alice", saved = { seenHelp = true } })
    c.M.serverTime = T0
    c.env.SlashCmdList.STACKRIVALS(""); c.ns.UI:ShowSheet("account")
    local a = c.ns.UI.accountSheet.acc
    fits(a, "not linked")
    local r = A.parseLinkRequest(assert(c.ns.Account.startLink(A.makeWebCode("FXTS001"))))
    c.ns.UI:RefreshAccount(); fits(a, "pending")
    c.M.serverTime = T0 + 60
    assert(c.ns.Account.import(snap({ linkId = r.linkId, issued = T0 + 30, expires = T0 + 30 + 7 * 86400 })))
    c.ns.UI:RefreshAccount(); fits(a, "linked")
    c.M.serverTime = T0 + 9 * 86400
    c.ns.UI:RefreshAccount(); fits(a, "out of date")
  end)
  it("a refused paste says REJECTED (in red) and keeps the profile you had", function()
    local c, Acc = linked(52)
    c.env.SlashCmdList.STACKRIVALS("")
    c.ns.UI:ShowSheet("account")
    local a = c.ns.UI.accountSheet.acc
    local before = Acc.profileView().asOf
    a.paste:SetText(snap({ linkId = "zzzzzzzzzzzz", issued = T0 + 50, expires = T0 + 86400 }))
    a.import:Click()
    ok(c.ns.UI.accountNote:find("^REJECTED: "), c.ns.UI.accountNote)
    local r, g, b = a.note:GetTextColor()
    local red = c.ns.T.C.redLight
    ok(math.abs(r - red[1]) < 0.01 and math.abs(g - red[2]) < 0.01 and math.abs(b - red[3]) < 0.01, "red")
    eq(Acc.profileView().asOf, before, "profile unchanged")
    eq(a.status.chip:GetText(), "LINKED - UNVERIFIED")
  end)
  it("step 2: Select puts the whole link request in the box, selected; only Ctrl+C in the box says it was pressed", function()
    local net = NS.new({ seed = 53 })
    local c = net.add({ name = "Alice", saved = { seenHelp = true } })
    c.M.serverTime = T0
    c.env.SlashCmdList.STACKRIVALS("")
    c.ns.UI:ShowSheet("account")
    local a = c.ns.UI.accountSheet.acc
    a.code:SetText(A.prettyWebCode(A.makeWebCode("SEXECT1")))
    a.link:Click()
    eq(a.status.chip:GetText(), "PENDING CONFIRMATION")
    ok(a.select:IsShown())
    a.select:Click()
    eq(a.request:GetText(), c.ns.Account.requestCode(), "the whole request")
    ok(a.request._highlighted and a.request._focus)
    ok(c.ns.UI.accountNote:find("^Selected"), c.ns.UI.accountNote)
    ok(not c.ns.UI.accountNote:lower():find("copied"), c.ns.UI.accountNote)
    -- the tab refreshes every second (expiry countdown): the selection must survive it until Ctrl+C
    -- (Classic Era 1.15.9, 4 Nov 2026: "the selection disappears" — every refresh re-set the same text)
    local sheet = c.ns.UI.accountSheet
    for _ = 1, 3 do sheet._scripts.OnUpdate(sheet, 1.1) end
    ok(a.request._highlighted and a.request._focus, "still selected after three refreshes")
    eq(a.request:GetText(), c.ns.Account.requestCode())
    c.M.ctrl = true; a.request._scripts.OnKeyDown(a.request, "C"); c.M.ctrl = false
    ok(c.ns.UI.accountNote:find("^Ctrl%+C pressed"), c.ns.UI.accountNote)
    sheet._scripts.OnUpdate(sheet, 1.1)
    ok(a.request._highlighted, "and after the refresh that shows 'Ctrl+C pressed'")
  end)
  it("a client without OnKeyDown on edit boxes still works (no 'Ctrl+C pressed', never a Lua error)", function()
    local net = NS.new({ seed = 54 })
    local c = net.add({ name = "Alice", saved = { seenHelp = true } })
    c.env.SlashCmdList.STACKRIVALS("")
    c.M.noEditBoxKeyDown = true
    local box = c.ns.UI.accountCopyBox(c.ns.UI.accountSheet or c.env.StackRivalsFrame, 200)
    eq(box._scripts.OnKeyDown, nil, "no key handler where the client has none")
    box:SetValue("SRL1.test"); box:SelectAll()
    eq(box:GetText(), "SRL1.test"); ok(box._highlighted)
  end)
  --- Link Alice with a snapshot built from `o` (the website side, simulated) and open the Profile tab.
  local function profileWith(seed, o, now)
    local net = NS.new({ seed = seed })
    local c = net.add({ name = "Alice", saved = { seenHelp = true } })
    c.M.serverTime = T0
    local r = A.parseLinkRequest(assert(c.ns.Account.startLink(A.makeWebCode("EDGE001"))))
    c.M.serverTime = T0 + 60
    o.linkId = r.linkId; o.issued = o.issued or T0 + 30; o.expires = o.expires or T0 + 30 + 7 * 86400
    assert(c.ns.Account.import(snap(o)))
    if now then c.M.serverTime = now end
    return c, openProfile(c)
  end
  it("very large numbers: the biggest values SRP1 allows fit without overlap; Shards up to 12 digits fit their slot (more is cut, with a tooltip)", function()
    local c, p = profileWith(55, { level = 9999, xp = 1e12, xpNext = 1e12, wins = 1e9, losses = 1e9, draws = 1e9,
      achUnlocked = 9999, achTotal = 9999, cosOwned = 99999 })
    eq(p.xp.v:GetText(), "Level 9999  -  1,000,000,000,000 / 1,000,000,000,000 XP")
    local L = dofile(testdir .. "/layout.lua")
    ok(L.textWidth(p.xp.v:GetText(), p.xp.v._font[2], p.xp.v._font[1]) <= p.xp.v._w, "the XP line fits its box (left of it: the LEVEL label)")
    local real = c.ns.Account.profileView
    c.ns.Account.profileView = function() local v, st = real(); v.shards = 999999999999; return v, st end
    c.ns.UI:RefreshAccount()
    c.ns.Account.profileView = real
    eq(p.shards:GetText(), "999,999,999,999 SHARDS")
    ok(L.textWidth("999,999,999,999 SHARDS", p.shards._font[2], p.shards._font[1]) <= p.shards._w, "12 digits fit")
    ok(p.stats._w + p.shards._w + 6 <= p._w - 28 + 0.5, "record and Shards share the line")
  end)
  it("0 XP, no next level, missing rank / season / achievements / cosmetics, no matches", function()
    local _, p = profileWith(56, { level = 1, xp = 0, xpNext = 0, rank = false, season = false, seasonPct = 0,
      achUnlocked = false, cosOwned = false, noHistory = true, wins = 0, losses = 0, draws = 0 })
    eq(p.xp.v:GetText(), "Level 1  -  0 XP")
    eq(p.xp.fill._w, 1, "an empty bar, no division by zero")
    eq(p.rank:GetText(), "UNRANKED")
    eq(p.season.v:GetText(), "No season  -  0%")
    eq(p.stats:GetText(), "Wins 0  -  Losses 0  -  Draws 0", "no win rate without games")
    eq(p.extra:GetText(), "Achievements -  -  Cosmetics -")
    eq(p.hist[1].mode:GetText(), "No matches yet.")
  end)
  it("an expired snapshot (past its 'expires', inside 7 days) is OUT OF DATE too", function()
    local _, p = profileWith(57, { issued = T0 + 30, expires = T0 + 30 + 86400 }, T0 + 30 + 2 * 86400)
    ok(p.foot:GetText():find("OUT OF DATE", 1, true), p.foot:GetText())
  end)
  it("10 matches in the snapshot: 5 shown, the header says 5 OF 10", function()
    local hist = {}
    for i = 1, 10 do hist[i] = { mode = "b120", res = (i % 2 == 0) and "w" or "l", my = i * 1000, their = 500, at = T0 - i * 3600 } end
    local _, p = profileWith(58, { history = hist })
    eq(p.histHead:GetText(), "RECENT MATCHES (5 OF 10, MORE ON STACKRIVALS.IO)")
    for i = 1, 5 do ok(p.hist[i].mode:IsShown(), "row " .. i) end
  end)
  it("a cut text shows the whole text in a tooltip on hover; a text that fits shows none", function()
    local c, p = profileWith(59, { name = "Wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww", rank = "Gold II" })
    local shown
    c.env.GameTooltip = { SetOwner = function() end, SetText = function(_, t) shown = t end, Show = function() end, Hide = function() end }
    local function hoverOf(fs) for _, h in ipairs(p.tips) do if h.fs == fs then return h end end end
    ok(p.name:IsTruncated(), "the long name is cut")
    hoverOf(p.name)._scripts.OnEnter(hoverOf(p.name))
    eq(shown, "Wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww")
    shown = nil
    hoverOf(p.rank)._scripts.OnEnter(hoverOf(p.rank))
    eq(shown, nil, "GOLD II fits: no tooltip")
  end)
  it("no tooltip area covers the Link account button when there is no profile", function()
    local net = NS.new({ seed = 60 })
    local c = net.add({ name = "Alice", saved = { seenHelp = true } })
    local p = openProfile(c)
    ok(p.go:IsShown())
    for _, h in ipairs(p.tips) do ok(not h:IsShown(), "tooltip area hidden") end
  end)
  it("every Profile text is on the type scale (>= the label size), so it stays readable at every resolution and UI scale", function()
    local c = linked(48)
    local p = openProfile(c)
    local floor = c.ns.T.SIZE.label
    local n = 0
    for _, o in ipairs(c.M.regions) do
      local cur, inside = o, false
      while cur do if cur == p then inside = true break end; cur = cur._parent end
      if inside and o._kind == "FontString" and o._font then
        n = n + 1
        ok(o._font[2] >= floor, "text size " .. tostring(o._font[2]) .. ": " .. tostring(o._text))
      end
    end
    ok(n >= 20, "checked " .. n .. " texts")
  end)
  it("a newer format (SRP3) is refused with 'update' and leaves the current profile as it was", function()
    local c, Acc, r = linked(45)
    local before = Acc.profileView()
    c.M.serverTime = T0 + 3600
    local s2 = snap({ linkId = r.linkId, issued = T0 + 3000, expires = T0 + 86400 })
    local okI, why = Acc.import("SRP3" .. s2:sub(5))
    eq(okI, nil); eq(why, "version"); ok(Acc.ERRORS.version:find("update"), Acc.ERRORS.version)
    local after = Acc.profileView()
    eq(after.asOf, before.asOf); eq(after.importedAt, before.importedAt); eq(after.shards, nil)
  end)
  it("an SRP2 snapshot updates the profile with the website's Shards, cosmetics and events (display only)", function()
    local c, Acc, r = linked(45)
    c.M.serverTime = T0 + 3600
    local code = A.profile2({
      linkId = r.linkId, player = "Alice-Realm", accountId = "acc_7f3k2", name = "Alice Stack", issued = T0 + 3000, expires = T0 + 86400,
      level = 13, xp = 10, xpNext = 2100, seasonPct = 46, wins = 13, losses = 8, draws = 1, history = {},
      shards = 1250, asOf = T0 + 2990, equipped = { skin = "skin_solar_inferno" }, owned = { "skin_solar_inferno", "skin_circuit" },
      events = { { kind = "overdrive", state = "live", start = T0 + 2000, ["end"] = T0 + 9000, value = 200 } },
    })
    local okI, res = Acc.import(code)
    eq(okI, true); eq(res, "updated")
    local v = Acc.profileView()
    eq(v.format, "SRP2"); eq(v.shards, 1250); eq(v.asOf, T0 + 2990); eq(v.level, 13)
    eq(v.equipped.skin, "skin_solar_inferno"); eq(#v.owned, 2); eq(v.owned[1], "skin_circuit")
    eq(#v.events, 1); eq(v.events[1].kind, "overdrive"); eq(v.events[1].value, 200)
    eq(v.verified, false) -- no signature check in this version: nothing is applied from it
    -- an SRP1 afterwards (newer) replaces it and the extras go away again (SRP1 has none)
    c.M.serverTime = T0 + 4000
    eq(Acc.import(snap({ linkId = r.linkId, issued = T0 + 3500, expires = T0 + 86400 })), true)
    v = Acc.profileView()
    eq(v.format, "SRP1"); eq(v.shards, nil); eq(#v.owned, 0); eq(#v.events, 0)
  end)
  it("SRP2 extras survive a reload (saved variables) and stay bounded", function()
    local c, Acc, r = linked(45)
    c.M.serverTime = T0 + 3600
    local code = A.profile2({
      linkId = r.linkId, player = "Alice-Realm", accountId = "acc_7f3k2", name = "Alice Stack", issued = T0 + 3000, expires = T0 + 86400,
      level = 13, xp = 10, xpNext = 2100, seasonPct = 46, wins = 13, losses = 8, draws = 1, history = {},
      shards = 77, asOf = T0 + 3000, equipped = { frame = "frame_neon_rival" }, owned = { "frame_neon_rival" },
      events = { { kind = "storm", state = "up", start = T0 + 5000, ["end"] = T0 + 5900, value = 25 } },
    })
    eq(Acc.import(code), true)
    local raw = Acc.rec()
    local clean = Acc.sanitize({ ["Alice-Realm"] = raw })
    local pr = clean["Alice-Realm"].profile
    eq(pr.format, "SRP2"); eq(pr.shards, 77); eq(pr.equipped.frame, "frame_neon_rival"); eq(pr.owned[1], "frame_neon_rival")
    eq(pr.events[1].kind, "storm"); eq(pr.events[1].value, 25)
    raw.profile.shards, raw.profile.owned = -5, { "BAD ID", "ok_id" }
    pr = Acc.sanitize({ ["Alice-Realm"] = raw })["Alice-Realm"].profile
    eq(pr.shards, nil); eq(#pr.owned, 1); eq(pr.owned[1], "ok_id")
  end)
end)

return H
