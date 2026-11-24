#!/usr/bin/env python3
"""
Check that vendored upstream crates in Verus missions are byte-identical to the
published crates.io releases.

For every missions/*/upstream/<name>-<version>/ directory, download
<name>-<version>.crate from static.crates.io, check its sha256 against the
`cksum` in the crates.io index and the sha256 recorded in upstream/README.md,
and compare every vendored file with the file in the crate.
"""
import glob
import hashlib
import io
import json
import os
import re
import sys
import tarfile
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UA = {"User-Agent": "sunstead-check-upstream/0.1"}


def fetch(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return r.read()


def index_path(name):
    n = name.lower()
    if len(n) <= 2:
        return f"{len(n)}/{n}"
    if len(n) == 3:
        return f"3/{n[0]}/{n}"
    return f"{n[:2]}/{n[2:4]}/{n}"


def main():
    failures = 0
    dirs = sorted(glob.glob(os.path.join(ROOT, "missions", "*", "upstream", "*-*")))
    for d in dirs:
        if not os.path.isdir(d):
            continue
        m = re.fullmatch(r"(.+)-(\d+\.\d+\.\d+.*)", os.path.basename(d))
        name, version = m.group(1), m.group(2)
        crate = fetch(f"https://static.crates.io/crates/{name}/{name}-{version}.crate")
        digest = hashlib.sha256(crate).hexdigest()
        index = [json.loads(l) for l in fetch(f"https://index.crates.io/{index_path(name)}").decode().splitlines() if l]
        cksum = next((e["cksum"] for e in index if e["vers"] == version), None)
        readme = open(os.path.join(os.path.dirname(d), "README.md"), encoding="utf-8").read()
        problems = []
        if digest != cksum:
            problems.append(f"crate sha256 {digest} != index cksum {cksum}")
        if digest not in readme:
            problems.append("sha256 recorded in upstream/README.md does not match")
        with tarfile.open(fileobj=io.BytesIO(crate), mode="r:gz") as tf:
            members = {mm.name: mm for mm in tf.getmembers() if mm.isfile()}
            for dirpath, _, files in os.walk(d):
                for fn in files:
                    rel = os.path.relpath(os.path.join(dirpath, fn), os.path.dirname(d))
                    mm = members.get(rel)
                    if mm is None:
                        problems.append(f"{rel}: not in the published crate")
                        continue
                    if tf.extractfile(mm).read() != open(os.path.join(dirpath, fn), "rb").read():
                        problems.append(f"{rel}: differs from the published crate")
        status = "OK" if not problems else "FAIL"
        print(f"[{status}] {os.path.relpath(d, ROOT)} ({name} {version}, sha256 {digest[:12]}...)")
        for p in problems:
            print(f"    {p}")
        failures += bool(problems)
    if not dirs:
        print("no vendored upstream crates found")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
