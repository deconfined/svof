#!/usr/bin/env python3
"""Match shipped passive-observer metadata with real PCRE2, then execute its
actual Lua handlers and native prompts via svof_world. No rex_stub is involved.

From this fork's root:
  python3 tools/test_passive_observations.py --lua lua
Requires Python 3, a Lua 5.1+ executable and the PCRE2 8-bit shared library
(Debian/Ubuntu: libpcre2-8-0; macOS: system library or Homebrew pcre2).
Use --pcre2-library /path/to/library if ctypes cannot locate it.
These historical reference fixtures are not live-game validation.
"""
import argparse
import ctypes
import ctypes.util
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TRIGGERS = ROOT / "src/triggers/svo (aliases, triggers)/svo"


class PCRE2:
    def __init__(self, path=None):
        path = path or ctypes.util.find_library("pcre2-8")
        if not path:
            raise RuntimeError("PCRE2 8-bit library missing; install libpcre2-8-0 (Linux) or pcre2 (Homebrew), or use --pcre2-library")
        self.lib = ctypes.CDLL(path)
        lib = self.lib
        lib.pcre2_compile_8.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_uint32, ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_size_t), ctypes.c_void_p]
        lib.pcre2_compile_8.restype = ctypes.c_void_p
        lib.pcre2_match_data_create_from_pattern_8.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        lib.pcre2_match_data_create_from_pattern_8.restype = ctypes.c_void_p
        lib.pcre2_match_8.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_size_t, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_void_p]
        lib.pcre2_match_8.restype = ctypes.c_int
        lib.pcre2_get_ovector_pointer_8.argtypes = [ctypes.c_void_p]
        lib.pcre2_get_ovector_pointer_8.restype = ctypes.POINTER(ctypes.c_size_t)
        lib.pcre2_match_data_free_8.argtypes = [ctypes.c_void_p]
        lib.pcre2_code_free_8.argtypes = [ctypes.c_void_p]

    def match(self, pattern, line):
        raw, subject = pattern.encode(), line.encode()
        error, offset = ctypes.c_int(), ctypes.c_size_t()
        code = self.lib.pcre2_compile_8(raw, len(raw), 0, ctypes.byref(error), ctypes.byref(offset), None)
        if not code:
            raise AssertionError("PCRE2 compile error %s at %s: %s" % (error.value, offset.value, pattern))
        data = self.lib.pcre2_match_data_create_from_pattern_8(code, None)
        try:
            result = self.lib.pcre2_match_8(code, subject, len(subject), 0, 0, data, None)
            if result == -1:
                return None
            if result <= 0:
                raise AssertionError("PCRE2 matching error %s: %s" % (result, pattern))
            spans = self.lib.pcre2_get_ovector_pointer_8(data)
            return [subject[spans[2*i]:spans[2*i+1]].decode() for i in range(result)]
        finally:
            self.lib.pcre2_match_data_free_8(data)
            self.lib.pcre2_code_free_8(code)


def metadata(group, name):
    records = json.loads((TRIGGERS / group / "triggers.json").read_text())
    found = [item for item in records if item["name"] == name]
    assert len(found) == 1, (group, name, "must have one metadata authority")
    record = found[0]
    assert record["isActive"] == "yes" and record["multiline"] == "no", name
    path = TRIGGERS / group / (name.replace(" ", "_") + ".lua")
    assert path.is_file(), path
    return record, path.relative_to(ROOT).as_posix()


def match_record(pcre, record, line):
    hits = []
    for entry in record["patterns"]:
        pattern, kind = entry["pattern"], entry["type"]
        if kind == "regex":
            hit = pcre.match(pattern, line)
        elif kind == "substring":
            hit = [pattern] if pattern in line else None
        else:
            raise AssertionError("unexpected passive-observer trigger type: " + kind)
        if hit is not None:
            hits.append(hit)
    assert len(hits) <= 1, (record["name"], "duplicate matching patterns", line)
    return hits[0] if hits else None


# The ten missing WS1456-1467 records, not the two already-native Doom records.
# Expected captures are independent of the source regex; no regex-to-fixture
# generation and no approximate matching that could agree with its own bug.
HAZARDS = [
    ("Miscellaneous", "Endbringer start", "ReciterA begins to regale ListenerA with a tale of a murder most foul. Of Thoth's own death at the hands of Slith, Prince of the Underworld. Of how the half-Aldar grew gluttonous of death, the power of utter massacre and slaughter piercing the Soulrealms. And of Slith's passage through the desolate plains, there to the Throne of Death to confront Death's God.", ["ReciterA", "ListenerA"], ["ReciterA", "ListenerA", "Endbringer"], []),
    ("Miscellaneous", "Endbringer continuation", "ReciterB recounts to ListenerB Slith's battle with Thoth, the gauntlet-clad claiming of the scythe that was the Endbringer's office. Of the battle betwixt ambition and inevitability, until at last the clatter of Thoth's white mask echoed across Creation and Prince dethroned God with His own Ayar-given blade.", ["ReciterB", "ListenerB"], ["ReciterB", "ListenerB", "Endbringer"], ["ReciterA", "ListenerA"]),
    ("Ignition", "Incandescence start", "A brilliant glow begins to emanate from within the raging inferno that is FlameA.", ["FlameA"], ["FlameA", "Incandescence"], []),
    ("Ignition", "Incandescence activation", "A burning column of fire descends upon FlameB, cloaking him with its brilliance. The flames merge with those that already cloak him, and he becomes little more than an incandescent pillar of light.", ["FlameB"], ["FlameB", "incandescent"], []),
    ("Ignition", "Incandescence room", "Wreathed in torrid fury, the Elemental Lord FlameC blazes bright. MiddleProse. FlameD is little more than a searing column of incandescent light.", ["FlameC", "MiddleProse", "FlameD"], ["Incandescence"], ["FlameC", "FlameD", "MiddleProse"]),
    ("Miscellaneous", "Criers bell start", "BellA begins slowly swinging his crier's bell back and forth, each swing punctuated by a loud ring.", ["BellA"], ["BellA", "bell"], ["you"]),
    ("Miscellaneous", "Criers bell direct", 'BellB begins swinging a crier\'s bell faster and faster, eliciting a great clanging from its depths. "HEAR YE, HEAR YE!", he intones, drawing upon you with obvious menace.', ["BellB"], ["BellB", "bell", "you"], []),
    ("Duress", "Rising winds", "The wind suddenly picks up, threatening to cast you to the ground with its strength. Clouds roll in and begin to madly boil as a roaring like distant thunder begins to build, growing ever louder.", [], ["Wind", "thunder"], ["StaleActor"]),
    ("Duress", "Upward launch", "Unidentified points an imperious finger at you, a wall of air manifesting beneath you and sending you streaking upwards.", [], ["air", "upward"], ["Unidentified", "StaleActor"]),
    ("Duress", "Resounding clap", "AirA brings his hands together in a single, resounding clap.", ["AirA"], ["AirA", "clap"], ["you", "dead", "pressure"]),
]


def fixture(pcre):
    hazards, priorities = [], []
    checks = 0
    for group, name, line, captures, tokens, absent in HAZARDS:
        record, path = metadata(group, name)
        assert len(record["patterns"]) == 1, name
        kind = "substring" if name == "Upward launch" else "regex"
        assert record["patterns"][0]["type"] == kind, name
        hit = match_record(pcre, record, line)
        assert hit is not None and hit[1:] == captures, (name, hit, captures)
        hazards.append(dict(group=group, name=name, path=path, line=line, matches=hit, tokens=tokens, absent=absent))
        checks += 1
        # Literal final punctuation is evidence, not a regex wildcard.
        assert match_record(pcre, record, line[:-1] + "!") is None, name
        assert match_record(pcre, record, "unrelated harmless line") is None, name
        checks += 2
        if name in {"Criers bell start", "Criers bell direct", "Rising winds"}:
            assert match_record(pcre, record, line + " trailing text") is None, name
            checks += 1
        else:
            assert match_record(pcre, record, line + " trailing text") is not None, name
            checks += 1
        if name not in {"Incandescence room", "Upward launch"}:
            assert match_record(pcre, record, "prefix " + line) is None, name
            checks += 1
        else:
            assert match_record(pcre, record, "prefix " + line) is not None, name
            checks += 1
    # Four distinct game feedback patterns plus the broad set acknowledgement.
    # Clear has two patterns in one native record, which must not double-fire.
    group = "General/Server-side commands"
    sequence = [
        ("Priority aff set", "Now prioritising the asthma affliction.", ["asthma"], "active", "asthma"),
        ("Priority aff set", "Now prioritising the novel_game_affliction affliction.", ["novel_game_affliction"], "active", "novel_game_affliction"),
        ("Priority aff clear", "No longer prioritising the asthma affliction.", ["asthma"], "unknown", None),
        ("Priority aff none", "You do not have a priority aff at the moment.", [], "none", None),
        ("Priority aff set", "Now prioritising the asthma affliction.", ["asthma"], "active", "asthma"),
        ("Priority aff clear", "[Curing]: No longer prioritising the asthma affliction.", ["asthma"], "none", None),
        ("Priority aff set", "Now prioritising the asthma affliction.", ["asthma"], "active", "asthma"),
        ("Observed curing set", "You will now cure using the custom duel set.", ["custom duel"], "unknown", None),
        ("Observed curing set", "You will now cure using the normal set.", ["normal"], "unknown", None),
        ("Observed curing set", "You will now cure using the slowcuring set.", ["slowcuring"], "unknown", None),
        ("Priority aff none", "You do not have a priority aff at the moment.", [], "none", None),
    ]
    for name, line, captures, status, affliction in sequence:
        record, path = metadata(group, name)
        hit = match_record(pcre, record, line)
        assert hit is not None and hit[1:] == captures, (name, hit, captures)
        priorities.append(dict(name=name, path=path, line=line, matches=hit, status=status, affliction=affliction))
        for negative in ("prefix " + line, line + " suffix", line[:-1] + "!"):
            assert match_record(pcre, record, negative) is None, (name, negative)
            checks += 1
        checks += 1
    # Every textual feedback line must have exactly one owner in the complete
    # General/Server-side commands metadata, including older gag records.
    records = json.loads((TRIGGERS / group / "triggers.json").read_text())
    for _, line, _, _, _ in sequence:
        owners = []
        for record in records:
            if record.get("isActive") != "yes" or record.get("isFolder") == "yes":
                continue
            # Unrelated metadata may use exact/start-of-line types.
            hits = []
            for entry in record.get("patterns", []):
                kind, pattern = entry["type"], entry["pattern"]
                if kind == "regex": hit = pcre.match(pattern, line)
                elif kind == "substring": hit = pattern in line
                elif kind == "exactMatch": hit = pattern == line
                elif kind == "startOfLine": hit = line.startswith(pattern)
                else: raise AssertionError("unsupported metadata type: " + kind)
                hits.append(bool(hit))
            # Multiline records are conjunctions, not alternatives. In
            # particular the native "[Curing]:" prefilter alone does not run
            # Running a curing command's script for a mixed-case feedback line.
            matched = bool(hits) and (all(hits) if record.get("multiline") == "yes" else any(hits))
            if matched:
                owners.append(record["name"])
        assert len(owners) == 1, (line, owners)
        checks += 1
    return dict(hazards=hazards, priority=priorities), checks


def lua(value):
    """Lua 5.1 literal (JSON escapes such as \\u are not Lua literals)."""
    if value is None: return "nil"
    if isinstance(value, bool): return "true" if value else "false"
    if isinstance(value, str):
        data = value.encode("utf-8")
        return '"' + "".join(chr(c) if 32 <= c < 127 and c not in (34, 92) else "\\%03d" % c for c in data) + '"'
    if isinstance(value, list): return "{" + ",".join(lua(item) for item in value) + "}"
    if isinstance(value, dict): return "{" + ",".join("[" + lua(key) + "]=" + lua(item) for key, item in value.items()) + "}"
    raise TypeError(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua", default="lua")
    parser.add_argument("--pcre2-library")
    args = parser.parse_args()
    data, checks = fixture(PCRE2(args.pcre2_library))
    with tempfile.TemporaryDirectory(prefix="svof-passive-observations-") as directory:
        path = Path(directory) / "captures.lua"
        path.write_text("return " + lua(data) + "\n")
        subprocess.run([args.lua, "tools/test_hazard_warnings.lua", str(path)], cwd=ROOT, check=True)
    print("ALL PASS: passive metadata (%d PCRE2/substring checks; 10 hazards, 4 priority feedback patterns, set acknowledgement)" % checks)


if __name__ == "__main__":
    main()
