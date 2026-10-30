-- Tiny test harness for Lua 5.1 (no dependencies). Loads addon files the way WoW does:
-- each file is called with (addonName, ns).
local H = { passed = 0, failed = 0, failures = {} }

function H.load(root, files, ns)
  ns = ns or {}
  for _, f in ipairs(files) do
    local chunk, err = loadfile(root .. "/" .. f)
    if not chunk then error("load " .. f .. ": " .. tostring(err)) end
    chunk("StackRivals", ns)
  end
  return ns
end

local current = "?"
function H.describe(name, fn) current = name; fn() end

-- SR_ONLY="part of a test name" runs only the matching tests (development)
local ONLY = os and os.getenv and os.getenv("SR_ONLY")
function H.it(name, fn)
  if ONLY and not name:find(ONLY, 1, true) then return end
  local ok, err = pcall(fn)
  if ok then
    H.passed = H.passed + 1
  else
    H.failed = H.failed + 1
    H.failures[#H.failures + 1] = current .. " > " .. name .. "\n    " .. tostring(err)
  end
end

local function show(v)
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

function H.eq(a, b, msg)
  if a ~= b then error((msg and (msg .. ": ") or "") .. "expected " .. show(b) .. ", got " .. show(a), 2) end
end
function H.ok(v, msg) if not v then error(msg or "expected truthy", 2) end end

function H.report(label)
  print(string.format("%s: %d passed, %d failed", label, H.passed, H.failed))
  for _, f in ipairs(H.failures) do print("  FAIL " .. f) end
  return H.failed == 0
end

return H
