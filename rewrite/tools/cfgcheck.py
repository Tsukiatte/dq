"""Every setting the code reads as CFG.<name> must actually exist in the settings table.

A replacement that ends in a comment can swallow the rest of a settings line, which is how
dodgeDangerWeight, dodgeDistanceCost, dodgeSafeDistanceCost and dodgeSafeWorst disappeared in
6.6.70 and took the whole field with them. Usage: python cfgcheck.py <bundle.lua>
"""
import re
import sys

src = open(sys.argv[1], encoding="utf-8").read()

# strip comments so a key that only survives inside one does not count as defined
nocomment = re.sub(r"--\[\[.*?\]\]", "", src, flags=re.S)
nocomment = re.sub(r"--[^\n]*", "", nocomment)

used = set(re.findall(r"CFG\.([A-Za-z_][A-Za-z0-9_]*)", nocomment))
defined = set(re.findall(r"(?:^|[{,\s])([A-Za-z_][A-Za-z0-9_]*)\s*=", nocomment))

missing = sorted(k for k in used if k not in defined)
print("settings read:", len(used), "| defined somewhere:", len(defined))
print("read but never defined:", missing if missing else "none")
sys.exit(1 if missing else 0)
