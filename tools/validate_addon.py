"""Static checks of the addon folder before packaging. Exits non-zero on any problem.

  python3 tools/validate_addon.py StackRivals

Checks: TOC fields and interface numbers, every listed file exists, every .lua is listed (no
orphans), load order (a file only uses modules loaded before it), media files referenced by the
code exist, file names are plain ASCII without spaces, no byte-code / obfuscated / binary Lua,
version matches CHANGELOG, no third-party trademark in user-facing strings.
"""
import os, re, sys

addon = sys.argv[1] if len(sys.argv) > 1 else "StackRivals"
name = os.path.basename(os.path.normpath(addon))
errors = []
def err(msg): errors.append(msg)

toc_path = os.path.join(addon, name + ".toc")
if not os.path.isfile(toc_path):
    print(f"FAIL: {toc_path} missing (TOC must be named after its folder)"); sys.exit(1)
toc = open(toc_path, encoding="utf-8").read().splitlines()
meta = {}
files = []
for line in toc:
    if line.startswith("## "):
        k, _, v = line[3:].partition(":")
        meta[k.strip()] = v.strip()
    elif line.strip() and not line.startswith("#"):
        files.append(line.strip().replace("\\", "/"))

for req in ("Interface", "Title", "Version", "SavedVariables", "Notes"):
    if req not in meta: err(f"TOC: missing ## {req}")
ifaces = [x.strip() for x in meta.get("Interface", "").split(",")]
if not ifaces or not all(re.fullmatch(r"\d{5,6}", x) for x in ifaces): err(f"TOC: bad Interface list {ifaces}")
if "16001" not in ifaces: err("TOC: Forever interface 16001 missing")
if len(set(ifaces)) != len(ifaces): err("TOC: duplicate interface numbers")
version = meta.get("Version", "")
if not re.fullmatch(r"\d+\.\d+\.\d+", version): err(f"TOC: version '{version}' is not x.y.z")

# files listed exist, every lua is listed
listed = set(files)
for f in files:
    if not os.path.isfile(os.path.join(addon, f)): err(f"TOC lists missing file {f}")
for dp, _, fs in os.walk(addon):
    for fn in fs:
        rel = os.path.relpath(os.path.join(dp, fn), addon).replace(os.sep, "/")
        if not re.fullmatch(r"[A-Za-z0-9_\-./]+", rel): err(f"unsafe file name: {rel}")
        if fn.startswith("."): err(f"hidden file in addon: {rel}")
        if fn.endswith(".lua") and rel not in listed: err(f"{rel} is not in the TOC (orphan)")
        ext = os.path.splitext(fn)[1].lower()
        license_text = ext == ".txt" and os.path.basename(rel).startswith("OFL-")  # bundled font licenses
        if ext not in (".lua", ".toc", ".tga", ".blp", ".ogg", ".mp3", ".ttf", ".xml") and not license_text:
            err(f"unexpected file type in addon: {rel}")

# source readable & not byte-code / obfuscated
provides = {}
for i, f in enumerate(files):
    p = os.path.join(addon, f)
    if not os.path.isfile(p) or not f.endswith(".lua"): continue
    raw = open(p, "rb").read()
    if raw.startswith(b"\x1bLua"): err(f"{f} is compiled byte-code")
    try: src = raw.decode("utf-8")
    except UnicodeDecodeError: err(f"{f} is not UTF-8 text"); continue
    if max((len(l) for l in src.splitlines()), default=0) > 400: err(f"{f} has a line > 400 chars (looks minified)")
    if re.search(r"\bloadstring\s*\(|\bRunScript\s*\(", src): err(f"{f} executes generated code (loadstring/RunScript)")
    for m in re.finditer(r"^ns\.(\w+)\s*=", src, re.M): provides.setdefault(m.group(1), i)
    for m in re.finditer(r"^local \w+ = \{\}\s*\nns\.(\w+)", src, re.M): provides.setdefault(m.group(1), i)

# load order: a module's file-scope `local X = ns.Y` must come after the file that defines ns.Y
for i, f in enumerate(files):
    p = os.path.join(addon, f)
    if not f.endswith(".lua") or not os.path.isfile(p): continue
    src = open(p, encoding="utf-8").read()
    for m in re.finditer(r"^local [\w, ]+=\s*(ns\.\w+(?:,\s*ns\.\w+)*)", src, re.M):
        for dep in re.findall(r"ns\.(\w+)", m.group(1)):
            j = provides.get(dep)
            if j is None: err(f"{f}: uses ns.{dep} which no file defines")
            elif j > i: err(f"{f}: uses ns.{dep} at load time but {files[j]} loads later")

# media referenced by code exists
code = "\n".join(open(os.path.join(addon, f), encoding="utf-8").read() for f in files if f.endswith(".lua"))
for m in re.finditer(r'T\.MEDIA \.\. "([A-Za-z0-9_\\]+)"', code):
    base = m.group(1).replace("\\\\", "/").replace("\\", "/")
    if base.endswith("/"): continue
    if not any(os.path.isfile(os.path.join(addon, "Media", base + e)) for e in ("", ".tga", ".blp")):
        err(f"code references missing media Media/{base}")
for font in re.findall(r'T\.MEDIA \.\. "Fonts\\\\([\w.\-]+\.ttf)"', code):
    if not os.path.isfile(os.path.join(addon, "Media", "Fonts", font)): err(f"missing font Media/Fonts/{font}")
    lic = os.path.join(addon, "Media", "Fonts", "OFL-ChakraPetch.txt")
    if "ChakraPetch" in font and not os.path.isfile(lic): err("Chakra Petch is bundled without its OFL license text")
for snd in re.findall(r'Sound\.play\("(\w+)"\)', code):
    if not os.path.isfile(os.path.join(addon, "Media", "Sounds", snd + ".ogg")): err(f"missing sound {snd}.ogg")
for n in range(1, 5):
    if not os.path.isfile(os.path.join(addon, "Media", "Sounds", f"clear{n}.ogg")): err(f"missing sound clear{n}.ogg")
icon = meta.get("IconTexture", "").replace("\\", "/").split("/")[-1]
if icon and not any(os.path.isfile(os.path.join(addon, "Media", icon + e)) for e in ("", ".tga", ".blp")):
    err(f"IconTexture {icon} missing")

# user-facing text: no third-party game trademark, no 'open source' claim (license is ARR)
for f in files:
    p = os.path.join(addon, f)
    if not f.endswith(".lua") or not os.path.isfile(p): continue
    for k, line in enumerate(open(p, encoding="utf-8"), 1):
        strings = re.findall(r'"([^"]*)"', line)
        for s_ in strings:
            if re.search(r"\btetris\b", s_, re.I): err(f"{f}:{k}: trademark in text: {s_}")
            if re.search(r"open source", s_, re.I): err(f"{f}:{k}: says 'open source' but the license is All Rights Reserved")

# changelog version
cl = os.path.join(os.path.dirname(os.path.abspath(addon)), "CHANGELOG.md")
if os.path.isfile(cl):
    first = re.search(r"^## (\d+\.\d+\.\d+)", open(cl, encoding="utf-8").read(), re.M)
    if not first or first.group(1) != version: err(f"CHANGELOG top entry {first and first.group(1)} != TOC version {version}")

if errors:
    print("ADDON VALIDATION FAILED:"); [print("  - " + e) for e in errors]; sys.exit(1)
print(f"addon OK: {name} {version}, {len(files)} files in load order, interfaces {', '.join(ifaces)}")
