-- Account > Collection: the website's Shards, events and cosmetics from an SRP2 code (display only), and the
-- cosmetics catalog (Core/CosmeticsCatalog.lua generated from docs/vectors/cosmetics_catalog_v1.json).
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local J = dofile(testdir .. "/jsonread.lua")
local NS = assert(loadfile(testdir .. "/netsim.lua"))(root, testdir)
local it, eq, ok, describe = H.it, H.eq, H.ok, H.describe

local T0 = 1793000000
--- Alice linked with an SRP2 code built from `o` (the website side, simulated with the Lua encoder).
local function linked2(seed, o, now)
  local net = NS.new({ seed = seed })
  local c = net.add({ name = "Alice", saved = { seenHelp = true } })
  c.M.serverTime = T0
  local A = c.ns.AccountCodes
  local r = A.parseLinkRequest(assert(c.ns.Account.startLink(A.makeWebCode("C0XXECT"))))
  c.M.serverTime = T0 + 300
  local p = { linkId = r.linkId, player = r.player, accountId = "6f1c2b9e-0d4a-4c1e-9a77-2f3b5c8d9e01", name = "Alice Stack",
    issued = T0 + 200, expires = T0 + 8 * 86400, level = 12, xp = 1240, xpNext = 2000, history = {},
    shards = 1250, asOf = T0 + 200, equipped = {}, owned = {}, events = {} }
  for k, v in pairs(o or {}) do p[k] = v end
  assert(c.ns.Account.import(A.profile2(p)))
  if now then c.M.serverTime = now end
  c.env.SlashCmdList.STACKRIVALS("")
  c.ns.UI:ShowSheet("account")
  c.ns.UI.accountSheet.tabs.collection:Click()
  return c, c.ns.UI.accountSheet.coll
end

describe("cosmetics catalog", function()
  it("is the website's file, generated unchanged (python3 tools/gen_cosmetics.py)", function()
    local ns = H.load(root, { "Core/CosmeticsCatalog.lua" })
    local Cat = ns.CosmeticsCatalog
    local V = J.read(root .. "/../docs/vectors/cosmetics_catalog_v1.json")
    eq(#Cat.items, #V.items)
    eq(#Cat.items, 32)
    for i, w in ipairs(V.items) do
      local a = Cat.items[i]
      eq(a.id, w.id); eq(a.name, w.name); eq(a.slot, w.slot); eq(a.rarity, w.rarity); eq(a.acquisition, w.acquisition)
      eq(a.price, w.priceShards ~= J.NULL and w.priceShards or nil, w.id)
    end
    eq(Cat.SHOP_OPEN, false, "the website's Shop isn't open: nothing is sold, purchasable items show as Upcoming")
  end)
  it("has none of the names that don't exist on the website", function()
    local ns = H.load(root, { "Core/CosmeticsCatalog.lua" })
    for _, it2 in ipairs(ns.CosmeticsCatalog.items) do
      for _, gone in ipairs({ "Cyber Crown", "Quantum Halo", "Eclipse Sovereign" }) do ok(it2.name ~= gone, gone) end
    end
  end)
end)

describe("Collection tab (simulated client)", function()
  it("shows the website's balance with 'as of', and says nothing is bought, spent or claimed in WoW", function()
    local _, y = linked2(1, nil, T0 + 200 + 1800)
    eq(y.shards:GetText(), "1,250")
    ok(y.asOf:GetText():find("^as of ") and y.asOf:GetText():find("30 min ago", 1, true), y.asOf:GetText())
    ok(y.shardsNote:GetText():find("Nothing is bought, spent or claimed in WoW", 1, true), y.shardsNote:GetText())
    ok(y.shardsNote:GetText():find("Shop Upcoming", 1, true))
  end)
  it("'-' in the code (Shards off on the website) shows NOT AVAILABLE, never 0", function()
    local _, y = linked2(2, { shards = false })
    eq(y.shards:GetText(), "NOT AVAILABLE")
  end)
  it("events: upcoming / live with the code's time, Overdrive x100 values, ended by the PC's clock; claims only on the website", function()
    local c, y = linked2(3, { events = {
      { kind = "storm", state = "up", start = T0 + 3800, ["end"] = T0 + 4700, value = 25 },
      { kind = "overdrive", state = "live", start = T0 - 600, ["end"] = T0 + 3000, value = 200 },
      { kind = "overdrive", state = "live", start = T0 - 600, ["end"] = T0 + 3000, value = 150 },
    } }, T0 + 1000)
    ok(y.events[1]:GetText():find("^SHARD STORM  upcoming ") and y.events[1]:GetText():find("25 Shards per claim", 1, true), y.events[1]:GetText())
    ok(y.events[2]:GetText():find("^XP OVERDRIVE 2x  live until ") and y.events[2]:GetText():find(", as of ", 1, true), y.events[2]:GetText())
    ok(y.events[3]:GetText():find("^XP OVERDRIVE 1.5x"), y.events[3]:GetText())
    ok(y.events[4]:GetText():find("WoW matches earn nothing", 1, true), y.events[4]:GetText())
    eq(c.ns.UI.overdriveText(101), "1.01x"); eq(c.ns.UI.overdriveText(300), "3x"); eq(c.ns.UI.overdriveText(250), "2.5x")
    c.M.serverTime = T0 + 5000
    c.ns.UI:RefreshAccount()
    ok(y.events[1]:GetText():find("ended", 1, true), y.events[1]:GetText())
  end)
  it("cosmetics: equipped first, then owned, then locked with how to get them; purchasable = Shop Upcoming, never a buy button", function()
    local c, y = linked2(4, {
      equipped = { skin = "skin_solar_inferno", frame = "frame_electric_blue" },
      owned = { "frame_electric_blue", "skin_circuit", "skin_solar_inferno" } })
    eq(y.rows[1].status:GetText(), "EQUIPPED"); eq(y.rows[2].status:GetText(), "EQUIPPED")
    eq(y.rows[1].name:GetText(), "Solar Inferno"); eq(y.rows[2].name:GetText(), "Electric Blue")
    eq(y.rows[3].status:GetText(), "OWNED"); eq(y.rows[3].name:GetText(), "Circuit")
    ok(y.equipped:GetText():find("Owned 3 of 32", 1, true), y.equipped:GetText())
    eq(y.page:GetText(), "1 / 7")
    local sawShop, sawLevel = false, false
    for _ = 1, 7 do
      for _, r in ipairs(y.rows) do
        local t = r.status:GetText() or ""
        if t:find("Shop Upcoming", 1, true) then sawShop = true end
        if t:find("Level reward", 1, true) then sawLevel = true end
      end
      y.next:Click()
    end
    ok(sawShop and sawLevel, "locked items say how they're obtained")
    -- no button on this tab buys, claims or applies anything
    for _, f in ipairs(c.M.frames) do
      local cur, inside = f, false
      while cur do if cur == y then inside = true break end; cur = cur._parent end
      if inside and f.fs and f.fs.GetText then
        local label = (f.fs:GetText() or ""):lower()
        ok(not (label:find("buy") or label:find("claim") or label:find("apply") or label:find("equip")), "button: " .. label)
      end
    end
  end)
  it("nothing is applied from an unverified code; the one gate says no", function()
    local c, y = linked2(5, { equipped = { skin = "skin_solar_inferno" }, owned = { "skin_solar_inferno" } })
    eq(c.ns.Account.profileView().verified, false)
    eq(c.ns.Account.canApplyCosmetic("skin_solar_inferno"), false)
    ok(y.trust:GetText():find("^UNVERIFIED"), y.trust:GetText())
    -- with a verified view (a signature checked by Net/SnapshotSig.lua) only owned / equipped items pass
    local real = c.ns.Account.profileView
    c.ns.Account.profileView = function() local v, st = real(); v.verified = true; return v, st end
    eq(c.ns.Account.canApplyCosmetic("skin_solar_inferno"), true)
    eq(c.ns.Account.canApplyCosmetic("skin_circuit"), false, "not owned")
    c.ns.Account.profileView = real
  end)
  it("an SRP1 profile says how to get the SRP2 code; no profile says how to link", function()
    local net = NS.new({ seed = 6 })
    local c = net.add({ name = "Alice", saved = { seenHelp = true } })
    c.env.SlashCmdList.STACKRIVALS(""); c.ns.UI:ShowSheet("account")
    c.ns.UI.accountSheet.tabs.collection:Click()
    local y = c.ns.UI.accountSheet.coll
    ok(y.empty:GetText():find("Link your stackrivals.io account", 1, true), y.empty:GetText())
    local A = c.ns.AccountCodes
    c.M.serverTime = T0
    local r = A.parseLinkRequest(assert(c.ns.Account.startLink(A.makeWebCode("C0XXECT"))))
    c.M.serverTime = T0 + 300
    assert(c.ns.Account.import(A.profile({ linkId = r.linkId, player = r.player, accountId = "acc_7f3k2", name = "Alice",
      issued = T0 + 200, expires = T0 + 86400, history = {} })))
    c.ns.UI:RefreshAccount()
    ok(y.empty:GetText():find("SRP2", 1, true) and y.empty:GetText():find(c.ns.Account.WEB.export, 1, true), y.empty:GetText())
  end)
end)

return H
