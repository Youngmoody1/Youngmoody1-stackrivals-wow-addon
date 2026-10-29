-- Writes a layout dump of every screen for tools/render_preview.py.
-- Usage (repo root): lua5.1 tests/dump_screens.lua <outdir>
local outdir = assert(arg[1], "usage: dump_screens.lua <outdir>")
local root, testdir = "StackRivals", "tests"
local L = dofile(testdir .. "/layout.lua")
local S = assert(loadfile(testdir .. "/screens.lua"))(root, testdir)
for _, sc in ipairs(S.list) do
  local M, ns, root_ = sc[3]()
  local F = root_ or StackRivalsFrame
  local R, items = L.collect(M, F)
  L.dump(outdir .. "/" .. sc[1] .. ".txt", F, R, items, "StackRivals " .. (ns.VERSION or "") .. "  -  " .. sc[2])
  print("dumped " .. sc[1])
end
