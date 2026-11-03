#!/usr/bin/env python3
"""Refreshes VitrinMac/Resources/asc-commands.json against the installed asc CLI.

Walks `asc <group> --help` for every command group in Views/AscCommandShelf.swift (AscAreas). Commands already in the
catalog keep their titles and their read/needs data; new ones are added with asc's own summary as the title and a
read/change guess from the verb, removed ones are dropped. Run it after updating asc, then review the new entries.
"""
import concurrent.futures as cf, json, pathlib, re, subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "VitrinMac/Resources/asc-commands.json"
AREAS = (ROOT / "VitrinMac/Views/AscCommandShelf.swift").read_text()
READ_VERBS = {"list", "view", "get", "find", "links", "status", "search", "info", "summary", "history", "validate", "doctor", "count", "metrics"}


def groups():
    names = []
    for line in AREAS.splitlines():
        m = re.match(r"\s*static let (\w+) = \[(.*)\]", line)
        if m and m.group(1) != "notInApp":
            names += re.findall(r'"([a-z0-9-]+)"', m.group(2))
    return names


def parse(path):
    r = subprocess.run(["asc", *path, "--help"], capture_output=True, text=True, timeout=30)
    text = r.stdout if "USAGE" in r.stdout else r.stderr
    section, summary, subs, flags = "", "", [], []
    for line in text.split("\n"):
        s = line.strip()
        if line and not line.startswith(" ") and s == s.upper() and re.search("[A-Z]", s):
            section = s
        elif s and section == "DESCRIPTION":
            summary += s + " "
        elif s and section.endswith("COMMANDS") and line.startswith("  "):
            m = re.match(r"([\w-]+):?(?:\s+(.*))?$", s)
            if m:
                subs.append((m.group(1), m.group(2) or ""))
        elif section == "FLAGS" and s.startswith("--"):
            flags.append(s.split()[0][2:])
    return summary.strip(), subs, flags


def walk(path, summary, out):
    own, subs, flags = parse(path)
    out[" ".join(path)] = {"summary": (summary or own).rstrip("."), "group": bool(subs), "flags": flags}
    for name, text in subs:
        walk(path + [name], text, out)


def main():
    old = {c["path"]: c for c in json.loads(CATALOG.read_text())}
    nodes = {}
    with cf.ThreadPoolExecutor(6) as pool:
        list(pool.map(lambda g: walk([g], "", nodes), groups()))
    catalog = []
    for path, node in sorted(nodes.items()):
        keep = old.get(path)
        if keep:
            catalog.append({**keep, "group": node["group"]})
            continue
        print("new:", path)
        catalog.append({"path": path, "en": node["summary"], "tr": node["summary"], "group": node["group"],
                        "read": not node["group"] and path.split()[-1] in READ_VERBS,
                        "takes": [f for f in node["flags"] if f == "app"], "needs": []})
    for path in sorted(set(old) - set(nodes)):
        print("gone:", path)
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    main()
