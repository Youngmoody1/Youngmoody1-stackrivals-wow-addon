-- SR1 cross-platform codes (Net/Codes.lua) and the shared vectors in docs/vectors/sr1.json.
-- The TypeScript side is checked against the same file by tools/sr1/check_vectors.ts (needs bun +
-- a web checkout; run by tools/parity/check_web.sh).
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe
local ns = H.load(root, { "Engine/Prng.lua", "Engine/Pieces.lua", "Engine/Engine.lua", "Engine/Input.lua", "Engine/Verify.lua", "Net/Protocol.lua", "Net/Codes.lua" })
local C, E = ns.Codes, ns.Engine
local VEC = assert(loadfile(testdir .. "/sr1_vectors.lua"))(root, testdir)

describe("SR1 codes", function()
  it("docs/vectors/sr1.json is current (regenerate: lua5.1 tests/sr1_vectors.lua > docs/vectors/sr1.json)", function()
    local f = assert(io.open(root .. "/../docs/vectors/sr1.json", "rb"))
    local onDisk = f:read("*a"); f:close()
    ok(onDisk == VEC.render(), "vectors file is stale")
  end)
  it("every vector decodes and verifies to its expectation in Lua", function()
    local v = VEC.build()
    ok(#v.challenges >= 8 and #v.results >= 18)
    for _, c in ipairs(v.challenges) do
      local d, err = C.parseChallenge(c.code)
      if c.expect.ok then ok(d and d.seed == c.expect.seed, c.name) else eq(err, c.expect.error, c.name) end
    end
    local valid, rejected, decodeErr = 0, 0, 0
    for _, r in ipairs(v.results) do
      local e = r.expect
      if e.decode ~= "ok" then decodeErr = decodeErr + 1
      elseif e.verify.ok then valid = valid + 1 else rejected = rejected + 1 end
    end
    ok(valid >= 5 and rejected >= 9 and decodeErr >= 6, valid .. "/" .. rejected .. "/" .. decodeErr)
  end)
  it("round trip: a duel-length game encodes, decodes and re-encodes identically", function()
    local s = E.createGame("srchal-roundtrip1", { startLevel = 1 })
    for t = 0, 7199 do
      if t % 13 == 0 then E.applyInput(s, E.INPUT_ACTIONS[(t / 13) % 7 + 1]) end
      if s.gameOver then break end
      E.tick(s)
    end
    local code = C.result({ platform = "wow-forever", ruleset = "b120", seed = s.seed, ticks = s.tick, score = s.score,
      lines = s.lines, level = s.level, hash = E.hashState(s), player = "Zoë-Argent Dawn", log = s.inputLog })
    ok(code:match("^SR1R%.wow%-forever%.b120%.e1%.srchal%-roundtrip1%."))
    ok(#code < 4000, "fits a paste box (" .. #code .. " chars)")
    local d = assert(C.parseResult(code))
    eq(d.player, "Zoë-Argent Dawn"); eq(d.score, s.score); eq(#d.log, #s.inputLog)
    eq(C.result({ platform = d.platform, ruleset = d.ruleset, seed = d.seed, ticks = d.ticks, score = d.score, lines = d.lines,
      level = d.level, hash = d.hash, player = d.player, log = d.log }), code)
    local r = ns.Verify.verify(d.log, d.seed, d.ticks, { seed = s.seed, capTicks = 7200, engine = d.engine, elapsedMs = 200000,
      claimed = { score = d.score, lines = d.lines, level = d.level, hash = d.hash } })
    ok(r.ok, table.concat(r.reasons, ","))
  end)
  it("rejects hostile input without errors", function()
    for _, bad in ipairs({ "", "SR1R", string.rep("A", 40000), "SR1R." .. string.rep(".", 13), "SR1C.b120.e1.x.zzzzzzzz",
      "SR1R.wow-forever.b120.e1.s.0.0.0.0.00000000.41.-.0A0B.00000000", "SR1R.wow-forever.b120.e99999.s.0.0.0.0.00000000.41.-..00000000" }) do
      local okCall, r = pcall(C.parseResult, bad)
      ok(okCall and r == nil, "rejected: " .. bad:sub(1, 40))
      local okC, c = pcall(C.parseChallenge, bad)
      ok(okC and c == nil)
    end
    ok(C.utf8ok("Zoë")); ok(not C.utf8ok("\195")); ok(not C.utf8ok("\192\128"), "overlong"); ok(not C.utf8ok("\237\160\128"), "surrogate")
  end)
end)

return H
