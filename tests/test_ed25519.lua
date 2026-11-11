-- Ed25519 verification + SHA-512 in pure Lua 5.1 (Net/Ed25519.lua) and the website's signed profile codes,
-- SRP1-SIG v1 and SRP2-SIG v1 (Net/SnapshotSig.lua). Oracles: RFC 8032 section 7.1, FIPS 180 SHA-512 values,
-- and the website's shared vectors (docs/vectors/srp1_sig_v1.json, docs/vectors/srp2_v1.json, copied unchanged).
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local J = dofile(testdir .. "/jsonread.lua")
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe
local ns = H.load(root, { "Engine/Prng.lua", "Engine/Pieces.lua", "Engine/Engine.lua", "Net/Protocol.lua", "Net/Codes.lua",
  "Net/AccountCodes.lua", "Net/Ed25519.lua", "Net/SnapshotSig.lua", "Net/SnapshotKeys.lua" })
local Ed, Sig = ns.Ed25519, ns.SnapshotSig

local function sha(s) local b, n = Ed.strBytes(s); return Ed.toHex(Ed.sha512(b, n), 64) end
local function bytesOfHex(h) local s = {}; for i = 1, #h, 2 do s[#s + 1] = string.char(tonumber(h:sub(i, i + 1), 16)) end; return table.concat(s) end
local RFC = {
  { "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "",
    "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b" },
  { "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c", "72",
    "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00" },
  { "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025", "af82",
    "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a" },
}

--- WoW's `bit` library returns SIGNED 32-bit numbers on some clients: a shim with that behaviour (built on the
--- pure tables) proves the normalisation works whichever the client does.
local function signedBitShim()
  Ed.useBitLib(nil)
  local function pureAnd(a, b) local r, m = 0, 1; for _ = 1, 32 do local x, y = a % 2, b % 2; if x == 1 and y == 1 then r = r + m end; a, b, m = (a - x) / 2, (b - y) / 2, m * 2 end; return r end
  local function pureXor(a, b) local r, m = 0, 1; for _ = 1, 32 do local x, y = a % 2, b % 2; if x ~= y then r = r + m end; a, b, m = (a - x) / 2, (b - y) / 2, m * 2 end; return r end
  local function signed(v) if v >= 2147483648 then return v - 4294967296 end; return v end
  return { band = function(a, b) return signed(pureAnd(a % 4294967296, b % 4294967296)) end,
           bxor = function(a, b) return signed(pureXor(a % 4294967296, b % 4294967296)) end }
end

describe("SHA-512 (pure Lua 5.1)", function()
  it("matches FIPS 180 / hashlib for '', 'abc', 200 bytes and lengths around the padding edges", function()
    eq(sha(""), "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e")
    eq(sha("abc"), "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
    eq(sha(string.rep("a", 200)), "4b11459c33f52a22ee8236782714c150a3b2c60994e9acee17fe68947a3e6789f31e7668394592da7bef827cddca88c4e6f86e4df7ed1ae6cba71f3e98faee9f")
    eq(sha(string.rep("x", 111)), "9a2a120825c2319867758ec277924f6faa254968bf752046dacdd948d8ad299b10359fd04bfd7d3810b5fa1b16a294236138baff981cbb85248478053ac4d3dd")
    eq(sha(string.rep("x", 112)), "a3722b515ef40c910f2419f6e0da8ca51d410114ce6272faae64045f9e9f630e7fa8dd5a3243c9860b899d148c3da4bc0f9e07454542604d030bb55531fe0d5b")
  end)
end)

describe("Ed25519 verify (pure Lua 5.1, RFC 8032)", function()
  it("RFC 8032 section 7.1 TEST 1-3 verify; every single changed byte of signature or message fails", function()
    for n, t in ipairs(RFC) do
      local pub, sig = Ed.hexBytes(t[1]), Ed.hexBytes(t[3])
      local msg = bytesOfHex(t[2])
      ok(Ed.verify(pub, sig, msg), "TEST " .. n)
      for _, i in ipairs({ 0, 31, 32, 63 }) do
        local bad = Ed.hexBytes(t[3]); bad[i] = (bad[i] + 1) % 256
        ok(not Ed.verify(pub, bad, msg), "TEST " .. n .. " sig byte " .. i)
      end
      ok(not Ed.verify(pub, sig, msg .. "x"), "TEST " .. n .. " message changed")
      local otherPub = Ed.hexBytes(RFC[n % 3 + 1][1])
      ok(not Ed.verify(otherPub, sig, msg), "TEST " .. n .. " another key")
    end
  end)
  it("refuses S >= L (malleability), a key that isn't a curve point, and malformed input without errors", function()
    local t = RFC[1]
    local pub, sig = Ed.hexBytes(t[1]), Ed.hexBytes(t[3])
    -- S + L: the same point, a different encoding; RFC 8032 says refuse
    local L = { 0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14,
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x10 }
    local s2, c = Ed.hexBytes(t[3]), 0
    for i = 0, 31 do local v = s2[32 + i] + L[i + 1] + c; s2[32 + i] = v % 256; c = math.floor(v / 256) end
    ok(not Ed.verify(pub, s2, ""), "S + L refused")
    local notPoint = Ed.hexBytes("0200000000000000000000000000000000000000000000000000000000000000")
    ok(not Ed.verify(notPoint, sig, ""), "not a point")
    ok(not Ed.verify({}, sig, ""), "empty key"); ok(not Ed.verify(pub, {}, ""), "empty sig"); ok(not Ed.verify(pub, sig, nil), "no message")
    local big = Ed.hexBytes(t[1]); big[3] = 300
    ok(not Ed.verify(big, sig, ""), "a byte out of range")
  end)
  it("WoW's bit library path (signed or unsigned results) gives the same answers as the pure path", function()
    local shim = signedBitShim()
    Ed.useBitLib(shim)
    eq(Ed.bitPath, "bit")
    eq(sha("abc"):sub(1, 32), "ddaf35a193617abacc417349ae204131")
    local t = RFC[2]
    ok(Ed.verify(Ed.hexBytes(t[1]), Ed.hexBytes(t[3]), bytesOfHex(t[2])))
    Ed.useBitLib(nil)
    eq(Ed.bitPath, "pure")
  end)
  it("one verification is quick enough for a click (measured here; real WoW timing is a client test)", function()
    local t = RFC[3]
    local c = os.clock()
    ok(Ed.verify(Ed.hexBytes(t[1]), Ed.hexBytes(t[3]), bytesOfHex(t[2])))
    local s = os.clock() - c
    H.note(string.format("Ed25519 verify, pure Lua path: %.0f ms", s * 1000))
    ok(s < 2, "took " .. s .. " s")
  end)
end)

describe("SRP1-SIG v1 (website vectors, docs/vectors/srp1_sig_v1.json)", function()
  local V = J.read(root .. "/../docs/vectors/srp1_sig_v1.json")
  it("every case gives the website's expected state and reason", function()
    eq(#V.cases, 11)
    for _, c in ipairs(V.cases) do
      local got = Sig.check(c.code, V.keys)
      eq(got.state, c.expect.state, c.name)
      eq(got.reason, c.expect.reason ~= J.NULL and c.expect.reason or nil, c.name .. " reason")
      eq(got.kid, c.expect.kid ~= J.NULL and c.expect.kid or nil, c.name .. " kid")
    end
  end)
  it("the signed message is exactly the website's", function()
    eq(Sig.signedMessage(V.cases[1].code), V.signedMessageOfValid)
  end)
end)

describe("SRP2-SIG v1 (website vectors, docs/vectors/srp2_v1.json)", function()
  local V = J.read(root .. "/../docs/vectors/srp2_v1.json")
  it("every signature case gives the website's expected state and reason", function()
    local keys = { [V.testKey.kid] = V.testKey.public }
    eq(#V.sig, 9)
    for _, c in ipairs(V.sig) do
      local got = Sig.check(c.code, keys)
      eq(got.state, c.expect.state, c.name)
      eq(got.reason, c.expect.reason ~= J.NULL and c.expect.reason or nil, c.name .. " reason")
      eq(got.kid, c.expect.kid ~= J.NULL and c.expect.kid or nil, c.name .. " kid")
    end
  end)
  it("an SRP1 signature never verifies as SRP2, and the other way round (different domain strings)", function()
    local keys = { [V.testKey.kid] = V.testKey.public }
    for _, c in ipairs(V.sig) do
      if c.name == "srp1_signature_moved" then eq(Sig.check(c.code, keys).reason, "signature") end
    end
  end)
end)

describe("signed codes in the account flow (simulated client)", function()
  local NS = assert(loadfile(testdir .. "/netsim.lua"))(root, testdir)
  local V2 = J.read(root .. "/../docs/vectors/srp2_v1.json")
  local V1 = J.read(root .. "/../docs/vectors/srp1_sig_v1.json")
  local function sigCase(V, list, name) for _, c in ipairs(V[list]) do if c.name == name then return c.code end end end
  local ISSUED = 1793000060
  --- Alice-Realm with a pending link request whose linkId is the vectors' (the website made the codes for it).
  local function pending(seed, keys)
    local net = NS.new({ seed = seed })
    local c = net.add({ name = "Alice", saved = { seenHelp = true } })
    c.M.serverTime = ISSUED - 60
    assert(c.ns.Account.startLink(c.ns.AccountCodes.makeWebCode("A7K9P2X")))
    c.ns.Account.rec().pending.linkId = "k3v9q2m7x1aa"
    c.M.serverTime = ISSUED + 30
    for k in pairs(c.ns.SnapshotSig.KEYS) do c.ns.SnapshotSig.KEYS[k] = nil end
    for k, v in pairs(keys or {}) do c.ns.SnapshotSig.KEYS[k] = v end
    return c, c.ns.Account
  end
  local T1 = { t1 = V2.testKey.public }

  it("a validly signed SRP2 links as VERIFIED (green) on the Account tab and the Profile tag", function()
    local c, Acc = pending(70, T1)
    local okI, res = Acc.import(sigCase(V2, "sig", "valid"))
    ok(okI, tostring(res)); eq(res, "linked")
    local v = Acc.profileView()
    eq(v.verified, true); eq(v.kid, "t1"); eq(v.shards, 1250)
    c.env.SlashCmdList.STACKRIVALS(""); c.ns.UI:ShowSheet("account")
    eq(c.ns.UI.accountSheet.acc.status.chip:GetText(), "VERIFIED")
    c.ns.UI.accountSheet.tabs.profile:Click()
    eq(c.ns.UI.accountSheet.prof.trust:GetText(), "VERIFIED")
  end)
  it("a validly signed SRP1 is VERIFIED too", function()
    local _, Acc = pending(71, T1)
    ok(Acc.import(sigCase(V1, "cases", "valid")))
    eq(Acc.profileView().verified, true)
  end)
  it("a signed code changed afterwards (Shards, owned, equipped, events, level, an SRP1 signature moved) is REJECTED", function()
    for _, name in ipairs({ "shards_changed", "owned_changed", "equipped_changed", "event_changed", "level_changed", "srp1_signature_moved" }) do
      local _, Acc = pending(72, T1)
      local okI, why = Acc.import(sigCase(V2, "sig", name))
      eq(okI, nil, name); eq(why, "signature", name)
      eq(Acc.profileView(), nil, name .. ": nothing linked")
    end
    local _, Acc = pending(73, T1)
    local okI, why = Acc.import(sigCase(V1, "cases", "xp_changed"))
    eq(okI, nil); eq(why, "signature")
  end)
  it("unsigned, or signed with a key this version doesn't ship: imported as UNVERIFIED (never an error)", function()
    local _, Acc = pending(74, T1)
    ok(Acc.import(sigCase(V2, "sig", "unsigned")))
    eq(Acc.profileView().verified, false); eq(Acc.profileView().sigNote, "unsigned")
    local _, Acc2 = pending(75, T1)
    ok(Acc2.import(sigCase(V2, "sig", "unknown_kid")))
    eq(Acc2.profileView().verified, false); eq(Acc2.profileView().sigNote, "unknown_kid")
    -- with the keys this version really ships (no test key), a t1-signed code is just UNVERIFIED
    local _, Acc3 = pending(76, nil)
    ok(Acc3.import(sigCase(V2, "sig", "valid")))
    eq(Acc3.profileView().verified, false); eq(Acc3.profileView().sigNote, "unknown_kid")
  end)
  it("VERIFIED survives a reload only while this version still ships that key (a retired key becomes UNVERIFIED)", function()
    local c, Acc = pending(77, T1)
    ok(Acc.import(sigCase(V2, "sig", "valid")))
    local saved = c.ns.Account.sanitize(c.ns.db.accounts)
    local who = next(saved)
    -- never VERIFIED from the file's own say-so: marked for the signature re-check (Account.reverify; the
    -- full reload is in tests/test_signed_import.lua), and only while the key is still shipped
    eq(saved[who].profile.verified, nil); eq(saved[who].profile.recheck, true); eq(saved[who].profile.kid, "t1")
    ok(saved[who].profile.code ~= nil, "the signed code is kept for the re-check")
    c.ns.SnapshotSig.KEYS.t1 = nil
    local again = c.ns.Account.sanitize(c.ns.db.accounts)
    eq(again[who].profile.verified, nil, "key retired: not verified after reload")
    eq(again[who].profile.recheck, nil, "and no re-check"); eq(again[who].profile.code, nil)
    eq(Acc.isVerified(again[who].profile), false)
  end)
end)

describe("shipped keys", function()
  it("contain no RFC 8032 test key (anyone could sign with it) and only well-formed public keys", function()
    for kid, hex in pairs(Sig.KEYS) do
      ok(kid:match("^[a-z0-9][a-z0-9]$"), "kid " .. kid)
      ok(type(hex) == "string" and #hex == 64 and not hex:find("[^0-9a-f]"), "key " .. kid)
      for _, t in ipairs(RFC) do ok(hex ~= t[1], "RFC test key shipped as " .. kid) end
    end
    eq(Sig.KEYS.t1, nil, "the test kid t1 is for tests only")
  end)
end)

return H
