#!/usr/bin/env python3
"""Prints the UDID of an available iPhone simulator on the newest iOS runtime."""
import json
import re
import subprocess
import sys

devices = json.loads(
    subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"])
)["devices"]


def version(runtime):
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)


for runtime in sorted(devices, key=version, reverse=True):
    if "iOS" not in runtime:
        continue
    phones = [d for d in devices[runtime] if d["name"].startswith("iPhone")]
    if phones:
        print(f"{phones[0]['name']} ({runtime})", file=sys.stderr)
        print(phones[0]["udid"])
        sys.exit(0)

sys.exit("no available iPhone simulator")
