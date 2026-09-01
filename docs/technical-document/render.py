import base64, pathlib, re, sys
from playwright.sync_api import sync_playwright

HERE = pathlib.Path(__file__).parent
FONT_DIR = pathlib.Path("/mnt/skills/examples/canvas-design/canvas-fonts")
FACES = [
    ("Zen Display", "BigShoulders-Bold.ttf", 700, "normal"),
    ("Zen Display", "BigShoulders-Regular.ttf", 400, "normal"),
    ("Zen Text", "WorkSans-Regular.ttf", 400, "normal"),
    ("Zen Text", "WorkSans-Italic.ttf", 400, "italic"),
    ("Zen Text", "WorkSans-Bold.ttf", 700, "normal"),
    ("Zen Text", "WorkSans-BoldItalic.ttf", 700, "italic"),
    ("Zen Mono", "IBMPlexMono-Regular.ttf", 400, "normal"),
    ("Zen Mono", "IBMPlexMono-Bold.ttf", 700, "normal"),
]

def font_css():
    out = []
    for family, filename, weight, style in FACES:
        data = base64.b64encode((FONT_DIR / filename).read_bytes()).decode()
        out.append(
            "@font-face{font-family:'%s';font-weight:%d;font-style:%s;font-display:block;"
            "src:url(data:font/ttf;base64,%s) format('truetype');}"
            % (family, weight, style, data)
        )
    return "\n".join(out)

FONTS = font_css()

FOOTER = """
<div style="width:100%;font-family:'Helvetica',sans-serif;font-size:7pt;color:#6A777E;
            padding:0 20mm 0 20mm;display:flex;justify-content:space-between;
            letter-spacing:0.1em;">
  <!-- Written uppercase rather than transformed. Chromium's footer template is a separate
       document with no `lang`, so `text-transform: uppercase` gave it the dotless Turkish
       I: every page read TEKNIK instead of TEKNİK. The brand keeps its Latin I — the
       Turkish rule applies to the Turkish words beside it, not to the name. -->
  <span>ZENITHIUM · TEKNİK DÖKÜMAN · SÜRÜM 0.1</span>
  <span class="pageNumber" style="color:#0E8E80;font-weight:700;"></span>
</div>"""
EMPTY = "<span></span>"


def render(src_html: str, out_path: pathlib.Path, page, footer=True, offset=0):
    tmp = HERE / (out_path.stem + ".built.html")
    tmp.write_text(src_html.replace("/*__FONTS__*/", FONTS), encoding="utf-8")
    page.goto(tmp.resolve().as_uri(), wait_until="networkidle")
    page.emulate_media(media="print")
    page.evaluate("document.fonts.ready")
    page.pdf(
        path=str(out_path),
        format="A4",
        print_background=True,
        display_header_footer=footer,
        header_template=EMPTY,
        footer_template=FOOTER if footer else EMPTY,
        margin={"top": "19mm", "bottom": "20mm", "left": "34mm", "right": "20mm"},
    )


HEADINGS = [
    ("ch1", "Ürün"), ("ch2", "Mimari"), ("ch3", "Veri katmanı"), ("ch4", "Motorlar"),
    ("ch5", "Arayüz ve tasarım sistemi"), ("ch6", "Sistem entegrasyonu"),
    ("ch7", "Zekâ katmanı"), ("ch8", "Veri taşınabilirliği"), ("ch9", "Teknoloji yığını"),
    ("ch10", "Kalite ve doğrulama"), ("ch11", "Yol haritası v4"), ("ch12", "Geliştirme süreci"),
    ("eka", "Faz listesi"), ("ekb", "Varsayım kayıt defteri"),
]


def tr_upper(text: str) -> str:
    """Uppercase the way Turkish does, which is not the way `str.upper` does.

    The document is `lang="tr"`, so Chromium's `text-transform: uppercase` maps `i` to the
    dotted `İ` and `ı` to `I`. Python's `str.upper` maps both to `I`. Every heading with an
    `i` in it therefore failed to match its own rendered form, and the table of contents came
    out with an em dash where its page number should be.
    """
    return text.replace("i", "İ").replace("ı", "I").upper()


def find_pages(pdf_path, offset):
    from pypdf import PdfReader
    reader = PdfReader(str(pdf_path))
    texts = [p.extract_text() or "" for p in reader.pages]
    result = {}
    flats = [re.sub(r"\s+", "", t) for t in texts]
    for key, title in HEADINGS:
        needle = tr_upper(title).replace(" ", "")
        for i, flat in enumerate(flats):
            # The H2s are rendered uppercase by CSS; the TOC keeps mixed case, so a
            # case-sensitive test cannot match the table of contents by accident.
            if needle in flat:
                result[key] = i + 1 + offset
                break
    return result, len(reader.pages)


PREAMBLE = '<!doctype html>\n<html lang="tr">\n<head>\n'


def assemble():
    """Build `doc.html` and `cover.html` from the checked-in parts.

    These two are generated and git-ignored; the parts beside them are the source. Until
    v0.1 nothing rebuilt them, so a fresh clone had every fragment of the document and no
    way to render it — the pipeline only worked in a working copy that happened to still
    carry the intermediates.

    Each part after `css.html` opens with its own `<title>` and closes `</head><body>`, so
    the head is this preamble plus the stylesheet, and the body files are concatenated in
    numeric order with the last one closing `</body>`.
    """
    css = (HERE / "css.html").read_text(encoding="utf-8")
    # `b<number>.html` only — the glob has to exclude the render's own intermediates
    # (`body.built.html`, `body-pass1.built.html`), which start with the same letter and
    # made the first assembled build fail on a previous run's leftovers.
    body_parts = sorted(
        (path for path in HERE.glob("b*.html") if re.fullmatch(r"b\d+", path.stem)),
        key=lambda path: int(path.stem[1:]),
    )
    if not body_parts:
        raise SystemExit("gövde parçası bulunamadı (b*.html)")

    doc = PREAMBLE + css + "\n".join(p.read_text(encoding="utf-8") for p in body_parts) + "\n</html>\n"
    cover = PREAMBLE + css + (HERE / "cover.body.html").read_text(encoding="utf-8") + "\n</html>\n"
    (HERE / "doc.html").write_text(doc, encoding="utf-8")
    (HERE / "cover.html").write_text(cover, encoding="utf-8")
    print("birleştirildi: %d gövde parçası (%s)" % (
        len(body_parts), ", ".join(p.name for p in body_parts)))
    return doc, cover


def main():
    doc, cover = assemble()

    with sync_playwright() as pw:
        browser = pw.chromium.launch(
            executable_path="/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
            args=["--no-sandbox"],
        )
        page = browser.new_page()

        render(cover, HERE / "cover.pdf", page, footer=False)
        render(doc, HERE / "body-pass1.pdf", page)

        pages, _ = find_pages(HERE / "body-pass1.pdf", offset=1)
        missing = [k for k, _ in HEADINGS if k not in pages]
        if missing:
            print("uyarı: bulunamayan başlıklar:", missing, file=sys.stderr)

        doc2 = doc
        for key, num in pages.items():
            doc2 = doc2.replace('data-tp="%s">—<' % key, 'data-tp="%s">%d<' % (key, num))
        render(doc2, HERE / "body.pdf", page)
        browser.close()

    from pypdf import PdfReader, PdfWriter
    writer = PdfWriter()
    for src in (HERE / "cover.pdf", HERE / "body.pdf"):
        for p in PdfReader(str(src)).pages:
            writer.add_page(p)

    titles = dict(HEADINGS)
    for key, num in sorted(pages.items(), key=lambda kv: kv[1]):
        writer.add_outline_item(titles[key], num - 1)

    writer.add_metadata({
        "/Title": "ZENITHIUM TEKNİK DÖKÜMAN — SÜRÜM 0.1 (21.08.2026 / İlk Yayın)",
        "/Subject": "iOS 18 sağlık ve antrenman uygulaması — mimari, motorlar, teknoloji yığını",
        "/Creator": "Zenithium",
        "/Keywords": "Swift 6, SwiftUI, SwiftData, HealthKit, iOS 18, watchOS 11, sürüm 0.1",
    })
    out = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "Zenithium-Teknik-Dokuman.pdf"
    with open(out, "wb") as fh:
        writer.write(fh)
    print("yazıldı:", out, "· sayfa:", len(writer.pages))


main()
