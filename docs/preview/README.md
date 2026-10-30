# Simulated previews — NOT screenshots from a WoW client

Every image is drawn from the addon's real layout code running in a WoW API mock
(`tests/screens.lua` → `tests/layout.lua` → `tools/render_preview.py`). Each banner names the
addon version (from the TOC), the branch and the commit it was drawn from.

What is real: positions and sizes of every element, colours (including WoW's inline colour codes,
e.g. the red RIVALS in the wordmark; previews before 2026-10-30 drew those in the text's base
colour), the bundled Chakra Petch font and the addon's own textures (mark, icon). What is approximate: WoW's own body font (drawn with DejaVu),
Blizzard textures, and animations (each shows its visible moment). The window is drawn at its base
size; in WoW it is scaled to ~58% of the screen height (never below 1:1).

Final visual decisions wait for real in-client screenshots.

Regenerate (after committing, so the banner names the commit):
`lua5.1 tests/dump_screens.lua docs/preview && python3 tools/render_preview.py docs/preview StackRivals/Media && rm docs/preview/*.txt`
