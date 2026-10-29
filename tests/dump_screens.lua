-- Writes a layout dump of every screen for tools/render_preview.py.
-- Usage (repo root): lua5.1 tests/dump_screens.lua <outdir>
local outdir = assert(arg[1], "usage: dump_screens.lua <outdir>")
local root, testdir = "StackRivals", "tests"
local L = dofile(testdir .. "/layout.lua")
local S = assert(loadfile(testdir .. "/screens.lua"))(root, testdir)
-- version from the TOC (the mock reads it) + the exact source it was drawn from
local function git(cmd) local p = io.popen("git " .. cmd .. " 2>/dev/null"); local s = p and p:read("*l") or ""; if p then p:close() end; return s or "" end
local branch, commit = git("rev-parse --abbrev-ref HEAD"), git("rev-parse --short HEAD")
local dirty = git("status --porcelain -- StackRivals") ~= "" and "+local changes" or ""
BUILD = (commit ~= "") and string.format("  (%s @ %s%s)", branch, commit, dirty ~= "" and (" " .. dirty) or "") or ""
for _, sc in ipairs(S.list) do
  local M, ns, root_ = sc[3]()
  local F = root_ or StackRivalsFrame
  -- the hard-drop rim is an 0.18 s flash: never part of a still picture
  if ns.UI and ns.UI.rim then ns.UI.rim:SetAlpha(0) end
  local R, items = L.collect(M, F)
  L.dump(outdir .. "/" .. sc[1] .. ".txt", F, R, items, "StackRivals " .. (ns.VERSION or "?") .. BUILD .. "  -  " .. sc[2])
  print("dumped " .. sc[1])
end
