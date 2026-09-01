#!/usr/bin/env python3
"""Check the asset catalog the way `actool` does, before `actool` gets to.

Why this exists
---------------
One asset catalog is shared by all three bundles that draw — the app, the widget extension
and the watch app — because a `Color(_:bundle:)` resolves against the bundle it is asked
from, so each one needs its own copy of the catalog compiled in.

For v0.1 that catalog carried a single `AppIcon` set holding both the iOS entries and a
watchOS one. An app icon entry is tagged with the platform it belongs to, so:

* building the watch, the three iOS entries were unassigned children — a warning;
* building the widget, the watchOS entry was an unassigned child — the same warning;
* and the watch found *no* applicable content, which is an error, not a warning: a watch app
  with no icon does not install.

None of it showed up until the project was opened in Xcode, because nothing here reads asset
catalogs. This does.

What is checked
---------------
1. Every `Contents.json` parses.
2. Every filename an entry names exists on disk.
3. Every image file in a set is named by some entry.
4. Each target's `ASSETCATALOG_COMPILER_APPICON_NAME` resolves to a set that exists and that
   carries at least one entry for that target's platform.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Zenithium" / "Resources" / "Zenithium.xcassets"

# Which platform each target's icon has to cover.
TARGET_PLATFORM = {
    "Zenithium": "ios",
    "ZenithiumWidgets": "ios",
    "ZenithiumWatch": "watchos",
}

IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".pdf", ".svg"}


def check_sets() -> int:
    """Filenames and files agree, in both directions."""
    failures = 0
    for contents in sorted(CATALOG.rglob("Contents.json")):
        folder = contents.parent
        try:
            data = json.loads(contents.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            print(f"FARK  {contents.relative_to(ROOT)}: çözümlenemedi — {error}")
            failures += 1
            continue

        named = {
            entry["filename"]
            for group in ("images", "colors", "assets")
            for entry in data.get(group, [])
            if isinstance(entry, dict) and "filename" in entry
        }
        for filename in sorted(named):
            if not (folder / filename).exists():
                print(f"FARK  {folder.relative_to(ROOT)}: {filename} bildirilmiş ama dosya yok")
                failures += 1

        on_disk = {
            path.name for path in folder.iterdir()
            if path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES
        }
        for filename in sorted(on_disk - named):
            print(
                f"FARK  {folder.relative_to(ROOT)}: {filename} dosyada var ama "
                f"Contents.json onu hiçbir yuvaya atamıyor"
            )
            failures += 1
    return failures


def set_platforms(contents: Path) -> set[str]:
    """The platforms one `.appiconset` carries entries for."""
    data = json.loads(contents.read_text(encoding="utf-8"))
    platforms: set[str] = set()
    for entry in data.get("images", []):
        platform = entry.get("platform")
        if platform:
            platforms.add(platform)
        elif entry.get("idiom") in {"watch", "watch-marketing"}:
            platforms.add("watchos")
        else:
            platforms.add("ios")
    return platforms


def check_single_platform_sets() -> int:
    """No app icon set mixes platforms.

    This is the invariant the whole split exists to hold. A set with entries for two
    platforms leaves one platform's files unassigned in every build of the other, and the
    build that needs the missing platform finds no applicable content at all.
    """
    failures = 0
    for contents in sorted(ROOT.rglob("*.appiconset/Contents.json")):
        platforms = set_platforms(contents)
        if len(platforms) > 1:
            print(
                f"FARK  {contents.parent.relative_to(ROOT)}: tek kümede iki platform "
                f"({', '.join(sorted(platforms))}) — her platform kendi kümesini ister"
            )
            failures += 1
        elif not platforms:
            print(f"FARK  {contents.parent.relative_to(ROOT)}: hiç giriş yok")
            failures += 1
    return failures


def target_catalogs() -> dict[str, list[Path]]:
    """Which catalogs each target compiles, read from the generator's own table.

    `project.yml` is authoritative for target membership (BUILD-1), and the generator has to
    agree with it — `check-target-sources.py` is what compares the two. Here the point is
    different: whether the catalogs a target ends up with contain the icon it asks for.
    """
    source = (ROOT / "Scripts" / "generate-project.py").read_text(encoding="utf-8")
    shared = re.search(r'COLOR_CATALOG = "([^"]+)"', source)
    if shared is None:
        print("HATA: COLOR_CATALOG okunamadı", file=sys.stderr)
        return {}
    block = re.search(r"ICON_CATALOGS = \{(.*?)\}", source, re.S)
    icons = dict(re.findall(r'"([^"]+)":\s*"([^"]+)"', block.group(1))) if block else {}

    result: dict[str, list[Path]] = {}
    for target in TARGET_PLATFORM:
        catalogs = [ROOT / shared.group(1)]
        if target in icons:
            catalogs.append(ROOT / icons[target])
        result[target] = catalogs
    return result


def check_app_icons() -> int:
    """Each target's icon setting resolves, in the catalogs that target actually compiles."""
    yaml = (ROOT / "project.yml").read_text(encoding="utf-8")
    catalogs = target_catalogs()
    failures = 0
    summary: list[str] = []

    for target, platform in TARGET_PLATFORM.items():
        block = re.search(rf"^  {re.escape(target)}:$(.*?)(?=^  \S|\Z)", yaml, re.S | re.M)
        if block is None:
            print(f"FARK  project.yml: {target} hedefi yok")
            failures += 1
            continue
        setting = re.search(r"^\s*ASSETCATALOG_COMPILER_APPICON_NAME:\s*(\S+)", block.group(1), re.M)
        available = {
            path.stem: path
            for catalog in catalogs.get(target, [])
            for path in catalog.glob("*.appiconset")
        }

        if setting is None:
            # No icon named. Then the target must not be compiling one either, or it would be
            # built and never used — which is how the unassigned-child warning appears.
            for name in sorted(available):
                print(f"FARK  {target} simge adı vermiyor ama {name}.appiconset derliyor")
                failures += 1
            summary.append(f"{target}→yok")
            continue

        name = setting.group(1)
        if name not in available:
            print(
                f"FARK  {target}: {name} adlı küme derlediği kataloglarda yok "
                f"({', '.join(str(c.relative_to(ROOT)) for c in catalogs.get(target, []))})"
            )
            failures += 1
            continue

        platforms = set_platforms(available[name] / "Contents.json")
        if platform not in platforms:
            print(
                f"FARK  {target} ({platform}) {name} kullanıyor ama o küme yalnızca "
                f"{', '.join(sorted(platforms))} için giriş taşıyor"
            )
            failures += 1
        summary.append(f"{target}→{available[name].parent.name}/{name}")

    if not failures:
        print(f"OK    Uygulama simgeleri: {', '.join(summary)}")
    return failures


def main() -> int:
    if not CATALOG.exists():
        print(f"HATA: {CATALOG} yok", file=sys.stderr)
        return 2
    failures = check_sets() + check_single_platform_sets()
    if failures == 0:
        sets = len(list(CATALOG.rglob("Contents.json"))) - 1
        print(f"OK    {sets} varlık kümesi: bildirilen her dosya var, her dosya atanmış")
    failures += check_app_icons()
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
