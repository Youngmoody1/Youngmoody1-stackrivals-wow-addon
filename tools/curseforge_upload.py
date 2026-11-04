"""Prepare (and, only with an explicit GO, upload) one StackRivals file to CurseForge.

Default = DRY RUN: it checks the ZIP against the commit, builds the upload metadata and prints
exactly what would be sent. Nothing leaves this machine.

  python3 tools/curseforge_upload.py --zip dist/StackRivals-0.8.1.zip --type beta \
      --clients forever,vanilla

A client's version must exist EXACTLY on CurseForge, or the upload stops. A documented exception
is possible only per client, by hand: --accept-version vanilla=1.15.8.

Uploading needs ALL of these (never in CI, never automatic):
  --go "I approve uploading StackRivals <version> as <type>"   (the exact sentence)
  --project <CurseForge project id>
  CF_API_TOKEN in the environment (https://authors.curseforge.com/#/settings/api-tokens)
and the file is always sent with isMarkedForManualRelease = true: after CurseForge's review it
still waits until the owner releases it by hand on the website.

--clients is required on purpose: only clients that passed their GO list (docs/RELEASE_PLAN.md)
get tagged. Keys come from tools/clients.json: forever, vanilla, retail, tbc, mists, wrath.

CurseForge Upload API (support.curseforge.com, article 9000197321, checked 2026-11-04):
  POST https://wow.curseforge.com/api/projects/{id}/upload-file  (multipart: metadata JSON + file)
  GET  https://wow.curseforge.com/api/game/wow/versions          (version ids; header X-Api-Token)
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import zipfile

API = "https://wow.curseforge.com"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# CurseForge's game version type id per client (BigWigsMods packager, release.sh, 2026-10) and the
# flavor name shown on CurseForge
CF_TYPES = {
    "retail": (517, "Retail"), "vanilla": (67408, "Classic"), "tbc": (73246, "Classic TBC"),
    "mists": (79434, "MoP Classic"), "wrath": (81212, "Titan Reforged Classic"), "forever": (88568, "Forever"),
}


def clients():
    data = json.load(open(os.path.join(ROOT, "tools", "clients.json"), encoding="utf-8"))
    return {c["key"]: c for c in data["clients"] if c.get("live")}


def toc_of(z):
    names = [n for n in z.namelist() if re.fullmatch(r"StackRivals/StackRivals\.toc", n)]
    if not names:
        raise SystemExit("ZIP: StackRivals/StackRivals.toc not found at the top level")
    text = z.read(names[0]).decode("utf-8")
    meta = dict(re.findall(r"^## ([\w-]+):\s*(.*?)\s*$", text, re.M))
    return meta


def changelog_for(version):
    text = open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8").read()
    m = re.search(r"^(## " + re.escape(version) + r"\b[^\n]*)\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not m:
        raise SystemExit(f"CHANGELOG.md has no entry for {version}")
    return m.group(1) + "\n\n" + m.group(2).strip() + "\n"


def verify_against_commit(zip_path):
    """The ZIP must hold exactly what `git archive HEAD StackRivals` holds."""
    with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
        zipfile.ZipFile(zip_path).extractall(a)
        tar = subprocess.run(["git", "archive", "HEAD", "StackRivals"], cwd=ROOT, check=True, capture_output=True).stdout
        subprocess.run(["tar", "-x", "-C", b], input=tar, check=True)
        r = subprocess.run(["diff", "-r", os.path.join(a, "StackRivals"), os.path.join(b, "StackRivals")], capture_output=True)
        if r.returncode != 0:
            raise SystemExit("ZIP differs from git archive HEAD:\n" + r.stdout.decode()[:2000])
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()


def pick_versions(versions, keys, cl, accepted):
    """CurseForge version ids: the EXACT version of each client (tools/clients.json). Never a silent
    substitute: if CurseForge lacks it, stop - unless that client has an explicit, documented
    --accept-version <client>=<version> (e.g. a game version CurseForge hasn't added yet)."""
    ids, problems = [], []
    for k in keys:
        type_id, flavor = CF_TYPES[k]
        want = accepted.get(k, cl[k]["version"])
        cands = [v for v in versions if v.get("gameVersionTypeID") == type_id]
        exact = [v for v in cands if v.get("name") == want]
        if exact:
            ids.append(exact[0]["id"])
            if k in accepted:
                print(f"note: {flavor} tagged as {want} (accepted by --accept-version instead of {cl[k]['version']})")
        else:
            have = ", ".join(sorted(v["name"] for v in cands)[-5:]) or "none"
            problems.append(f"{flavor}: CurseForge has no version {want} (latest it has: {have})")
    if problems:
        raise SystemExit("STOP, nothing uploaded:\n  " + "\n  ".join(problems)
                         + "\nIf a listed version is right for this client, re-run with --accept-version <client>=<version>"
                         + " and note it in the upload checklist (docs/CURSEFORGE.md).")
    return ids


def resolve_versions(token, keys, cl, accepted):
    import urllib.request
    req = urllib.request.Request(API + "/api/game/wow/versions", headers={"X-Api-Token": token})
    return pick_versions(json.load(urllib.request.urlopen(req, timeout=30)), keys, cl, accepted)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--zip", required=True)
    ap.add_argument("--type", required=True, choices=["alpha", "beta", "release"])
    ap.add_argument("--clients", required=True, help="comma list of tools/clients.json keys that passed their GO list")
    ap.add_argument("--project", type=int)
    ap.add_argument("--go", default="")
    ap.add_argument("--accept-version", action="append", default=[], metavar="CLIENT=VERSION",
                    help="tag CLIENT with this exact CurseForge version instead of tools/clients.json's (documented exception)")
    ap.add_argument("--selftest", action="store_true", help=argparse.SUPPRESS)
    if "--selftest" in sys.argv:
        return selftest()
    a = ap.parse_args()
    accepted = {}
    for x in a.accept_version:
        k, _, v = x.partition("=")
        if not v:
            raise SystemExit(f"--accept-version needs CLIENT=VERSION, got {x}")
        accepted[k.strip()] = v.strip()

    cl = clients()
    keys = [k.strip() for k in a.clients.split(",") if k.strip()]
    for k in keys:
        if k not in cl or k not in CF_TYPES:
            raise SystemExit(f"unknown or not-live client '{k}' (known: {', '.join(sorted(CF_TYPES))})")
    z = zipfile.ZipFile(a.zip)
    meta = toc_of(z)
    version = meta.get("Version", "")
    ifaces = sorted(x.strip() for x in meta.get("Interface", "").split(","))
    if ifaces != sorted(str(c["interface"]) for c in cl.values()):
        raise SystemExit(f"TOC interfaces {ifaces} != tools/clients.json")
    commit = verify_against_commit(a.zip)
    sha = hashlib.sha256(open(a.zip, "rb").read()).hexdigest()
    display = f"StackRivals – Loot Duels {version}" + ("" if a.type == "release" else f" ({a.type})")
    metadata = {
        "changelog": changelog_for(version), "changelogType": "markdown", "displayName": display,
        "gameVersionNames": [f"{CF_TYPES[k][1]} {cl[k]['version']}" for k in keys],
        "releaseType": a.type, "isMarkedForManualRelease": True,
    }
    print(f"ZIP {a.zip}\n  version {version}, commit {commit}, sha256 {sha}")
    print(f"  tagged for: {', '.join(CF_TYPES[k][1] + ' ' + cl[k]['version'] for k in keys)}")
    unverified = [k for k in keys if not cl[k].get("interfaceVerified")]
    if unverified:
        print(f"  WARNING: interface not verified for the live client: {', '.join(unverified)} (tools/clients.json)")
    print("metadata:\n" + json.dumps(metadata, indent=2)[:3000])

    sentence = f"I approve uploading StackRivals {version} as {a.type}"
    if a.go != sentence:
        print(f"\nDRY RUN: nothing uploaded. To upload, add --project <id> and --go \"{sentence}\" with CF_API_TOKEN set.")
        return 0
    token = os.environ.get("CF_API_TOKEN")
    if not (token and a.project):
        raise SystemExit("--go given, but CF_API_TOKEN or --project is missing: nothing uploaded")
    metadata["gameVersions"] = resolve_versions(token, keys, cl, accepted)
    del metadata["gameVersionNames"]
    import urllib.request
    import uuid
    boundary = uuid.uuid4().hex
    body = b"".join([
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"metadata\"\r\n\r\n".encode(), json.dumps(metadata).encode(), b"\r\n",
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{os.path.basename(a.zip)}\"\r\nContent-Type: application/zip\r\n\r\n".encode(),
        open(a.zip, "rb").read(), f"\r\n--{boundary}--\r\n".encode(),
    ])
    req = urllib.request.Request(f"{API}/api/projects/{a.project}/upload-file", data=body, method="POST",
                                 headers={"X-Api-Token": token, "Content-Type": f"multipart/form-data; boundary={boundary}"})
    print(urllib.request.urlopen(req, timeout=120).read().decode())
    print("Uploaded. It waits for CurseForge's review, then for YOUR manual release on the website.")
    return 0


def selftest():
    cl = {"forever": {"version": "1.60.1"}, "vanilla": {"version": "1.15.9"}}
    versions = [{"id": 1, "name": "1.60.1", "gameVersionTypeID": 88568}, {"id": 2, "name": "1.15.8", "gameVersionTypeID": 67408}]
    assert pick_versions(versions, ["forever"], cl, {}) == [1]
    try:
        pick_versions(versions, ["forever", "vanilla"], cl, {})
        raise AssertionError("a missing version was substituted")
    except SystemExit as e:
        assert "no version 1.15.9" in str(e), e
    assert pick_versions(versions, ["forever", "vanilla"], cl, {"vanilla": "1.15.8"}) == [1, 2]
    print("curseforge_upload selftest OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
