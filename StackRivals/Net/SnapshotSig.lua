--[[
  StackRivals - signed profile codes from stackrivals.io: SRP1-SIG v1 and SRP2-SIG v1 (verify only).

  The website's spec: docs/WOW_ADDON_BRIDGE.md section 3 (SRP1-SIG v1) and docs/WOW_SRP2.md (SRP2-SIG v1) in
  its repo; shared vectors: docs/vectors/srp1_sig_v1.json and docs/vectors/srp2_v1.json (copied unchanged here).

    sig = <kid: 2 x [a-z0-9]> <base64url, no padding, of the 64-byte Ed25519 signature: 86 characters>   (88)
    SRP1 signed message (UTF-8): "SRP1-SIG-v1\n" + fields 0-18 joined by "."
    SRP2 signed message (UTF-8): "SRP2-SIG-v1\n" + fields 0-23 joined by "."
    (a different domain per format: a signature can't be moved from one to the other)

  Result, exactly as the website's reference verifySnapshot / verifySrp2:
    { state = "verified", kid }                     the signature checks out with that kid's public key
    { state = "unverified", reason = "unsigned" }   sig "-": LINKED - UNVERIFIED, nothing locked applied
    { state = "unverified", reason = "unknown_kid"} a key this addon doesn't know (newer, or retired)
    { state = "invalid", reason = "format" }        the code doesn't parse, or the sig isn't kid + 86 characters
    { state = "invalid", reason = "signature" }     the code was changed after signing: refuse it

  KEYS holds PUBLIC keys only (kid -> 64 hex). The production key doesn't exist yet: the owner of stackrivals.io
  creates it and publishes its public half; it is added here in an addon update. The RFC 8032 test key (kid t1)
  is known to everyone and is used by the tests only: it must never be shipped (tests/test_ed25519.lua checks).
]]
local _, ns = ...
ns = ns or {}

local Sig = {}
ns.SnapshotSig = Sig

Sig.KEYS = {} -- filled by Net/SnapshotKeys.lua (public keys only; tools/add_public_key.py writes that file)
Sig.DOMAIN = { SRP1 = "SRP1-SIG-v1\n", SRP2 = "SRP2-SIG-v1\n" }
Sig.SIGNED_FIELDS = { SRP1 = 19, SRP2 = 24 } -- fields 0..18 / 0..23
Sig.FIELDS = { SRP1 = 21, SRP2 = 26 }

local function split(code)
  local f = {}
  for part in (code .. "."):gmatch("([^.]*)%.") do f[#f + 1] = part end
  return f
end

--- The exact bytes the website signed for this code (a string), or nil.
function Sig.signedMessage(code)
  if type(code) ~= "string" then return nil end
  code = code:gsub("[ \t\r\n\f\v]", "")
  local f = split(code)
  local kind = f[1]
  if not Sig.DOMAIN[kind] or #f ~= Sig.FIELDS[kind] then return nil end
  return Sig.DOMAIN[kind] .. table.concat(f, ".", 1, Sig.SIGNED_FIELDS[kind]), kind
end

--- Check a profile code's signature. keys: optional kid -> hex table (default Sig.KEYS).
--- step (optional): passed to Ed25519.verify (e.g. coroutine.yield, to spread the work over frames).
function Sig.check(code, keys, step)
  keys = keys or Sig.KEYS
  local A = ns.AccountCodes
  local kind = type(code) == "string" and code:gsub("[ \t\r\n\f\v]", ""):match("^(SRP%d+)%.") or nil
  local p
  if kind == "SRP1" then p = A.parseProfile(code) elseif kind == "SRP2" then p = A.parseProfile2(code) end
  if not p then return { state = "invalid", reason = "format" } end
  if p.sig == nil then return { state = "unverified", reason = "unsigned" } end
  local kid, body = p.sig:sub(1, 2), p.sig:sub(3)
  if not kid:match("^[a-z0-9][a-z0-9]$") or #body ~= 86 or body:find("[^A-Za-z0-9_%-]") then
    return { state = "invalid", reason = "format" }
  end
  local hex = keys[kid]
  if not hex then return { state = "unverified", reason = "unknown_kid" } end
  local Ed = ns.Ed25519
  local pub, pn = Ed.hexBytes(hex)
  local sig, sn = Ed.unb64url(body)
  local msg = Sig.signedMessage(code)
  if not (pub and pn == 32 and sig and sn == 64 and msg) then return { state = "invalid", reason = "signature" } end
  if Ed.verify(pub, sig, msg, step) then return { state = "verified", kid = kid } end
  return { state = "invalid", reason = "signature" }
end

return Sig
