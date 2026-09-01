#!/usr/bin/env python3
"""Check the privacy manifest's claims against the source that has to honour them.

Why this exists
---------------
`PrivacyInfo.xcprivacy` says Zenithium collects nothing and tracks nothing. That is the
app's central promise, it is the reason it has no accounts and no backend, and it is
declared in a plist that nobody reads again after writing it. A privacy manifest is exactly
the kind of file that stays true for a year and then quietly stops being true the first time
somebody adds a crash reporter.

So the claim is checked rather than trusted:

1. No networking API appears anywhere in the source.
2. No third-party dependency is declared.
3. Every required-reason API the app actually uses is declared in the manifest, and every
   API the manifest declares is actually used — an over-declaration is as wrong as a missing
   one, because it describes an app this is not.
4. Every shipping bundle has a manifest. An extension is not covered by the app's.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

MANIFESTS = {
    "Zenithium": ROOT / "Zenithium" / "PrivacyInfo.xcprivacy",
    "ZenithiumWidgets": ROOT / "ZenithiumWidgets" / "PrivacyInfo.xcprivacy",
    "ZenithiumWatch": ROOT / "ZenithiumWatch" / "PrivacyInfo.xcprivacy",
}

# Anything here would contradict "no data leaves the device".
NETWORK_APIS = [
    r"\bURLSession\b",
    r"\bURLRequest\b",
    r"\bNWConnection\b",
    r"\bCFStream\b",
    r"\bSocket\b",
    r"\bNSURLConnection\b",
    r"\.dataTask\(",
    r"\bWKWebView\b",
]

# Required-reason APIs, and how to spot each one in Swift.
REQUIRED_REASON = {
    "NSPrivacyAccessedAPICategoryUserDefaults": [r"\bUserDefaults\b"],
    "NSPrivacyAccessedAPICategoryFileTimestamp": [
        r"\.contentModificationDateKey", r"\.creationDateKey",
        r"\battributesOfItem\(", r"\.modificationDate\b",
    ],
    "NSPrivacyAccessedAPICategoryDiskSpace": [
        r"volumeAvailableCapacity", r"systemFreeSize", r"\bstatfs\b",
    ],
    "NSPrivacyAccessedAPICategorySystemBootTime": [
        r"\bsystemUptime\b", r"mach_absolute_time", r"CACurrentMediaTime",
    ],
    "NSPrivacyAccessedAPICategoryActiveKeyboards": [r"activeInputModes"],
}


def swift_sources() -> list[Path]:
    files: list[Path] = []
    for folder in ("Zenithium", "ZenithiumWidgets", "ZenithiumWatch"):
        files.extend(sorted((ROOT / folder).rglob("*.swift")))
    return files


def strip_comments(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    return re.sub(r"//.*?$", " ", source, flags=re.M)


def main() -> int:
    failures = 0
    sources = swift_sources()
    corpus = {file: strip_comments(file.read_text(encoding="utf-8")) for file in sources}

    # 1. No networking.
    print("=== ağ çağrısı ===")
    hits = []
    for file, text in corpus.items():
        for pattern in NETWORK_APIS:
            if re.search(pattern, text):
                hits.append(f"{file.relative_to(ROOT)}: {pattern}")
    if hits:
        failures += len(hits)
        for hit in hits:
            print(f"  ÇELİŞKİ  {hit}")
    else:
        print(f"  OK   {len(sources)} dosyada ağ API'si yok")

    # 2. No third-party packages.
    print("\n=== üçüncü parti bağımlılık ===")
    package_declarations = list(ROOT.rglob("Package.swift")) + list(
        ROOT.rglob("Package.resolved")
    )
    if package_declarations:
        failures += len(package_declarations)
        for path in package_declarations:
            print(f"  ÇELİŞKİ  {path.relative_to(ROOT)}")
    else:
        print("  OK   SPM bildirimi yok")

    # 3. Required-reason APIs: used ⇔ declared.
    print("\n=== gerekçe gerektiren API'ler ===")
    used = {
        category
        for category, patterns in REQUIRED_REASON.items()
        if any(re.search(pattern, text) for text in corpus.values() for pattern in patterns)
    }
    for target, path in MANIFESTS.items():
        if not path.exists():
            failures += 1
            print(f"  EKSİK  {target}: gizlilik bildirimi yok")
            continue
        manifest = path.read_text(encoding="utf-8")
        declared = set(re.findall(r"<string>(NSPrivacyAccessedAPICategory\w+)</string>", manifest))

        for missing in sorted(used - declared):
            failures += 1
            print(f"  EKSİK  {target}: {missing} kullanılıyor ama bildirilmemiş")
        for extra in sorted(declared - used):
            failures += 1
            print(f"  FAZLA  {target}: {extra} bildirilmiş ama kullanılmıyor")

        if "<key>NSPrivacyTracking</key>" not in manifest or "<false/>" not in manifest:
            failures += 1
            print(f"  ŞÜPHELİ  {target}: NSPrivacyTracking false değil")

    if used:
        print(f"  kullanılan: {', '.join(sorted(used))}")
    print(f"  bildirimi olan paket: {sum(1 for p in MANIFESTS.values() if p.exists())}/{len(MANIFESTS)}")

    print(f"\ntoplam sorun: {failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
