#!/usr/bin/env python3
"""Build PetData.lua from a Wowhead Forever harvest (see harvest_petdata.js).

usage: build_petdata.py harvest.json [harvest2.json ...] > PetData.lua
Which beast teaches which rank comes from Petopia Classic (tools/harvest/petopia.html, refresh with
  curl -sL https://www.wow-petopia.com/classic/abilities.php -o tools/harvest/petopia.html).
Wowhead's "used by NPC" lists are not taming sources (a level-7 cat "uses" Dash 1), so they are only
used for spell IDs, rank levels, families and trainers.
Zone names and uiMapIDs come from QuestieDB's Forever areaIdToUiMapId table (DBC-derived),
read from the installed addon; pass its path with QUESTIE_AREAS=... to override.
"""
import json, os, re, sys

AREAS = os.environ.get("QUESTIE_AREAS", os.path.expanduser(
    "~/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_/"
    "Interface/AddOns/QuestieDB/support/Forever/Zones/areaIdToUiMapId.lua"))
DIET = [(1, "Meat"), (2, "Fish"), (4, "Cheese"), (8, "Bread"), (16, "Fungus"), (32, "Fruit"),
        (64, "Raw Meat"), (128, "Raw Fish")]
ALL_PETS = 270  # skill line "Pet - General": every family can learn it


PETOPIA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "harvest", "petopia.html")
PETOPIA_NAMES = {"Screech": "Demoralizing Screech", "Owl": "Bird of Prey"}


def areas():
    out, byname = {}, {}
    for m in re.finditer(r"\[(\d+)\]\s*=\s*(\d+),\s*--\s*(.+)", open(AREAS, encoding="utf-8").read()):
        out.setdefault(int(m[1]), (int(m[2]), m[3].strip()))
        for n in m[3].split("->"):
            byname.setdefault(n.strip(), int(m[2]))
    return out, byname


def petopia():
    """-> {ability: {"tame": bool, "beasts": {npcID: (rank, name, family, min, max, zone)}}}"""
    h = open(PETOPIA, encoding="utf-8").read()
    heads = dict(re.findall(r"<h3 class='guide_heading classic' id='(\w+)'><img[^>]*>([^<]+)</h3>", h))
    out = {}
    for m in re.finditer(r"<li id='([a-z]+)(\d+)' class='abilityrank classic'>(.*?)(?=<li id='|<h3|<hr)", h, re.S):
        name = heads[m[1]].strip()
        a = out.setdefault(PETOPIA_NAMES.get(name, name), {"tame": False, "beasts": {}})
        for li in re.findall(r"<li class='abilityranknpc classic'>(.*?)</li>", m[3]):
            n, bname, fam, lo, hi, zone = re.match(
                r".*npc=(\d+)'>([^<]+)</a> \(([^,]+), (\d+)(?:-(\d+))?, (.+)\)$", li).groups()
            a["tame"] = True
            n, r = int(n), int(m[2])
            if r > a["beasts"].get(n, (0,))[0]:
                zone = re.sub(r" \((Dungeon|Raid)\)$", "", zone.split(";")[0].strip())
                a["beasts"][n] = (r, bname.replace("&#039;", "'"), PETOPIA_NAMES.get(fam, fam),
                                  int(lo), int(hi or lo), zone)
    return out


def lua(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main(paths):
    spells, fams, npcs, lst = {}, {}, {}, []
    for p in paths:
        d = json.load(open(p))
        spells.update(d["spells"]); fams.update(d["fams"]); npcs.update(d["npcs"])
        lst = d.get("list") or lst
    zone, zonemap = areas()
    pet = petopia()

    # abilities: only real ranked entries ("Rank N")
    abilities = {}
    for sid, name, rank, level, skill, _change in lst:
        m = re.match(r"Rank (\d+)$", rank or "")
        if not m or str(sid) not in spells:
            continue
        s = spells[str(sid)]
        a = abilities.setdefault(name, {"ranks": {}, "fams": set(), "all": False, "trainer": False})
        a["ranks"][int(m[1])] = (sid, level, s["npcs"])
        a["fams"].update(s["fams"])
        a["all"] |= ALL_PETS in skill and not s["fams"]
        a["trainer"] |= s["trainers"] > 0

    famIDs = sorted(int(f) for f in fams)
    learn = {f: [] for f in famIDs}
    for name in sorted(abilities):
        a = abilities[name]
        for f in famIDs:
            if a["all"] or f in a["fams"]:
                learn[f].append(name)

    # beasts: Petopia's taming lists; beast metadata from the Wowhead harvest when it has the NPC
    famByName = {fams[str(f)]["name"]: f for f in famIDs}
    teaches, beasts = {}, {}
    for name, p in pet.items():
        if name not in abilities:
            sys.stderr.write("petopia ability not in wowhead list: %s\n" % name)
            continue
        for n, (r, bname, fam, lo, hi, zname) in p["beasts"].items():
            if r not in abilities[name]["ranks"]:
                sys.stderr.write("no spell for %s %d (%s)\n" % (name, r, bname))
                continue
            teaches.setdefault(n, []).append((name, r))
            b = npcs.get(str(n))
            z = b and next((zone[l] for l in (b.get("loc") or []) if l in zone), None)
            beasts[n] = {"name": b["name"] if b else bname, "family": famByName[fam], "min": lo, "max": hi,
                         "zone": z[1] if z else zname, "map": z[0] if z else zonemap.get(zname),
                         "rare": bool(b and b.get("cls") in (2, 4))}

    w = sys.stdout.write
    w("local _, ns = ...\n\n-- GENERATED by tools/build_petdata.py from a wowhead.com/forever harvest. Do not edit.\n")
    w("-- Zone names/uiMapIDs: QuestieDB Forever areaIdToUiMapId (DBC). TP costs: not on Wowhead, read live at the trainer.\n")
    w("ns.PetData = {\n\tsource = %s,\n" % lua("wowhead.com/forever, harvested 2026-11-18"))
    w("\tfamilies = {\n")
    for f in famIDs:
        fd = fams[str(f)]
        diet = [n for bit, n in DIET if fd["diet"] & bit]
        w("\t\t[%d] = { name = %s, diet = { %s }, abilities = { %s } },\n" % (
            f, lua(fd["name"]), ", ".join(map(lua, diet)), ", ".join(map(lua, learn[f]))))
    w("\t},\n\tabilities = {\n")
    for name in sorted(abilities):
        a = abilities[name]
        # tame: beasts know it. trainer: general pet skill bought from trainers.
        # family: Forever's family signature abilities; Wowhead lists no beast for them.
        # Petopia decides tame; abilities it doesn't know are Forever additions.
        tame = pet.get(name, {}).get("tame", False)
        taught = "tame" if tame else "trainer" if a["all"] or name in pet else "family"
        w("\t\t[%s] = { taught = %s%s, ranks = {\n" % (lua(name), lua(taught),
            ", trainer = true" if tame and a["trainer"] else ""))
        for r in sorted(a["ranks"]):
            sid, lvl, _ = a["ranks"][r]
            w("\t\t\t[%d] = { spell = %d, level = %d },\n" % (r, sid, lvl or 1))
        w("\t\t} },\n")
    w("\t},\n\tbeasts = {\n")
    for n in sorted(teaches):
        b = beasts[n]
        w("\t\t[%d] = { name = %s, family = %d, min = %d, max = %d%s%s, teaches = { %s } },\n" % (
            n, lua(b["name"]), b["family"], b["min"], b["max"],
            (", zone = %s, map = %d" % (lua(b["zone"]), b["map"])) if b["map"] else ", zone = %s" % lua(b["zone"]),
            ", rare = true" if b["rare"] else "",
            ", ".join("{ %s, %d }" % (lua(a), r) for a, r in sorted(set(teaches[n])))))
    w("\t},\n}\n")


if __name__ == "__main__":
    main(sys.argv[1:])
