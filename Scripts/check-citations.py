#!/usr/bin/env python3
"""Kaynak tablosunun bütünlüğü — ve docs/EVIDENCE.md'nin üreticisi.

Bu geçişin var olma sebebi, bu projedeki tek geri döndürülemez hata türü: var olmayan
ama son derece inandırıcı görünen bir bilimsel atıf. Ağ erişimi yok, yani hiçbir künye
burada doğrulanamaz. Betiğin yapabildiği şey daha dar ama yine de değerli:

  · her kaynağın bir bulunabilir tanımlayıcısı (DOI / PMID / ISBN) olduğunu,
  · olmayanların needsVerification ile işaretlendiğini,
  · hiçbir iddianın var olmayan bir kaynağa işaret etmediğini,
  · hiçbir kaynağın "neyi göstermediği" yazılmadan durmadığını,
  · çelişkilerin çift yönlü kayıtlı olduğunu,
  · motor kodunda kütüphane dışında serbest metin atıf kalmadığını

denetler. Yani künyenin doğruluğunu değil, künyenin *denetlenebilir* olduğunu garanti eder.
Doğruluğu insan kontrol eder — docs/EVIDENCE.md tam da onun için üretiliyor ve
doğrulanmamış kaynaklar orada ayrı bir başlık altında listeleniyor.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIBRARY = ROOT / "Zenithium/Domain/Intelligence/EvidenceLibrary.swift"
DOCS = ROOT / "docs/EVIDENCE.md"

DOI_PATTERN = re.compile(r"^10\.\d{4,9}/\S+$")
PMID_PATTERN = re.compile(r"^\d+$")

# "Plews et al. (2013)" and friends: a free-text citation left outside the library.
FREE_TEXT_CITATION = re.compile(r"[A-ZÇĞİÖŞÜ][A-Za-zçğıöşüÇĞİÖŞÜ]+\s+(?:et al\.|ve ark\.)\s*\(\d{4}\)")

GRADE_LABELS = {
    "mechanistic": "Mekanizma",
    "observational": "Gözlemsel",
    "cohort": "Kohort",
    "controlled": "Randomize kontrollü",
    "synthesis": "Derleme / konsensüs",
}
GRADE_ORDER = ["synthesis", "controlled", "cohort", "observational", "mechanistic"]


def fail(problems, message):
    problems.append(message)


def split_reference_literals(source):
    """Her `Reference(` çağrısının gövdesini, parantez sayarak ayırır.

    Düz regex burada yetmez: künye alanları virgül ve parantez içeren serbest metin
    taşıyor, ve `StudiedPopulation(...)` iç içe geçmiş bir çağrı.
    """
    bodies = []
    for match in re.finditer(r"\bReference\(", source):
        index = match.end()
        depth = 1
        in_string = False
        while index < len(source) and depth > 0:
            char = source[index]
            if char == '"' and source[index - 1] != "\\":
                in_string = not in_string
            elif not in_string:
                if char == "(":
                    depth += 1
                elif char == ")":
                    depth -= 1
            index += 1
        bodies.append(source[match.end():index - 1])
    return bodies


def field(body, name):
    """Bir alanın string değeri, yoksa None."""
    match = re.search(rf'\b{name}:\s*"((?:[^"\\]|\\.)*)"', body)
    return match.group(1) if match else None


def bool_field(body, name, default=False):
    match = re.search(rf"\b{name}:\s*(true|false)\b", body)
    return match.group(1) == "true" if match else default


def enum_field(body, name):
    match = re.search(rf"\b{name}:\s*\.([A-Za-z]+)", body)
    return match.group(1) if match else None


def list_field(body, name):
    match = re.search(rf"\b{name}:\s*\[([^\]]*)\]", body)
    if not match:
        return []
    return re.findall(r'"([^"]+)"', match.group(1))


def int_field(body, name):
    match = re.search(rf"\b{name}:\s*(\d+)", body)
    return int(match.group(1)) if match else None


def parse_references(problems):
    if not LIBRARY.exists():
        fail(problems, f"{LIBRARY.relative_to(ROOT)} bulunamadı.")
        return {}

    source = LIBRARY.read_text(encoding="utf-8")
    references = {}

    for body in split_reference_literals(source):
        identifier = field(body, "id")
        if not identifier:
            fail(problems, "id alanı olmayan bir Reference tanımı var.")
            continue
        if identifier in references:
            fail(problems, f"{identifier}: birden fazla kez tanımlanmış.")
            continue

        references[identifier] = {
            "id": identifier,
            "authors": field(body, "authors"),
            "year": int_field(body, "year"),
            "title": field(body, "title"),
            "venue": field(body, "venue"),
            "doi": field(body, "doi"),
            "pmid": field(body, "pmid"),
            "isbn": field(body, "isbn"),
            "grade": enum_field(body, "grade"),
            "doesNotShow": field(body, "doesNotShow"),
            "needsVerification": bool_field(body, "needsVerification"),
            "contradicts": list_field(body, "contradicts"),
        }

    return references


def check_entries(references, problems):
    for identifier, entry in sorted(references.items()):
        locatable = any(entry[key] for key in ("doi", "pmid", "isbn"))

        if not locatable and not entry["needsVerification"]:
            fail(problems, f"{identifier}: DOI, PMID veya ISBN yok ama needsVerification işaretli değil.")

        doi = entry["doi"]
        if doi and not DOI_PATTERN.match(doi):
            fail(problems, f"{identifier}: DOI biçimi geçersiz — {doi}")

        pmid = entry["pmid"]
        if pmid and not PMID_PATTERN.match(pmid):
            fail(problems, f"{identifier}: PMID yalnızca rakam olmalı — {pmid}")

        if not (entry["doesNotShow"] or "").strip():
            fail(problems, f"{identifier}: doesNotShow boş.")

        if entry["grade"] not in GRADE_LABELS:
            fail(problems, f"{identifier}: tanınmayan kanıt derecesi — {entry["grade"]}")

        for other in entry["contradicts"]:
            if other not in references:
                fail(problems, f"{identifier}: var olmayan {other} ile çelişiyor olarak işaretli.")
            elif identifier not in references[other]["contradicts"]:
                fail(problems, f"{identifier} ↔ {other}: çelişki tek yönlü tanımlanmış.")


def swift_sources():
    for path in sorted(ROOT.rglob("*.swift")):
        if any(part in {".build", "DerivedData"} for part in path.parts):
            continue
        yield path


def collect_usages(problems, references):
    """referenceIDs listelerinde geçen her anahtarı toplar ve kırık atıfları bildirir."""
    used = {}
    for path in swift_sources():
        if path == LIBRARY:
            continue
        source = path.read_text(encoding="utf-8")
        for match in re.finditer(r"referenceIDs:\s*\[([^\]]*)\]", source):
            for identifier in re.findall(r'"([^"]+)"', match.group(1)):
                used.setdefault(identifier, set()).add(str(path.relative_to(ROOT)))
                if identifier not in references:
                    fail(problems, f"{path.relative_to(ROOT)}: {identifier} kütüphanede yok.")
    return used


def check_dead_entries(references, used, problems):
    for identifier in sorted(references):
        if identifier not in used:
            fail(problems, f"{identifier}: hiçbir yerden referans verilmiyor (ölü kaynak).")


def check_free_text_citations(problems):
    """Motor kodunda kütüphane dışında kalmış serbest metin atıf.

    Yorum satırları dahil taranıyor: bir başlıktaki 'Plews et al. (2013)' cümlesi de
    kütüphaneye taşınması gereken bir atıftır, çünkü kimse onu denetlemiyor.
    """
    for path in sorted((ROOT / "Zenithium/Engines").rglob("*.swift")):
        source = path.read_text(encoding="utf-8")
        for match in FREE_TEXT_CITATION.finditer(source):
            line = source[:match.start()].count("\n") + 1
            fail(
                problems,
                f"{path.relative_to(ROOT)}:{line}: serbest metin atıf — "
                f"'{match.group(0)}' EvidenceLibrary'ye taşınmalı.",
            )


def write_docs(references, used):
    verified = [r for r in references.values() if not r["needsVerification"]]
    flagged = [r for r in references.values() if r["needsVerification"]]

    def locator(entry):
        if entry["doi"]:
            return f"doi:{entry['doi']}"
        if entry["pmid"]:
            return f"PMID:{entry['pmid']}"
        if entry["isbn"]:
            return f"ISBN:{entry['isbn']}"
        return "tanımlayıcı yok"

    def block(entry):
        lines = [
            f"#### {entry['id']}",
            "",
            f"{entry['authors']} ({entry['year']}). *{entry['title']}*. {entry['venue']}.",
            "",
            f"- **Tanımlayıcı:** {locator(entry)}",
            f"- **Kanıt derecesi:** {GRADE_LABELS.get(entry['grade'], entry['grade'])}",
            f"- **Ne göstermiyor:** {entry['doesNotShow']}",
        ]
        if entry["contradicts"]:
            contradicts_str = ", ".join(sorted(entry['contradicts']))
            lines.append(f"- **Çelişki:** {contradicts_str}")
        consumers = sorted(used.get(entry["id"], []))
        if consumers:
            consumers_str = ", ".join(consumers)
            lines.append(f"- **Kullanan:** {consumers_str}")
        lines.append("")
        return "\n".join(lines)

    parts = [
        "# Bilimsel kaynaklar",
        "",
        "Bu dosya elle yazılmaz — `Scripts/check-citations.py` tarafından",
        "`Zenithium/Domain/Intelligence/EvidenceLibrary.swift` içinden üretilir. Elle",
        "düzenlenirse bir sonraki preflight çalıştırmasında geri alınır; değişiklik",
        "kaynağın kendisinde yapılmalıdır.",
        "",
        "Her kaydın **ne göstermediği** satırı zorunludur. Bir çalışmanın neyi",
        "kanıtlamadığını yazmak, neyi kanıtladığını yazmaktan daha çok düşünmeyi",
        "gerektirir ve aşırı iddiayı kaynağında keser.",
        "",
        f"Toplam {len(references)} kaynak: {len(verified)} doğrulanmış, {len(flagged)} doğrulama bekliyor.",
        "",
        "## Doğrulanmış kaynaklar",
        "",
        "Kanıt tasarımına göre gruplanmış, güçlüden zayıfa.",
        "",
    ]

    for grade in GRADE_ORDER:
        entries = sorted([r for r in verified if r["grade"] == grade], key=lambda r: r["id"])
        if not entries:
            continue
        parts.append(f"### {GRADE_LABELS[grade]}")
        parts.append("")
        parts.extend(block(entry) for entry in entries)

    parts.extend([
        "## Doğrulama bekleyen kaynaklar",
        "",
        "Aşağıdaki kayıtların bulguları yerleşiktir; doğrulanamayan şey künyenin kendisidir",
        "— basılı yılın çevrimiçi yıldan farklı olması, bir kitap bölümünün baskısı, ya da",
        "başlığın tam olarak hatırlanamaması gibi. Bu kayıtlar uygulamada kullanılmaya",
        "devam eder ama **hiçbiri bir tavsiyeyi destekleyemez**: dayandıkları kart en fazla",
        "öneri seviyesinde kalır. Künyesi elle doğrulanan bir kaydın",
        "`needsVerification` alanı `false` yapılmalıdır.",
        "",
    ])
    if flagged:
        parts.extend(block(entry) for entry in sorted(flagged, key=lambda r: r["id"]))
    else:
        parts.append("Şu anda doğrulama bekleyen kaynak yok.\n")

    DOCS.parent.mkdir(parents=True, exist_ok=True)
    DOCS.write_text("\n".join(parts).rstrip() + "\n", encoding="utf-8")


def main():
    problems = []
    references = parse_references(problems)

    if not references:
        fail(problems, "Kütüphanede hiçbir Reference tanımı ayrıştırılamadı.")
    else:
        check_entries(references, problems)
        used = collect_usages(problems, references)
        check_dead_entries(references, used, problems)
        check_free_text_citations(problems)
        write_docs(references, used)

        flagged = sorted(r["id"] for r in references.values() if r["needsVerification"])
        print(f"{len(references)} kaynak okundu, {len(used)} tanesi kullanılıyor.")
        if flagged:
            flagged_str = ", ".join(flagged)
            print(f"Doğrulama bekleyen {len(flagged)} kaynak: {flagged_str}")
            print("Bunlar tavsiye üretemez; künyelerini docs/EVIDENCE.md üzerinden elle kontrol et.")

    if problems:
        print()
        for problem in problems:
            print(f"  ✗ {problem}")
        print(f"\n{len(problems)} sorun.")
        return 1

    print("Kaynak tablosu tutarlı. docs/EVIDENCE.md güncellendi.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
