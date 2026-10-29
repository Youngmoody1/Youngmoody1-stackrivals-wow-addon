-- Runs every test file. Usage (from repo root):  lua5.1 tests/run.lua
local root, testdir = "StackRivals", "tests"
local allOk = true
for _, file in ipairs({ "test_engine.lua", "test_session_db.lua", "test_addon_load.lua", "test_layout.lua" }) do
  local chunk = assert(loadfile(testdir .. "/" .. file))
  local H = chunk(root, testdir)
  allOk = H.report(file) and allOk
end
print(allOk and "ALL TESTS PASSED" or "SOME TESTS FAILED")
os.exit(allOk and 0 or 1)
