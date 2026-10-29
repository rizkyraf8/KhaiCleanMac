#!/usr/bin/env python3
"""Keeps the extra languages in step with the code.

Every text in the app is written as L("Indonesian", "English"). For the other languages, the English
text is the key: each interpolation becomes %1$@, %2$@… in order, exactly as `LocalizedText` builds it.
Each language has its own file, Sources/KhaiCleanMac/Localization/Translations+<code>.swift.

    scripts/l10n.py check            # every key translated, no stale entries (CI runs this)
    scripts/l10n.py missing [code]   # keys still to translate (in one language), as JSON
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources" / "KhaiCleanMac"
TABLES = SOURCES / "Localization"
LANGUAGES = ["ja", "zh-Hans", "es", "de", "pt-BR", "fr", "ko"]
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\", "'": "'", "0": "\0"}


def parse_literal(text, start):
    """Parses the Swift string literal opening at text[start] == '"'.
    Returns (key, end) where key has %N$@ for each interpolation and end is just past the closing quote."""
    assert text[start] == '"'
    i, key, count = start + 1, [], 0
    while True:
        c = text[i]
        if c == '"':
            return "".join(key), i + 1
        if c == "\\":
            nxt = text[i + 1]
            if nxt == "(":
                i = skip_interpolation(text, i + 2)
                count += 1
                key.append(f"%{count}$@")
                continue
            if nxt == "u" and text[i + 2] == "{":
                close = text.index("}", i + 3)
                key.append(chr(int(text[i + 3:close], 16)))
                i = close + 1
                continue
            key.append(ESCAPES.get(nxt, nxt))
            i += 2
            continue
        key.append(c)
        i += 1


def skip_interpolation(text, i):
    """Skips the expression of an interpolation; i is just past '\\('. Returns the index past its ')'."""
    depth = 1
    while depth:
        c = text[i]
        if c == '"':
            _, i = parse_literal(text, i)
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        i += 1
    return i


CALL = re.compile(r'(?<![\w.])L\(\s*"')


def extract():
    """{english key: [(indonesian key, "file:line"), …]} for every L(…) call."""
    found = {}
    for path in sorted(SOURCES.rglob("*.swift")):
        if TABLES in path.parents:
            continue
        text = path.read_text(encoding="utf-8")
        for match in CALL.finditer(text):
            start = match.end() - 1
            indonesian, end = parse_literal(text, start)
            rest = re.match(r"\s*,\s*", text[end:])
            if not rest or text[end + rest.end()] != '"':
                continue
            english, _ = parse_literal(text, end + rest.end())
            line = text.count("\n", 0, start) + 1
            found.setdefault(english, []).append((indonesian, f"{path.relative_to(SOURCES)}:{line}"))
    return found


ENTRY = re.compile(r'^\s*(".*"),\s*$')


def load_tables():
    """{language: {key: text}}. Entries are one per line, `"key": "text",`, which reads as JSON."""
    tables, problems = {}, []
    for language in LANGUAGES:
        path = TABLES / f"Translations+{language}.swift"
        table = tables[language] = {}
        if not path.exists():
            problems.append(f"{path.name} is missing")
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            match = ENTRY.match(line)
            if not match:
                continue
            try:
                (key, value), = json.loads("{" + match.group(1) + "}").items()
            except (ValueError, json.JSONDecodeError) as error:
                problems.append(f"{path.name}:{number}: unreadable entry ({error})")
                continue
            if key in table:
                problems.append(f"{path.name}:{number}: duplicate key {key!r}")
            if not isinstance(value, str) or not value:
                problems.append(f"{path.name}:{number}: empty text")
            table[key] = value
    return tables, problems


def placeholders(text):
    return set(re.findall(r"%\d+\$@", text))


def check():
    found, (tables, problems) = extract(), load_tables()
    summary = []
    for language, table in tables.items():
        for key, value in table.items():
            if key not in found:
                problems.append(f"{language}: stale entry, no longer in the code: {key!r}")
                continue
            # A translation may leave out a value (an English plural "s"), but never invent one.
            extra = placeholders(value) - placeholders(key)
            if extra:
                problems.append(f"{language} uses {sorted(extra)} that {key!r} doesn't have")
        missing = [key for key in found if key not in table]
        for key in missing:
            problems.append(f"{language}: missing translation: {key!r} ({found[key][0][1]})")
        summary.append(f"{language} {len(found) - len(missing)}")
    for problem in problems:
        print(problem)
    print(f"{len(found)} texts · translated: {', '.join(summary)} · {len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else "check"
    if command == "missing":
        found, (tables, _) = extract(), load_tables()
        languages = sys.argv[2:] or LANGUAGES
        print(json.dumps([{"en": k, "id": v[0][0], "at": v[0][1], "missing": [l for l in languages if k not in tables[l]]}
                          for k, v in found.items() if any(k not in tables[l] for l in languages)],
                         ensure_ascii=False, indent=1))
    else:
        sys.exit(check())
