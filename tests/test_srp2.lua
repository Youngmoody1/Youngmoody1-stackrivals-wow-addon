-- SRP2 (profile snapshot v2, defined by stackrivals.io: docs/WOW_SRP2.md on the website). The shared vectors
-- docs/vectors/srp2_v1.json are made by the website's TypeScript reference (scripts/qa/make-srp2-vectors.ts); this
-- Lua parser must decode / refuse every one of them exactly, and its encoder must give the same codes back.
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe
local ns = H.load(root, { "Engine/Prng.lua", "Engine/Pieces.lua", "Engine/Engine.lua", "Net/Protocol.lua", "Net/Codes.lua", "Net/AccountCodes.lua" })
local A = ns.AccountCodes

-- a small JSON reader (tests only): objects, arrays, strings (with \n \" \\ \uXXXX ASCII), numbers, true/false/null
local NULL = {}
local function decode(s)
  local i = 1
  local function ws() i = s:find("[^ \t\r\n]", i) or #s + 1 end
  local val
  local function str()
    local out = {}
    i = i + 1
    while true do
      local ch = s:sub(i, i)
      if ch == '"' then i = i + 1; return table.concat(out) end
      if ch == "\\" then
        local e = s:sub(i + 1, i + 1)
        if e == "u" then out[#out + 1] = string.char(tonumber(s:sub(i + 2, i + 5), 16)); i = i + 6
        else out[#out + 1] = ({ n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" })[e] or e; i = i + 2 end
      else out[#out + 1] = ch; i = i + 1 end
    end
  end
  function val()
    ws()
    local ch = s:sub(i, i)
    if ch == "{" then
      local o = {}; i = i + 1; ws()
      if s:sub(i, i) == "}" then i = i + 1; return o end
      while true do
        ws(); local k = str(); ws(); i = i + 1 -- ':'
        o[k] = val(); ws()
        local c = s:sub(i, i); i = i + 1
        if c == "}" then return o end
      end
    elseif ch == "[" then
      local a = {}; i = i + 1; ws()
      if s:sub(i, i) == "]" then i = i + 1; return a end
      while true do
        a[#a + 1] = val(); ws()
        local c = s:sub(i, i); i = i + 1
        if c == "]" then return a end
      end
    elseif ch == '"' then return str()
    elseif s:sub(i, i + 3) == "true" then i = i + 4; return true
    elseif s:sub(i, i + 4) == "false" then i = i + 5; return false
    elseif s:sub(i, i + 3) == "null" then i = i + 4; return NULL
    else
      local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
      i = i + #num
      return tonumber(num)
    end
  end
  return val()
end

local f = assert(io.open(root .. "/../docs/vectors/srp2_v1.json", "rb"))
local V = decode(f:read("*a"))
f:close()

-- compare a decoded Lua snapshot with the website's expectation (null = nil here)
local function same(lua, js, path)
  if js == NULL then eq(lua, nil, path); return end
  if type(js) == "table" then
    ok(type(lua) == "table", path .. ": expected a table")
    local n = 0
    for k, v in pairs(js) do n = n + 1; same(lua[k], v, path .. "." .. tostring(k)) end
    if js[1] ~= nil or next(js) == nil then eq(#lua, #js, path .. " length") end
    return
  end
  eq(lua, js, path)
end

describe("SRP2 shared vectors (website reference)", function()
  it("the file has the parse and signature cases", function()
    ok(#V.parse >= 15, "parse cases"); ok(#V.sig >= 9, "sig cases")
  end)
  for _, c in ipairs(V.parse) do
    it("parse: " .. c.name .. " (" .. c.why .. ")", function()
      local p, why = A.parseProfile2(c.code)
      if c.expect.ok then
        ok(p, "refused: " .. tostring(why))
        local snapshot = c.expect.snapshot
        for k, v in pairs(snapshot) do same(p[k], v, k) end
        -- round trip: the Lua encoder gives the website's code back byte for byte
        eq(A.profile2(p), c.code, "re-encoded")
      else
        eq(p, nil); eq(why, c.expect.error)
      end
    end)
  end
  it("every signature vector still parses (the format is the same; this version does not check signatures)", function()
    for _, c in ipairs(V.sig) do
      local p = A.parseProfile2(c.code)
      ok(p, c.name)
      if c.name == "unsigned" then eq(p.sig, nil) else ok(p.sig and #p.sig == 88, c.name .. " sig") end
    end
  end)
end)

describe("SRP2 next to SRP1", function()
  it("SRP1's parser refuses SRP2 as another version and SRP2's parser refuses SRP1 the same way", function()
    local full = V.parse[1].code
    local p, why = A.parseProfile(full); eq(p, nil); eq(why, "version")
    p, why = A.parseProfile2("SRP1" .. full:sub(5)); eq(p, nil); eq(why, "version")
    p, why = A.parseProfile2("SRP3" .. full:sub(5)); eq(p, nil); eq(why, "version")
  end)
  it("owned ids are compared in byte order, not the C library's locale order ('_' sorts before letters)", function()
    ok(A.byteLess("skin_a", "skina")); ok(A.byteLess("a", "ab")); ok(not A.byteLess("b", "a"))
  end)
end)

return H
