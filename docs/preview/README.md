# Developer previews — not in-game screenshots

Generated from the addon's real layout code running in the WoW API mock
(`tests/screens.lua` → `tests/layout.lua` → `tools/render_preview.py`). Fonts, text metrics and
Blizzard-owned textures are approximations. Real screenshots come from the client test.

Regenerate: `lua5.1 tests/dump_screens.lua /tmp/prev && python3 tools/render_preview.py /tmp/prev StackRivals/Media`
