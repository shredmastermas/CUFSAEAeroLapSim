#!/usr/bin/env python3
"""Re-fetch the airfoil dataset in data/airfoils/ and rebuild MANIFEST.json.

Sources (exact URLs recorded per file in the manifest):
- Coordinates: UIUC Airfoil Coordinates Database, https://m-selig.ae.illinois.edu/ads/coord/
- Polars: airfoiltools.com XFOIL polars (Ncrit=9), http://airfoiltools.com/polar/csv?polar=...

Usage: python scripts/fetch_airfoils.py
"""

import hashlib
import json
import os
import sys
import urllib.request
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
DEST = os.path.join(HERE, "..", "data", "airfoils")

COORDS = ["s1223", "e423", "ch10sm", "s1210", "fx74cl5140"]
POLARS = ["s1223-il", "e423-il", "ch10sm-il", "s1210-il", "fx74cl5140-il"]
REYNOLDS = [200000, 500000]


def fetch(url: str, dest: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "pylapsim-fetch/0.1"})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read()
    with open(dest, "wb") as f:
        f.write(data)
    return hashlib.sha256(data).hexdigest()


def main():
    os.makedirs(DEST, exist_ok=True)
    files = {f"{c}.dat": f"https://m-selig.ae.illinois.edu/ads/coord/{c}.dat" for c in COORDS}
    for p in POLARS:
        for re_ in REYNOLDS:
            files[f"xf-{p}-{re_}.csv"] = f"http://airfoiltools.com/polar/csv?polar=xf-{p}-{re_}"
    manifest = {
        "retrieved_at": datetime.now(timezone.utc).isoformat(),
        "notes": {
            "coordinates": "UIUC Airfoil Coordinates Database (M. Selig), Selig .dat format",
            "polars": "airfoiltools.com XFOIL-computed polars (Ncrit=9, Mach 0); computed data, "
                      "not wind-tunnel measurements",
            "reynolds_rationale": "FSAE wing Re at 35-60 mph with 0.25-0.5 m chords spans ~2e5-6e5",
        },
        "files": {},
    }
    for name, url in files.items():
        sha = fetch(url, os.path.join(DEST, name))
        manifest["files"][name] = {"url": url, "sha256": sha}
        print(f"fetched {name} ({sha[:12]})")
    with open(os.path.join(DEST, "MANIFEST.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    print(f"MANIFEST.json updated ({len(files)} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
