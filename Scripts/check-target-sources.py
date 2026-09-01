#!/usr/bin/env python3
"""Verify the build configuration's duplicated facts agree with each other.

Three things are checked: that project.yml and generate-project.py list the same shared
sources for each target, that the App Group identifier is the same in Swift and in all three
entitlement files, and that the release version has exactly one source.

Why this exists
---------------
ASSUMPTION BUILD-1 says project.yml is authoritative and the generator is the bug when they
disagree. That only helps if somebody notices the disagreement, and twice now nobody did:

* the watch target existed only in the generator from Faz 21 until Yol haritası v4, which
  made BUILD-1's claim untrue for four phases;
* the widget target was missing PendingJournalStore.swift in project.yml while JournalWidget
  called into it, so the extension would not have compiled from the authoritative file.

Both are the same failure: two lists of the same thing, edited in one place. This script is
the check that was missing. It reports differences and exits non-zero, so it can run in a
pre-commit hook or by hand after touching either file.

The source comparison deliberately covers only the *shared* sources — files a target
compiles from outside its own folder. A target's own directory is included wholesale by
both files, so a mismatch there is not possible.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT_YML = ROOT / "project.yml"
GENERATOR = ROOT / "Scripts" / "generate-project.py"

# Target name in project.yml -> (list constant, directory constant) in the generator.
TARGETS = {
    "ZenithiumWidgets": ("WIDGET_SHARED", "WIDGET_SHARED_DIRS"),
    "ZenithiumWatch": ("WATCH_SHARED", "WATCH_SHARED_DIRS"),
}

# Paths both files carry but that are not Swift sources, so they are compared separately or
# not at all. The asset catalog is a resource, present in both by a different mechanism.
IGNORED = {"Zenithium/Resources/Zenithium.xcassets"}


def yaml_sources(target: str) -> set[str]:
    """The shared source paths project.yml lists for one target."""
    lines = PROJECT_YML.read_text(encoding="utf-8").splitlines()
    inside = False
    in_sources = False
    found: set[str] = set()
    for line in lines:
        if re.match(rf"^  {re.escape(target)}:\s*$", line):
            inside = True
            continue
        if inside and re.match(r"^  \S", line):
            break
        if inside and re.match(r"^    sources:\s*$", line):
            in_sources = True
            continue
        if in_sources:
            match = re.match(r"^      - path:\s*(\S+)", line)
            if match:
                path = match.group(1)
                # A target's own folder is included wholesale by both files.
                if not path.startswith(f"{target}"):
                    found.add(path)
            elif re.match(r"^    \S", line):
                in_sources = False
    return found - IGNORED


def generator_sources(list_name: str, dirs_name: str) -> set[str]:
    """The shared source paths the generator lists for one target."""
    text = GENERATOR.read_text(encoding="utf-8")
    found: set[str] = set()
    for name in (list_name, dirs_name):
        # Non-greedy to the first `]`, so a single-line list and a multi-line one both match.
        # Neither list contains a nested bracket, which is what makes that safe.
        match = re.search(rf"^{name}\s*=\s*\[(.*?)\]", text, re.S | re.M)
        if match is None:
            print(f"HATA: {name} generate-project.py içinde bulunamadı", file=sys.stderr)
            sys.exit(2)
        found |= set(re.findall(r'"([^"]+)"', match.group(1)))
    return found - IGNORED


VERSION_PLISTS = [
    "Zenithium/Info.plist",
    "ZenithiumWidgets/Info.plist",
    "ZenithiumWatch/Info.plist",
]


def check_version() -> int:
    """The release version lives in project.yml and nowhere else.

    Before v0.1 it lived in four places and disagreed with itself: two Info.plists hardcoded
    "1.0", the watch read `$(MARKETING_VERSION)`, and project.yml never set that variable —
    so an XcodeGen build shipped the watch app with an empty CFBundleShortVersionString,
    which App Store Connect rejects outright.

    So: the plists must read the variables, and the generator must agree with project.yml.
    """
    failures = 0
    yaml = (ROOT / "project.yml").read_text(encoding="utf-8")

    marketing = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', yaml)
    build = re.search(r'CURRENT_PROJECT_VERSION:\s*"([^"]+)"', yaml)
    if marketing is None or build is None:
        print("FARK  project.yml sürüm ayarlarını taşımıyor")
        return 1

    for name in VERSION_PLISTS:
        text = (ROOT / name).read_text(encoding="utf-8")
        for key, variable in (
            ("CFBundleShortVersionString", "$(MARKETING_VERSION)"),
            ("CFBundleVersion", "$(CURRENT_PROJECT_VERSION)"),
        ):
            pattern = rf"<key>{key}</key>\s*<string>([^<]*)</string>"
            found = re.search(pattern, text)
            if found is None:
                print(f"FARK  {name}: {key} yok")
                failures += 1
            elif found.group(1) != variable:
                print(f"FARK  {name}: {key} = {found.group(1)!r}, {variable!r} olmalı")
                failures += 1

    generator = (ROOT / "Scripts" / "generate-project.py").read_text(encoding="utf-8")
    for label, value in (("MARKETING_VERSION", marketing.group(1)),
                         ("CURRENT_PROJECT_VERSION", build.group(1))):
        for found in re.findall(rf'"{label}":\s*"([^"]+)"', generator):
            if found != value:
                print(f"FARK  generate-project.py: {label} = {found!r}, project.yml {value!r} diyor")
                failures += 1

    if not failures:
        print(f"OK    Sürüm {marketing.group(1)} (build {build.group(1)}): "
              f"project.yml, üç plist ve üreteç aynı")
    return failures


APP_GROUP_FILES = [
    "Zenithium/Zenithium.entitlements",
    "ZenithiumWatch/ZenithiumWatch.entitlements",
    "ZenithiumWidgets/ZenithiumWidgets.entitlements",
]


def check_app_group() -> int:
    """The App Group identifier lives in Swift and in three plists. Nothing else compares them.

    A mismatch produces no compiler error and no crash: the app writes to one container, the
    widget reads another, and both look healthy. It is the least visible failure in the
    project, so it gets an explicit check.
    """
    source = (ROOT / "Zenithium" / "Support" / "AppGroup.swift").read_text(encoding="utf-8")
    match = re.search(r'static let identifier = "([^"]+)"', source)
    if match is None:
        print("HATA: AppGroup.identifier okunamadı", file=sys.stderr)
        return 1
    identifier = match.group(1)

    failures = 0
    for name in APP_GROUP_FILES:
        path = ROOT / name
        if not path.exists():
            print(f"FARK  {name} yok")
            failures += 1
            continue
        if identifier not in path.read_text(encoding="utf-8"):
            print(f"FARK  {name} '{identifier}' taşımıyor")
            failures += 1

    if not failures:
        print(f"OK    App Group '{identifier}': Swift ve üç yetkilendirme dosyası aynı")
    return failures


def check_bundle_wiring() -> int:
    """Three more facts that are written twice and compared nowhere.

    Each fails silently rather than loudly, which is what puts them here:

    * `WKCompanionAppBundleIdentifier` names the phone app the watch app belongs to. Get it
      wrong and the watch app builds, installs, and never pairs.
    * `BGTaskSchedulerPermittedIdentifiers` has to list the identifier the scheduler
      registers. A mismatch is not a crash — the registration is simply refused and the
      morning pass never runs again.
    * `developmentRegion` in the generator has to agree with `developmentLanguage` in
      project.yml. It did not: project.yml said `tr` and the generator wrote `en`, so an
      XcodeGen build and the checked-in project disagreed about which localization the App
      Store falls back to.
    """
    failures = 0
    yaml = (ROOT / "project.yml").read_text(encoding="utf-8")

    app_id = re.search(r'PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)', yaml)
    watch = (ROOT / "ZenithiumWatch" / "Info.plist").read_text(encoding="utf-8")
    companion = re.search(
        r"<key>WKCompanionAppBundleIdentifier</key>\s*<string>([^<]*)</string>", watch
    )
    if app_id is None or companion is None:
        print("FARK  saat eşlik eden uygulama kimliği okunamadı")
        failures += 1
    elif companion.group(1) != app_id.group(1):
        print(f"FARK  ZenithiumWatch/Info.plist: WKCompanionAppBundleIdentifier = "
              f"{companion.group(1)!r}, uygulama {app_id.group(1)!r}")
        failures += 1

    source = (ROOT / "Zenithium" / "Engines" / "EngineConstants.swift").read_text(encoding="utf-8")
    identifier = re.search(r'static let backgroundTaskIdentifier = "([^"]+)"', source)
    app_plist = (ROOT / "Zenithium" / "Info.plist").read_text(encoding="utf-8")
    permitted = re.search(
        r"<key>BGTaskSchedulerPermittedIdentifiers</key>\s*<array>(.*?)</array>",
        app_plist,
        re.S,
    )
    if identifier is None or permitted is None:
        print("FARK  arka plan görev kimliği okunamadı")
        failures += 1
    elif identifier.group(1) not in re.findall(r"<string>([^<]*)</string>", permitted.group(1)):
        print(f"FARK  Zenithium/Info.plist: {identifier.group(1)!r} "
              f"BGTaskSchedulerPermittedIdentifiers içinde yok")
        failures += 1

    language = re.search(r"developmentLanguage:\s*(\S+)", yaml)
    generator = (ROOT / "Scripts" / "generate-project.py").read_text(encoding="utf-8")
    region = re.search(r"developmentRegion = (\w+);", generator)
    if language is None or region is None:
        print("FARK  geliştirme dili okunamadı")
        failures += 1
    elif language.group(1) != region.group(1):
        print(f"FARK  generate-project.py: developmentRegion = {region.group(1)!r}, "
              f"project.yml {language.group(1)!r} diyor")
        failures += 1

    if not failures:
        print("OK    Saat eşleşmesi, arka plan görev kimliği ve geliştirme dili tutarlı")
    return failures


def main() -> int:
    failures = check_version()
    failures += check_app_group()
    failures += check_bundle_wiring()
    for target, (list_name, dirs_name) in TARGETS.items():
        from_yaml = yaml_sources(target)
        from_generator = generator_sources(list_name, dirs_name)

        only_yaml = sorted(from_yaml - from_generator)
        only_generator = sorted(from_generator - from_yaml)

        if not only_yaml and not only_generator:
            print(f"OK    {target}: {len(from_yaml)} paylaşılan kaynak, iki dosya da aynı")
            continue

        failures += 1
        print(f"FARK  {target}:")
        for path in only_yaml:
            print(f"        yalnızca project.yml'de:        {path}")
        for path in only_generator:
            print(f"        yalnızca generate-project.py'de: {path}")

    if failures:
        print(
            "\nBUILD-1 project.yml'i yetkili sayıyor: farkı orada değil, üreteçte kapat.",
            file=sys.stderr,
        )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
