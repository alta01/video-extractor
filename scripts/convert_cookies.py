#!/usr/bin/env python3
"""
convert_cookies.py — convert Cookie-Editor JSON export to Netscape cookies.txt
Usage: python3 scripts/convert_cookies.py cookies/cookies.json cookies/cookies.txt
"""

import json, sys, math

src = sys.argv[1] if len(sys.argv) > 1 else "cookies/cookies.json"
dst = sys.argv[2] if len(sys.argv) > 2 else "cookies/cookies.txt"

with open(src) as f:
    cookies = json.load(f)

lines = ["# Netscape HTTP Cookie File"]
for c in cookies:
    domain = c.get("domain", "")
    host_only = c.get("hostOnly", False)
    # Netscape format: domain with leading dot means all subdomains
    include_subdomains = "FALSE" if host_only else "TRUE"
    if not domain.startswith(".") and not host_only:
        domain = "." + domain
    path = c.get("path", "/")
    secure = "TRUE" if c.get("secure", False) else "FALSE"
    expiry = int(math.floor(c.get("expirationDate", 0)))
    name = c.get("name", "")
    value = c.get("value", "")
    lines.append(f"{domain}\t{include_subdomains}\t{path}\t{secure}\t{expiry}\t{name}\t{value}")

with open(dst, "w") as f:
    f.write("\n".join(lines) + "\n")

print(f"✓ Converted {len(cookies)} cookies → {dst}")
