-- Writes a layout dump of every screen for tools/render_preview.py.
-- Usage (repo root): lua5.1 tests/dump_screens.lua <outdir>
local outdir = assert(arg[1], "usage: dump_screens.lua <outdir>")
local root, testdir = "StackRivals", "tests"
local L = dofile(testdir .. "/layout.lua")
local S = assert(loadfile(testdir .. "/screens.lua"))(root, testdir)
for _, sc in ipairs(S.list) do
  local M, ns = sc[3]()
  local R, items = L.collect(M, StackRivalsFrame)
  L.dump(outdir .. "/" .. sc[1] .. ".txt", StackRivalsFrame, R, items, "StackRivals " .. (ns.VERSION or "") .. "  -  " .. sc[2])
  print("dumped " .. sc[1])
end
