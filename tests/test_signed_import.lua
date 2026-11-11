-- 0.9.1: signed profile codes end to end in a simulated client (SRP1-SIG v1 and SRP2-SIG v1), the security cases
-- from the 0.9.1 brief, and how long verification takes / how it is spread over frames so WoW never freezes.
-- Codes come from the website's vectors (docs/vectors/srp1_sig_v1.json, srp2_v1.json; RFC 8032 TEST 1 key, kid t1,
-- given to the addon ONLY inside these tests). Edited codes get a recomputed check value (the check only catches
-- typos), so the SIGNATURE is what must refuse them.
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local J = dofile(testdir .. "/jsonread.lua")
local NS = assert(loadfile(testdir .. "/netsim.lua"))(root, testdir)
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe

local V1 = J.read(root .. "/../docs/vectors/srp1_sig_v1.json")
local V2 = J.read(root .. "/../docs/vectors/srp2_v1.json")
local function case(V, list, name) for _, c in ipairs(V[list]) do if c.name == name then return c.code end end; error(name) end
local VALID2, VALID1 = case(V2, "sig", "valid"), case(V1, "cases", "valid")
local T1 = { t1 = V2.testKey.public }
local ISSUED = 1793000060

--- Alice-Realm with a pending request for the vectors' linkId; `keys` replaces the shipped key table (tests only).
local function client(seed, keys)
  local net = NS.new({ seed = seed })
  local c = net.add({ name = "Alice", saved = { seenHelp = true } })
  c.M.serverTime = ISSUED - 60
  assert(c.ns.Account.startLink(c.ns.AccountCodes.makeWebCode("A7K9P2X")))
  c.ns.Account.rec().pending.linkId = "k3v9q2m7x1aa"
  c.M.serverTime = ISSUED + 30
  local K = c.ns.SnapshotSig.KEYS
  for k in pairs(K) do K[k] = nil end
  for k, v in pairs(keys or {}) do K[k] = v end
  return net, c, c.ns.Account
end
--- Change field i (0-based, as in the spec) of a code and recompute the check value (a careful forger).
local PRNG
local function edit(ns, code, i, value)
  PRNG = (ns and ns.Prng) or PRNG
  local f = {}
  for part in (code .. "."):gmatch("([^.]*)%.") do f[#f + 1] = part end
  f[i + 1] = value
  table.remove(f)
  local body = table.concat(f, ".")
  return body .. "." .. string.format("%08x", PRNG.hashString(body))
end
local function hex(s) return (s:gsub(".", function(ch) return string.format("%02x", ch:byte()) end)) end
--- Run an async import to its end; returns ok, result, frames used.
local function importAsync(net, Acc, code)
  local done, r1, r2
  local started = Acc.importAsync(code, function(a, b) done, r1, r2 = true, a, b end)
  ok(started, "started")
  local frames = 0
  while not done and frames < 2000 do net.step(1); frames = frames + 1 end
  ok(done, "finished")
  return r1, r2, frames
end

describe("signed codes: the 0.9.1 security cases", function()
  it("valid signature -> VERIFIED (SRP2 and SRP1); the Account line says it proves origin, not character ownership", function()
    local net, c, Acc = client(1, T1)
    local okI, res = importAsync(net, Acc, VALID2)
    ok(okI, tostring(res))
    eq(Acc.profileView().verified, true)
    c.env.SlashCmdList.STACKRIVALS(""); c.ns.UI:ShowSheet("account")
    local a = c.ns.UI.accountSheet.acc
    eq(a.status.chip:GetText(), "VERIFIED")
    ok(a.status.trust:GetText():find("proves its origin, not character ownership", 1, true), a.status.trust:GetText())
    local net1, _, Acc1 = client(2, T1)
    ok((importAsync(net1, Acc1, VALID1)))
    eq(Acc1.profileView().verified, true)
  end)
  it("missing signature -> UNVERIFIED; unknown key id -> UNVERIFIED with 'update StackRivals'", function()
    local _, _, Acc = client(3, T1)
    ok(Acc.import(case(V2, "sig", "unsigned")))
    eq(Acc.profileView().verified, false)
    local _, c2, Acc2 = client(4, T1)
    ok(Acc2.import(case(V2, "sig", "unknown_kid")))
    eq(Acc2.profileView().verified, false)
    c2.env.SlashCmdList.STACKRIVALS(""); c2.ns.UI:ShowSheet("account")
    ok(c2.ns.UI.accountSheet.acc.status.trust:GetText():find("update StackRivals", 1, true), c2.ns.UI.accountSheet.acc.status.trust:GetText())
    eq(c2.ns.UI.accountSheet.acc.status.chip:GetText(), "LINKED - UNVERIFIED")
  end)
  it("edited XP, Shards, rank, character, display name, linkId or signature -> REJECTED (signature), nothing linked", function()
    local _, c0 = client(5, T1)
    local ns = c0.ns
    local edits = {
      xp = edit(ns, VALID2, 8, "zz"),
      shards = edit(ns, VALID2, 19, "zzz"),
      rank = edit(ns, VALID2, 10, hex("Grandmaster")),
      character = edit(ns, VALID2, 2, hex("Bob-Realm")),
      displayName = edit(ns, VALID2, 4, hex("Mallory")),
      linkId = edit(ns, VALID2, 1, "zzzzzzzzzzzz"),
      owned = case(V2, "sig", "owned_changed"),
      signature = edit(ns, VALID2, 24, "t1" .. ("A"):rep(86)),
      srp1Xp = case(V1, "cases", "xp_changed"),
    }
    for what, code in pairs(edits) do
      local net, _, Acc = client(6, T1)
      local okI, why = importAsync(net, Acc, code)
      eq(okI, nil, what); eq(why, "signature", what)
      eq(Acc.profileView(), nil, what .. ": nothing linked")
    end
  end)
  it("an edited code never overwrites the VERIFIED profile you have", function()
    local net, c, Acc = client(7, T1)
    ok((importAsync(net, Acc, VALID2)))
    local before = Acc.profileView()
    local okI, why = importAsync(net, Acc, edit(c.ns, VALID2, 19, "zzz"))
    eq(okI, nil); eq(why, "signature")
    local after = Acc.profileView()
    eq(after.verified, true); eq(after.shards, before.shards); eq(after.asOf, before.asOf)
  end)
  it("an expired code is refused; a VERIFIED profile that ages shows OUT OF DATE (still from the website)", function()
    local net, c, Acc = client(8, T1)
    c.M.serverTime = 1793604860 + 3600 -- past expires (+ clock skew)
    local okI, why = importAsync(net, Acc, VALID2)
    eq(okI, nil); eq(why, "expired")
    local net2, c2, Acc2 = client(9, T1)
    ok((importAsync(net2, Acc2, VALID2)))
    c2.M.serverTime = ISSUED + 8 * 86400
    c2.env.SlashCmdList.STACKRIVALS(""); c2.ns.UI:ShowSheet("account")
    eq(c2.ns.UI.accountSheet.acc.status.chip:GetText(), "OUT OF DATE")
    eq(Acc2.profileView().stale, true)
  end)
  -- A reload with the test key in the key table (the shipped table is empty until the production key exists).
  local function reloadWith(net, c, keys, mutate)
    c.M.fire("PLAYER_LOGOUT")
    local saved = c.env.StackRivalsDB
    if mutate then mutate(saved.accounts["Alice-Realm"]) end
    local net2 = NS.new({ seed = 99 })
    local n = net2.add({ name = "Alice", saved = saved, beforeLogin = function(_, M, ns)
      M.serverTime = ISSUED + 120
      for k, v in pairs(keys or {}) do ns.SnapshotSig.KEYS[k] = v end -- before the file is read (ADDON_LOADED)
    end })
    n.M.serverTime = ISSUED + 120
    for _ = 1, 400 do net2.step(1) end
    return n, n.ns.Account
  end
  it("after /reload a VERIFIED profile is checked again from its signed code, and is VERIFIED again", function()
    local net, c, Acc = client(20, T1)
    ok((importAsync(net, Acc, VALID2)))
    local before = Acc.profileView()
    local n, Acc2 = reloadWith(net, c, T1)
    local v = Acc2.profileView()
    eq(v.verified, true); eq(v.shards, before.shards); eq(v.name, before.name); eq(#v.owned, #before.owned)
    eq(Acc2.rec().profile.recheck, nil)
  end)
  it("SavedVariables edited by hand: more Shards / more cosmetics on a VERIFIED profile are undone by the signed code", function()
    local net, c, Acc = client(21, T1)
    ok((importAsync(net, Acc, VALID2)))
    local before = Acc.profileView()
    local n, Acc2 = reloadWith(net, c, T1, function(r)
      r.profile.shards = 999999
      r.profile.owned = { "skin_solar_inferno", "skin_circuit" }
      r.profile.equipped = { skin = "skin_solar_inferno" }
      r.profile.level = 99
    end)
    local v = Acc2.profileView()
    eq(v.verified, true); eq(v.shards, before.shards); eq(v.level, before.level); eq(#v.owned, #before.owned)
    local had = {}
    for _, id in ipairs(before.owned) do had[id] = true end
    for _, e in pairs(before.equipped) do had[e] = true end
    for _, it in ipairs(n.ns.CosmeticsCatalog.items) do
      eq(Acc2.canApplyCosmetic(it.id), had[it.id] == true, it.id) -- exactly what the website signed, nothing more
    end
  end)
  it("SavedVariables edited by hand: 'verified = true' without the signed code, or with an edited code, is UNVERIFIED and unlocks nothing", function()
    for name, mutate in pairs({
      no_code = function(r) r.profile.code = nil; r.profile.owned = { "skin_solar_inferno" } end,
      edited_code = function(r) r.profile.code = edit(nil, r.profile.code, 19, "zzz"); r.profile.shards = 46655; r.profile.owned = { "skin_solar_inferno" } end,
      other_link = function(r) r.link.linkId = "aaaaaaaaaaaa"; r.profile.linkId = "aaaaaaaaaaaa" end,
      forged_from_nothing = function(r)
        r.profile = { linkId = r.link.linkId, accountId = r.link.accountId, name = "Mallory", issued = ISSUED, expires = ISSUED + 86400,
          level = 99, xp = 1, xpNext = 2, wins = 0, losses = 0, draws = 0, history = {}, signed = true, check = "0a0b0c0d",
          verified = true, kid = "t1", format = "SRP2", shards = 999999, asOf = ISSUED, owned = { "skin_solar_inferno" },
          equipped = { skin = "skin_solar_inferno" }, events = {}, code = "SRP2.not.a.real.code" }
      end,
    }) do
      local net, c, Acc = client(22, T1)
      ok((importAsync(net, Acc, VALID2)))
      local n, Acc2 = reloadWith(net, c, T1, mutate)
      local v = Acc2.profileView()
      ok(v, name .. ": still has a profile"); eq(v.verified, false, name)
      eq(Acc2.canApplyCosmetic("skin_solar_inferno"), false, name)
      eq(Acc2.rec().profile.code, nil, name .. ": the useless code is dropped")
    end
  end)
  it("an UNVERIFIED profile keeps no code and does no signature work after a reload", function()
    local net, c, Acc = client(23, {})
    ok((importAsync(net, Acc, VALID2))) -- unknown kid: unverified
    eq(Acc.rec().profile.code, nil)
    local n, Acc2 = reloadWith(net, c, {})
    eq(Acc2.profileView().verified, false); eq(Acc2.rec().profile.recheck, nil)
  end)
  it("old saved profiles (0.8.x / 0.9.0, no signature fields) still load, as UNVERIFIED", function()
    local net = NS.new({ seed = 10 })
    local saved = { seenHelp = true, accounts = { ["Alice-Realm"] = {
      link = { linkId = "k3v9q2m7x1aa", accountId = "acc_7f3k2", at = ISSUED },
      profile = { linkId = "k3v9q2m7x1aa", accountId = "acc_7f3k2", name = "Alice Stack", issued = ISSUED, expires = ISSUED + 86400,
        level = 3, xp = 10, xpNext = 100, wins = 1, losses = 0, draws = 0, history = {}, signed = false, check = "0a0b0c0d" },
      lastSync = ISSUED } } }
    local c = net.add({ name = "Alice", saved = saved })
    c.M.serverTime = ISSUED + 60
    local v = c.ns.Account.profileView()
    ok(v, "loaded"); eq(v.name, "Alice Stack"); eq(v.verified, false)
    -- a saved 'verified = true' with a kid this version doesn't ship is not trusted
    local net2 = NS.new({ seed = 11 })
    saved.accounts["Alice-Realm"].profile.verified = true; saved.accounts["Alice-Realm"].profile.kid = "zz"
    local c2 = net2.add({ name = "Alice", saved = saved })
    c2.M.serverTime = ISSUED + 60
    eq(c2.ns.Account.profileView().verified, false)
  end)
  it("the shipped key table holds no test key; tests add t1 themselves", function()
    local net = NS.new({ seed = 12 })
    local c = net.add({ name = "Alice" })
    eq(c.ns.SnapshotSig.KEYS.t1, nil)
    for _, hexKey in pairs(c.ns.SnapshotSig.KEYS) do ok(hexKey ~= V2.testKey.public, "RFC test key shipped") end
  end)
end)

describe("performance: verification never freezes WoW", function()
  it("one verification (valid / invalid / long code), measured; the async import spreads it over frames", function()
    local net, c, Acc = client(20, T1)
    local Ed, Sig = c.ns.Ed25519, c.ns.SnapshotSig
    local pub = Ed.hexBytes(V2.testKey.public)
    local function timeIt(fn) local t = os.clock(); local r = fn(); return (os.clock() - t) * 1000, r end
    local msOk, rOk = timeIt(function() return Sig.check(VALID2, T1).state end)
    local msBad, rBad = timeIt(function() return Sig.check(case(V2, "sig", "shards_changed"), T1).state end)
    eq(rOk, "verified"); eq(rBad, "invalid")
    -- the longest message SRP2 allows (~4 KB): SHA-512 grows, the curve work doesn't
    local sig = Ed.unb64url(("A"):rep(86))
    local msLong = timeIt(function() return Ed.verify(pub, sig, ("x"):rep(4096)) end)
    H.note(string.format("signature check: valid %.0f ms, invalid %.0f ms, 4 KB message %.0f ms (%s path)", msOk, msBad, msLong, Ed.bitPath))
    ok(msOk < 3000 and msBad < 3000 and msLong < 3000, "sane")
    -- async: no slice longer than a small budget; count the frames
    local maxSlice, frames, done = 0, 0, false
    local t = os.clock()
    Acc.importAsync(VALID2, function() done = true end)
    maxSlice = (os.clock() - t) * 1000
    while not done and frames < 2000 do
      t = os.clock(); net.step(1); frames = frames + 1
      maxSlice = math.max(maxSlice, (os.clock() - t) * 1000)
    end
    ok(done)
    H.note(string.format("async import: %d frames (%.1f s at 60 FPS, %.1f s at 15 FPS), longest slice %.1f ms",
      frames, frames / 60, frames / 15, maxSlice))
    ok(frames >= 5, "really spread over frames: " .. frames)
    ok(maxSlice < 60, "no long freeze: " .. maxSlice .. " ms")
  end)
  it("the work per frame is fixed, so a low frame rate only means more seconds, never a longer freeze", function()
    local net, _, Acc = client(21, T1)
    local okI, res, frames = importAsync(net, Acc, VALID2)
    ok(okI, tostring(res)); eq(Acc.profileView().verified, true)
    ok(frames > 0)
  end)
  it("repeated import: the same code again is 'already imported' at once, without a second check; one import at a time", function()
    local net, _, Acc = client(22, T1)
    ok((importAsync(net, Acc, VALID2)))
    local done, r1, r2
    local t = os.clock()
    Acc.importAsync(VALID2, function(a, b) done, r1, r2 = true, a, b end)
    ok(done, "finished inside the call"); eq(r1, nil); eq(r2, "duplicate")
    ok((os.clock() - t) * 1000 < 50, "no signature work for a duplicate")
    -- while one runs, a second is refused (busy), and the first still finishes
    local finished = false
    ok(Acc.importAsync(case(V2, "sig", "shards_changed"), function() finished = true end))
    local okB, whyB = Acc.importAsync(VALID2, function() end)
    eq(okB, false); eq(whyB, "busy")
    for _ = 1, 2000 do if finished then break end; net.step(1) end
    ok(finished)
  end)
  it("the Account tab says 'Checking...' while it runs and disables Import; then shows the result", function()
    local net, c, Acc = client(23, T1)
    c.env.SlashCmdList.STACKRIVALS(""); c.ns.UI:ShowSheet("account")
    local a = c.ns.UI.accountSheet.acc
    a.paste:SetText(VALID2)
    a.import:Click()
    ok(c.ns.UI.accountNote:find("^Checking the website's signature"), c.ns.UI.accountNote)
    eq(a.import:IsEnabled(), false)
    for _ = 1, 2000 do if not Acc.busy then break end; net.step(1) end
    ok(c.ns.UI.accountNote:find("VERIFIED", 1, true), c.ns.UI.accountNote)
    eq(a.import:IsEnabled(), true)
    eq(a.status.chip:GetText(), "VERIFIED")
  end)
end)

return H
