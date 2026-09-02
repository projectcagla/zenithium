#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Zenithium — Tanıtım Sitesi Üreticisi (gen-site.py)
Şartname Yasa 8: Üç sayfa (index.html, privacy.html, support.html) tek bir kaynaktan üretilir.
Şartname Yasa 5: 0 harici istek, yerel docs/fonts/ woff2 fontları.
Şartname Yasa 3 & 4: Tipografi rampası ve L0-L2 yükselti modeli.
Şartname Yasa 2: Yeni uygulama tasarımına (64pt açık yay, hipnogram, L1 listeler) sadık maketler.
"""

import sys
import os
import difflib

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DOCS = os.path.join(ROOT, "docs")

# ── ORTAK PALET VE STİLLER ──────────────────────────────────────────
# ZenithiumColor.swift ile bayt bayt uyumlu
SHARED_CSS = """
:root {
  --ink: #07090E;
  --surface: #0D111A;
  --raised: #111725;
  --hairline: #1F2836;
  --hairline-soft: #151C28;
  --text: #E9EDF5;
  --dim: #8C96AB;
  --faint: #8590A6;
  --accent: #3ED0BE;
  --ready: #3FCF8E;
  --moderate: #F0B23F;
  --recovering: #EF5560;

  --display: "Archivo", -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
  --body: "IBM Plex Sans", -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
  --mono: "IBM Plex Mono", ui-monospace, "SF Mono", Menlo, Consolas, monospace;

  --col: 1180px;
  --gutter: clamp(20px, 4.5vw, 44px);
  --measure: 64ch;

  /* Yasa 3: Web Tipografi Rampası */
  --siteHero: clamp(2.6rem, 6vw, 4.2rem);
  --sectionTitle: clamp(1.7rem, 3.5vw, 2.4rem);
  --subTitle: 1.3rem;
  --lede: clamp(1.05rem, 1.9vw, 1.22rem);
  --text-body: 1rem;
  --text-secondary: 0.9rem;
  --eyebrow-size: 0.67rem;
}

/* Yasa 5a: Yerel Font Bildirimleri (0 harici istek, tam Türkçe desteği) */
@font-face {
  font-family: 'Archivo';
  font-style: normal;
  font-weight: 700;
  font-display: swap;
  src: url('fonts/archivo-700-latin-ext.woff2') format('woff2');
  unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF;
}
@font-face {
  font-family: 'Archivo';
  font-style: normal;
  font-weight: 700;
  font-display: swap;
  src: url('fonts/archivo-700-latin.woff2') format('woff2');
  unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD;
}
@font-face {
  font-family: 'Archivo';
  font-style: normal;
  font-weight: 800;
  font-display: swap;
  src: url('fonts/archivo-800-latin-ext.woff2') format('woff2');
  unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF;
}
@font-face {
  font-family: 'Archivo';
  font-style: normal;
  font-weight: 800;
  font-display: swap;
  src: url('fonts/archivo-800-latin.woff2') format('woff2');
  unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD;
}
@font-face {
  font-family: 'IBM Plex Sans';
  font-style: normal;
  font-weight: 400;
  font-display: swap;
  src: url('fonts/ibm-plex-sans-400-latin-ext.woff2') format('woff2');
  unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF;
}
@font-face {
  font-family: 'IBM Plex Sans';
  font-style: normal;
  font-weight: 400;
  font-display: swap;
  src: url('fonts/ibm-plex-sans-400-latin.woff2') format('woff2');
  unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD;
}
@font-face {
  font-family: 'IBM Plex Sans';
  font-style: normal;
  font-weight: 600;
  font-display: swap;
  src: url('fonts/ibm-plex-sans-600-latin-ext.woff2') format('woff2');
  unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF;
}
@font-face {
  font-family: 'IBM Plex Sans';
  font-style: normal;
  font-weight: 600;
  font-display: swap;
  src: url('fonts/ibm-plex-sans-600-latin.woff2') format('woff2');
  unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD;
}
@font-face {
  font-family: 'IBM Plex Mono';
  font-style: normal;
  font-weight: 400;
  font-display: swap;
  src: url('fonts/ibm-plex-mono-400-latin-ext.woff2') format('woff2');
  unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF;
}
@font-face {
  font-family: 'IBM Plex Mono';
  font-style: normal;
  font-weight: 400;
  font-display: swap;
  src: url('fonts/ibm-plex-mono-400-latin.woff2') format('woff2');
  unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD;
}
@font-face {
  font-family: 'IBM Plex Mono';
  font-style: normal;
  font-weight: 500;
  font-display: swap;
  src: url('fonts/ibm-plex-mono-500-latin-ext.woff2') format('woff2');
  unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF;
}
@font-face {
  font-family: 'IBM Plex Mono';
  font-style: normal;
  font-weight: 500;
  font-display: swap;
  src: url('fonts/ibm-plex-mono-500-latin.woff2') format('woff2');
  unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD;
}
@font-face {
  font-family: 'IBM Plex Mono';
  font-style: normal;
  font-weight: 600;
  font-display: swap;
  src: url('fonts/ibm-plex-mono-600-latin-ext.woff2') format('woff2');
  unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF;
}
@font-face {
  font-family: 'IBM Plex Mono';
  font-style: normal;
  font-weight: 600;
  font-display: swap;
  src: url('fonts/ibm-plex-mono-600-latin.woff2') format('woff2');
  unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD;
}

* { box-sizing: border-box; }
html { scroll-behavior: smooth; }
body {
  margin: 0;
  color: var(--text);
  font-family: var(--body);
  font-size: var(--text-body);
  line-height: 1.6;
  -webkit-font-smoothing: antialiased;
  background: var(--ink); /* L0 */
}

.wrap { max-width: var(--col); margin: 0 auto; padding: 0 var(--gutter); }
h1, h2, h3, h4 { font-family: var(--display); margin: 0; text-wrap: balance; }
p { margin: 0; }
a { color: var(--accent); text-decoration: underline; text-underline-offset: 3px; }
a:hover { text-decoration: underline; text-underline-offset: 3px; }
a:focus-visible { outline: 2px solid var(--accent); outline-offset: 3px; border-radius: 2px; }

.eyebrow {
  font-family: var(--mono);
  font-size: var(--eyebrow-size);
  font-weight: 600;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: var(--faint);
}

.numeral {
  font-family: var(--mono);
  font-variant-numeric: tabular-nums;
}

/* ── BAŞLIK / MASTHEAD ── */
header {
  border-bottom: 1px solid var(--hairline);
  background: rgba(7, 9, 14, 0.94);
  backdrop-filter: blur(10px);
  position: sticky;
  top: 0;
  z-index: 40;
}
.masthead {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 18px;
  padding: 15px 0;
  flex-wrap: wrap;
}
.mark {
  font-family: var(--display);
  font-weight: 700;
  font-size: 1.05rem;
  letter-spacing: 0.04em;
  color: var(--text);
}
.mark b { color: var(--accent); font-weight: 700; }
.masthead nav {
  display: flex;
  gap: 22px;
  font-family: var(--mono);
  font-size: 0.72rem;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  flex-wrap: wrap;
}
.masthead nav a { color: var(--dim); }
.masthead nav a:hover { color: var(--accent); text-decoration: none; }
.masthead nav a[aria-current="page"] { color: var(--accent); }

/* ── KAHRAMAN BÖLÜMÜ (L1) ── */
.hero-band {
  background-image:
    radial-gradient(115% 88% at 76% 10%, rgba(62, 208, 190, 0.08), transparent 62%),
    linear-gradient(var(--hairline-soft) 1px, transparent 1px),
    linear-gradient(90deg, var(--hairline-soft) 1px, transparent 1px);
  background-size: auto, 64px 64px, 64px 64px;
  background-position: 0 0, -1px -1px, -1px -1px;
  border-bottom: 1px solid var(--hairline-soft);
}
.hero {
  display: grid;
  gap: clamp(32px, 5vw, 64px);
  align-items: center;
  padding: clamp(48px, 6vw, 84px) 0 clamp(48px, 6vw, 76px);
}
@media (min-width: 940px) {
  .hero { grid-template-columns: minmax(0, 1.05fr) minmax(0, 0.95fr); }
}
.hero-copy { display: grid; gap: 24px; max-width: var(--measure); }
.hero h1 {
  font-size: var(--siteHero);
  font-weight: 800;
  line-height: 1.04;
  letter-spacing: -0.025em;
}
.hero h1 em { font-style: normal; color: var(--dim); }
.lede {
  font-size: var(--lede);
  color: var(--dim);
  line-height: 1.58;
}
.lede strong { color: var(--text); font-weight: 600; }
.hero-cta { display: flex; flex-wrap: wrap; gap: 12px; align-items: center; }
.btn {
  border: 1px solid var(--hairline);
  background: var(--surface); /* L2 */
  padding: 13px 22px;
  color: var(--text);
  font-family: var(--mono);
  font-size: 0.75rem;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  border-radius: 4px;
}
.btn:hover { border-color: var(--accent); color: var(--accent); text-decoration: none; }
.btn.solid {
  background: var(--accent);
  border-color: var(--accent);
  color: #04120F;
  font-weight: 600;
}
.btn.solid:hover { filter: brightness(1.08); color: #04120F; }

/* ── YETKİ MANİFESTOSU (L2) ── */
.manifest {
  border: 1px solid var(--hairline);
  background: var(--surface);
  border-radius: 4px;
  display: grid;
  gap: 0;
  max-width: var(--measure);
}
.manifest .mhead {
  padding: 12px 16px;
  border-bottom: 1px solid var(--hairline);
  font-family: var(--mono);
  font-size: 0.65rem;
  letter-spacing: 0.16em;
  text-transform: uppercase;
  color: var(--dim);
}
.manifest .mrow {
  display: grid;
  grid-template-columns: 24px 1fr auto;
  align-items: center;
  gap: 12px;
  padding: 10px 16px;
  border-bottom: 1px solid var(--hairline-soft);
  font-size: 0.88rem;
}
.manifest .mrow .x {
  color: var(--recovering);
  font-family: var(--mono);
  font-weight: 700;
}
.manifest .mrow .st {
  color: var(--dim);
  font-family: var(--mono);
  font-size: 0.75rem;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}
.manifest .foot {
  padding: 10px 16px 12px;
  font-size: 0.82rem;
  color: var(--dim);
  line-height: 1.45;
}

/* ── SAYAÇLAR (L1) ── */
.counts {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
  gap: 20px;
  padding: clamp(36px, 5vw, 48px) 0;
  border-bottom: 1px solid var(--hairline-soft);
}
.counts div { display: grid; gap: 4px; }
.counts .v {
  font-family: var(--mono);
  font-size: clamp(2rem, 3.8vw, 2.8rem);
  font-weight: 700;
  letter-spacing: -0.02em;
  color: var(--text);
  line-height: 1;
}
.counts .k {
  font-family: var(--mono);
  font-size: 0.72rem;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--accent);
}
.counts .s { font-size: 0.84rem; color: var(--dim); }

/* ── BÖLÜMLER (L1 Varsayılan) ── */
section {
  padding: clamp(56px, 8vw, 104px) 0;
  border-top: 1px solid var(--hairline-soft);
}
.sec-head {
  max-width: var(--measure);
  display: grid;
  gap: 14px;
  margin-bottom: clamp(36px, 5vw, 54px);
}
.sec-head h2 {
  font-size: var(--sectionTitle);
  font-weight: 700;
  line-height: 1.15;
  letter-spacing: -0.018em;
}
.sec-head p {
  color: var(--dim);
  font-size: 1.02rem;
  line-height: 1.6;
}

/* ── L2 PANEL (Tek, Düz, 0 Gölge, 4px Radius) ── */
.panel {
  border: 1px solid var(--hairline);
  background: var(--surface);
  border-radius: 4px;
  overflow: hidden;
}
.panel-head {
  padding: 14px 20px;
  border-bottom: 1px solid var(--hairline);
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  gap: 16px;
  flex-wrap: wrap;
}
.panel-title {
  font-family: var(--mono);
  font-size: 0.74rem;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--text);
  font-weight: 600;
}
.panel-note {
  font-family: var(--mono);
  font-size: 0.72rem;
  color: var(--dim);
}
.panel-body { padding: clamp(16px, 3vw, 24px); }

/* ── SHOWCASE DÜZENİ ── */
.showcase {
  display: grid;
  gap: clamp(32px, 5vw, 64px);
  align-items: center;
}
@media (min-width: 940px) {
  .showcase { grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); }
  .showcase.reverse .art { order: 2; }
  .showcase.reverse .prose { order: 1; }
}
.prose { display: grid; gap: 18px; max-width: var(--measure); }
.prose h3 { font-size: var(--subTitle); font-weight: 700; line-height: 1.25; }
.prose p { color: var(--dim); line-height: 1.6; }

/* ── YASA 2: CİHAZ MAKETLERİ (EN AZ 340PX) ── */
.art { display: flex; justify-content: center; }
.device {
  width: 100%;
  max-width: 380px;
  min-width: 320px;
}
@media (min-width: 480px) {
  .device { min-width: 340px; } /* Yasa 2 kuralı: ekran >= 340px */
}
.device .frame {
  background: #020305;
  border: 1px solid var(--hairline);
  border-radius: 44px;
  padding: 10px;
  box-shadow: none; /* 0 gölge */
}
.device .island {
  width: 92px;
  height: 22px;
  background: #000;
  border-radius: 11px;
  margin: 4px auto 8px;
}
.device .screen {
  background: var(--ink);
  border-radius: 34px;
  overflow: hidden;
  padding: 14px 16px 20px;
  font-family: var(--body);
  display: grid;
  gap: 14px;
  border: 1px solid var(--hairline-soft);
}

/* Ekran İçi Öğeler (Yeni Tasarımla Birebir) */
.sbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-family: var(--mono);
  font-size: 0.68rem;
  color: var(--dim);
}
.sbar .bat {
  display: inline-block;
  width: 14px;
  height: 7px;
  border: 1px solid var(--dim);
  border-radius: 2px;
  margin-left: 6px;
  vertical-align: middle;
}
.app-h {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  border-bottom: 1px solid var(--hairline-soft);
  padding-bottom: 6px;
}
.app-h .t {
  font-family: var(--display);
  font-weight: 700;
  font-size: 1.4rem;
  letter-spacing: -0.02em;
  color: var(--text);
}
.app-h .d {
  font-family: var(--mono);
  font-size: 0.7rem;
  color: var(--dim);
}

/* 64pt Kahraman Açık Yay */
.hero-score-box {
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  padding: 10px 0 6px;
}
.hero-gauge-svg {
  width: 160px;
  height: 100px;
}
.hero-score-val {
  font-family: var(--mono);
  font-size: 3.8rem; /* ~61-64pt */
  font-weight: 700;
  line-height: 1;
  color: var(--text);
  margin-top: -85px;
  letter-spacing: -0.04em;
}
.hero-score-unit {
  font-size: 1rem;
  font-weight: 500;
  color: var(--dim);
  margin-left: 2px;
}
.hero-score-badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  margin-top: 14px;
  font-family: var(--mono);
  font-size: 0.75rem;
  font-weight: 600;
}
.hero-score-badge .dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
}
.hero-score-rationale {
  font-size: 0.78rem;
  color: var(--dim);
  line-height: 1.4;
  margin-top: 8px;
  max-width: 280px;
}

/* L1 Sessiz 4'lü Metrik Şeridi */
.silent-metric-strip {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 6px;
  padding: 8px 0;
  border-top: 1px solid var(--hairline-soft);
  border-bottom: 1px solid var(--hairline-soft);
  text-align: left;
}
.silent-metric-strip .item { display: grid; gap: 2px; }
.silent-metric-strip .lbl {
  font-family: var(--mono);
  font-size: 0.6rem;
  color: var(--faint);
  text-transform: uppercase;
  white-space: nowrap;
}
.silent-metric-strip .val {
  font-family: var(--mono);
  font-size: 1.1rem; /* ~30pt skala */
  font-weight: 600;
  color: var(--text);
  line-height: 1.1;
}
.silent-metric-strip .unit {
  font-size: 0.65rem;
  color: var(--dim);
  font-weight: 400;
}
.silent-metric-strip .arr {
  font-size: 0.7rem;
  margin-left: 2px;
}

/* L2 Tek Öneri Kartı */
.app-l2-card {
  background: var(--surface);
  border: 1px solid var(--hairline);
  border-radius: 8px;
  padding: 12px 14px;
  display: grid;
  gap: 6px;
}
.app-l2-card .head {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.app-l2-card .tag {
  font-family: var(--mono);
  font-size: 0.65rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  padding: 2px 8px;
  border-radius: 12px;
}
.app-l2-card .title {
  font-size: 0.86rem;
  font-weight: 600;
  color: var(--text);
}
.app-l2-card .body {
  font-size: 0.75rem;
  color: var(--dim);
  line-height: 1.4;
}
.app-l2-card .meta-row {
  display: flex;
  justify-content: space-between;
  font-family: var(--mono);
  font-size: 0.68rem;
  color: var(--faint);
  margin-top: 4px;
  padding-top: 6px;
  border-top: 1px solid var(--hairline-soft);
}

/* ── 7 ADIMLI DİKEY KANIT ZİNCİRİ MAKETİ (L1) ── */
.trace-chain {
  display: grid;
  gap: 10px; /* 12pt ritmi */
  padding: 6px 0;
}
.trace-step {
  display: grid;
  grid-template-columns: 18px 1fr;
  gap: 10px;
  position: relative;
}
.trace-step:not(:last-child)::after {
  content: "";
  position: absolute;
  top: 18px;
  left: 8px;
  bottom: -10px;
  width: 1.5px;
  background: var(--hairline-soft);
}
.trace-num {
  width: 18px;
  height: 18px;
  border-radius: 50%;
  background: var(--accent);
  color: var(--ink);
  font-family: var(--mono);
  font-size: 0.58rem;
  font-weight: 700;
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1;
}
.trace-info { display: grid; gap: 2px; }
.trace-title-row {
  display: flex;
  justify-content: space-between;
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--text);
}
.trace-badge {
  font-family: var(--mono);
  font-size: 0.65rem;
  color: var(--accent);
}
.trace-detail {
  font-size: 0.7rem;
  color: var(--dim);
  line-height: 1.35;
}

/* ── KAS HARİTASI MAKETİ ── */
.muscle-map-box {
  display: grid;
  gap: 10px;
  text-align: center;
}
.muscle-canvas-svg {
  width: 100%;
  max-width: 180px;
  height: 160px;
  margin: 0 auto;
}
.fatigue-strip {
  display: grid;
  gap: 4px;
  text-align: left;
  border-top: 1px solid var(--hairline-soft);
  padding-top: 8px;
}
.fatigue-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 0.72rem;
}
.fatigue-row .grp { color: var(--text); font-weight: 500; }
.fatigue-row .pct {
  font-family: var(--mono);
  font-weight: 600;
}

/* ── TAHLİL LİSTESİ MAKETİ ── */
.lab-table {
  display: grid;
  gap: 6px;
}
.lab-row {
  display: grid;
  grid-template-columns: 1fr auto;
  align-items: center;
  padding: 6px 0;
  border-bottom: 1px solid var(--hairline-soft);
  font-size: 0.74rem;
}
.lab-row .name { color: var(--text); font-weight: 500; }
.lab-row .ref { font-size: 0.65rem; color: var(--faint); font-family: var(--mono); }
.lab-row .val {
  font-family: var(--mono);
  font-size: 0.85rem;
  font-weight: 600;
  text-align: right;
}
.lab-row .out-badge {
  font-family: var(--mono);
  font-size: 0.6rem;
  color: var(--recovering);
  display: block;
}

/* ── APPLE WATCH MAKİTESİ ── */
.watch {
  width: 200px;
  margin: 0 auto;
}
.watch .case {
  background: #151821;
  border: 1px solid var(--hairline);
  border-radius: 40px;
  padding: 10px;
}
.watch .wscreen {
  background: #000;
  border-radius: 30px;
  aspect-ratio: 41 / 50;
  padding: 16px 12px;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  text-align: center;
}
.watch .w-score {
  font-family: var(--mono);
  font-size: 2.6rem;
  font-weight: 700;
  color: var(--text);
  line-height: 1;
}
.watch .w-lbl {
  font-family: var(--mono);
  font-size: 0.65rem;
  letter-spacing: 0.1em;
  color: var(--moderate);
  text-transform: uppercase;
  margin-top: 4px;
}
.watch .w-badge {
  background: var(--surface);
  border: 1px solid var(--hairline);
  border-radius: 12px;
  padding: 6px;
  font-family: var(--mono);
  font-size: 0.65rem;
  color: var(--accent);
}

/* ── İDDİA MERDİVENİ ── */
.ladder {
  display: grid;
  gap: 16px;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
}
.ladder-step {
  border: 1px solid var(--hairline);
  background: var(--surface);
  border-radius: 4px;
  padding: 20px;
  display: grid;
  gap: 12px;
}
.ladder-step .tier {
  font-family: var(--mono);
  font-size: 0.68rem;
  color: var(--accent);
  text-transform: uppercase;
  letter-spacing: 0.12em;
}
.ladder-step h3 { font-size: 1.1rem; color: var(--text); }
.ladder-step p { font-size: 0.88rem; color: var(--dim); line-height: 1.5; }
.ladder-step .claim-strength {
  font-family: var(--mono);
  font-size: 0.72rem;
  color: var(--faint);
  border-top: 1px solid var(--hairline-soft);
  padding-top: 10px;
}

/* ── ALTLIK / FOOTER ── */
footer {
  border-top: 1px solid var(--hairline-soft);
  padding: clamp(48px, 6vw, 72px) 0;
  margin-top: clamp(48px, 6vw, 72px);
}
.flinks {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  margin-bottom: 24px;
}
.fine {
  font-size: 0.82rem;
  color: var(--faint);
  line-height: 1.6;
  max-width: var(--measure);
}

/* ── DUYARLILIK KORUMASI ── */
@media (max-width: 480px) {
  .masthead { flex-direction: column; align-items: flex-start; gap: 12px; }
  .masthead nav { gap: 14px; font-size: 0.66rem; }
  .silent-metric-strip { grid-template-columns: repeat(2, 1fr); gap: 10px; }
  .counts { grid-template-columns: 1fr 1fr; }
  .hero-cta { flex-direction: column; align-items: stretch; }
  .btn { text-align: center; }
  .device { min-width: 100%; max-width: 100%; }
}
"""

def page_layout(title, description, canonical_url, active_page, body_content):
    """Ortak HTML iskeleti."""
    return f"""<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="description" content="{description}">
<meta name="theme-color" content="#07090E">
<meta name="color-scheme" content="dark">
<meta property="og:title" content="{title}">
<meta property="og:description" content="{description}">
<meta property="og:type" content="website">
<meta property="og:url" content="{canonical_url}">
<meta property="og:image" content="https://projectcagla.github.io/zenithium/og.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="Zenithium — Her sayı kendi işini gösterir">
<meta property="og:locale" content="tr_TR">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{title}">
<meta name="twitter:description" content="{description}">
<meta name="twitter:image" content="https://projectcagla.github.io/zenithium/og.png">
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='7' fill='%2307090E'/%3E%3Ccircle cx='16' cy='16' r='10' fill='none' stroke='%231F2836' stroke-width='2.8'/%3E%3Cpath d='M16 6 A10 10 0 0 1 26 16' fill='none' stroke='%233ED0BE' stroke-width='2.8' stroke-linecap='round'/%3E%3C/svg%3E">
<title>{title}</title>
<style>
{SHARED_CSS}
</style>
</head>
<body>

<header>
  <div class="wrap masthead">
    <a class="mark" href="index.html">ZEN<b>İ</b>TH<b>İ</b>UM</a>
    <nav aria-label="Ana gezinme">
      <a href="index.html" {'aria-current="page"' if active_page == 'index' else ''}>Ölçüm</a>
      <a href="privacy.html" {'aria-current="page"' if active_page == 'privacy' else ''}>Gizlilik</a>
      <a href="support.html" {'aria-current="page"' if active_page == 'support' else ''}>Destek</a>
      <a href="https://github.com/projectcagla/zenithium">Kaynak Kodu</a>
    </nav>
  </div>
</header>

{body_content}

<footer>
  <div class="wrap">
    <div class="flinks">
      <a class="btn" href="index.html">Ana Sayfa</a>
      <a class="btn" href="privacy.html">Gizlilik Politikası</a>
      <a class="btn" href="support.html">Destek ve İletişim</a>
      <a class="btn" href="https://github.com/projectcagla/zenithium/blob/main/docs/EVIDENCE.md">Kanıt Tablosu (16 Kaynak)</a>
      <a class="btn" href="https://github.com/projectcagla/zenithium">GitHub Deposu</a>
    </div>
    <p class="fine">Zenithium bir spor ve atletik performans izleme aracıdır. Tıbbi cihaz değildir, klinik teşhis koymaz ve tedavi önerisinde bulunmaz. Herhangi bir sağlık şikâyetinizde lütfen hekiminize danışın. İletişim: <a href="mailto:hi@zenithium.app">hi@zenithium.app</a></p>
  </div>
</footer>

</body>
</html>
"""

# ── 1. INDEX.HTML İÇERİĞİ ──────────────────────────────────────────
def build_index():
    title = "Zenithium — Her Sayı Kendi İşini Gösterir"
    desc = "Apple Watch verinden antrenman kararı üreten, tamamen cihaz üzerinde çalışan deterministik ölçüm ve karar sistemi. Sıfır sunucu, sıfır ağ yetkisi."
    url = "https://projectcagla.github.io/zenithium/"

    content = """
<div class="hero-band"><div class="wrap hero">
  <div class="hero-copy">
    <span class="eyebrow">iOS 18 · watchOS 11 · Türkçe</span>
    <h1>Her sayı kendi işini gösterir.<br><em>Arkasını saklamaz.</em></h1>
    <p class="lede">Zenithium her sabah bir toparlanma skoru verir. Ayırt edici olan skor değil: o skorun hangi geceden çıktığını, hangi çalışmaya yaslandığını, o çalışmanın <strong>neyi göstermediğini</strong> ve fikrini neyin değiştireceğini açık bir kanıt zinciriyle verir.</p>
    <div class="hero-cta">
      <a class="btn solid" href="#karar">Nasıl Karar Veriyor?</a>
      <a class="btn" href="https://github.com/projectcagla/zenithium">Kaynak Kodu</a>
    </div>
    <div class="manifest">
      <div class="mhead">Uygulamanın Sahip Olmadığı Yetkiler</div>
      <div class="mrow"><span class="x">✕</span><span class="lab">Ağ bağlantı yetkisi</span><span class="st">Yok</span></div>
      <div class="mrow"><span class="x">✕</span><span class="lab">Kullanıcı hesabı ve sunucu</span><span class="st">Yok</span></div>
      <div class="mrow"><span class="x">✕</span><span class="lab">Üçüncü parti paket ve SDK</span><span class="st">Yok</span></div>
      <div class="mrow"><span class="x">✕</span><span class="lab">Analitik ve çökme raporlama</span><span class="st">Yok</span></div>
      <p class="foot">Bunlar kapatılmış ayarlar değil, işletim sisteminden hiç talep edilmemiş izinlerdir. Zenithium internete bağlanamaz — istese bile.</p>
    </div>
  </div>

  <div class="art">
    <div class="device" role="img" aria-label="Zenithium yeni ana ekran maketi: 64pt toparlanma skoru 59, açık yay göstergesi, 4'lü sessiz metrik şeridi ve günün önerisi kartı.">
      <div class="frame"><div class="island"></div><div class="screen">
        <div class="sbar"><span>09:41</span><span class="r">Zenithium<span class="bat"></span></span></div>
        <div class="app-h"><span class="t">Bugün</span><span class="d">2 Eyl · Salı</span></div>

        <!-- 64pt Kahraman Açık Yay -->
        <div class="hero-score-box">
          <svg class="hero-gauge-svg" viewBox="0 0 160 100">
            <path d="M 20 90 A 60 60 0 0 1 140 90" fill="none" stroke="#1F2836" stroke-width="12" stroke-linecap="round" />
            <path d="M 20 90 A 60 60 0 0 1 95 32" fill="none" stroke="#F0B23F" stroke-width="12" stroke-linecap="round" />
          </svg>
          <div class="hero-score-val">59<span class="hero-score-unit">%</span></div>
          <div class="hero-score-badge" style="color:var(--moderate)">
            <span class="dot" style="background:var(--moderate)"></span>
            <span>Orta Toparlanma</span>
          </div>
          <p class="hero-score-rationale">Gece HRV taban ortalamasının (%3,2) altında; toparlanma orta seviyede seyrediyor.</p>
        </div>

        <!-- 2. Kademe: L1 Sessiz 4'lü Metrik Şeridi -->
        <div class="silent-metric-strip">
          <div class="item">
            <span class="lbl">HRV</span>
            <span class="val">54<span class="unit"> ms</span><span class="arr" style="color:var(--recovering)">↓</span></span>
          </div>
          <div class="item">
            <span class="lbl">İstirahat</span>
            <span class="val">58<span class="unit"> bpm</span><span class="arr" style="color:var(--ready)">↑</span></span>
          </div>
          <div class="item">
            <span class="lbl">Uyku</span>
            <span class="val">7,4<span class="unit"> sa</span><span class="arr" style="color:var(--dim)">→</span></span>
          </div>
          <div class="item">
            <span class="lbl">Sıcaklık</span>
            <span class="val">+0,2<span class="unit"> °C</span><span class="arr" style="color:var(--moderate)">↑</span></span>
          </div>
        </div>

        <!-- Tek L2 Kart: Günün Önerisi -->
        <div class="app-l2-card">
          <div class="head">
            <span class="title">Günün Önerisi</span>
            <span class="tag" style="background:rgba(240,178,63,0.18); color:var(--moderate)">Dengeli Yük</span>
          </div>
          <p class="body">Otonom sinir sistemi dengesi kısmi toparlanmaya işaret ediyor. Hedef zorlanma sınırları içinde kalınması önerilir.</p>
          <div class="meta-row">
            <span>Hedef Tavan: 14,2 / 21</span>
            <span>Güven: %84</span>
          </div>
        </div>

      </div></div>
    </div>
  </div>
</div></div>

<!-- SAYAÇLAR (Gerçek Kod Değerleri: 29 Motor, 21 Kas Grubu, 50 Belirteç) -->
<div class="wrap">
  <div class="counts">
    <div><span class="v">29</span><span class="k">Hesap Motoru</span><span class="s">Cihazda yerel çalışır</span></div>
    <div><span class="v">21</span><span class="k">Kas Grubu</span><span class="s">Biyomekanik yorgunluk izi</span></div>
    <div><span class="v">50</span><span class="k">Biyobelirteç</span><span class="s">Laboratuvar referans eşleşmesi</span></div>
    <div><span class="v">14<i> gün</i></span><span class="k">Taban Çizgisi</span><span class="s">Bireysel fizyolojik pencere</span></div>
  </div>
</div>

<main class="wrap">

  <!-- İDDİA MERDİVENİ -->
  <section id="merdiven">
    <div class="sec-head">
      <span class="eyebrow">İddia Merdiveni</span>
      <h2>Aynı sabahın üç ayrı okuması. Üç farklı kanıt gücü.</h2>
      <p>Bir biyometrik skor her soruya aynı kesinlikle cevap veremez. Zenithium, sinyalin gücüne göre iddiasının derecesini sınırlar.</p>
    </div>
    <div class="ladder">
      <div class="ladder-step">
        <span class="tier">1. Kademe · Gözlem</span>
        <h3>"Gece HRV değerin 41 ms."</h3>
        <p>Doğrudan Apple Watch optik ve EKG sensörlerinden alınan ham ölçüm. Yorumsuz, filtresiz, kesin.</p>
        <span class="claim-strength">Kanıt: Sensör doğrudan ölçümü</span>
      </div>
      <div class="ladder-step">
        <span class="tier">2. Kademe · Taban Sapması</span>
        <h3>"14 günlük tabanının 1,4 standart sapma altındasın."</h3>
        <p>Bireysel geçmişle matematiksel kıyaslama. Popülasyon ortalaması değil, kendi biyometrik dağılımın.</p>
        <span class="claim-strength">Kanıt: Bireysel Z-skoru istatistiği</span>
      </div>
      <div class="ladder-step">
        <span class="tier">3. Kademe · Öneri Kısıtı</span>
        <h3>"Bugünü hafif tutmayı düşünebilirsin."</h3>
        <p>Plews (2013) ve Banister modelleriyle sentezlenmiş tavsiye. Literatür sınırları emir kipine izin vermez.</p>
        <span class="claim-strength">Kanıt: Akran denetimli spor bilimi</span>
      </div>
    </div>
  </section>

  <!-- UYKU VE HİPNOGRAM BÖLÜMÜ -->
  <section id="uyku">
    <div class="sec-head">
      <span class="eyebrow">Gece & Uyku Mimarisi</span>
      <h2>Skor uykudan çıkar, uykudan konuşur.</h2>
      <p>Saatini takarak uyuduğun her gece dört sinyal bırakır: HRV, istirahat nabzı, bilek sıcaklığı ve solunum hızı. Zenithium bunları nüfus ortalamasıyla değil, senin son 14 gecenle kıyaslar.</p>
    </div>

    <div class="showcase">
      <div class="art">
        <div class="device" role="img" aria-label="Uyku ekranı: Tam genişlik hipnogram grafiği, derin uyku ışıltılı bloğu, uyku süreleri ve borç paneli.">
          <div class="frame"><div class="island"></div><div class="screen">
            <div class="sbar"><span>09:41</span><span class="r">Zenithium<span class="bat"></span></span></div>
            <div class="app-h"><span class="t">Uyku</span><span class="d">Dün Gece</span></div>

            <!-- Hipnogram Maketi -->
            <div style="background:var(--surface); border:1px solid var(--hairline); border-radius:8px; padding:10px;">
              <div style="display:flex; justify-content:space-between; font-family:var(--mono); font-size:0.68rem; color:var(--dim); margin-bottom:8px;">
                <span>Hipnogram Mimarisi</span>
                <span style="color:var(--accent)">7 sa 25 dk</span>
              </div>
              <svg viewBox="0 0 260 70" style="width:100%; height:70px;">
                <!-- Kılavuz Çizgileri -->
                <line x1="0" y1="10" x2="260" y2="10" stroke="#151C28" stroke-width="1" />
                <line x1="0" y1="30" x2="260" y2="30" stroke="#151C28" stroke-width="1" />
                <line x1="0" y1="50" x2="260" y2="50" stroke="#151C28" stroke-width="1" />
                <!-- NREM/REM Ultradian Döngü Yolu -->
                <path d="M 0 10 L 25 10 L 35 60 L 75 60 L 85 30 L 115 30 L 125 60 L 155 60 L 165 30 L 205 30 L 215 10 L 260 10" fill="none" stroke="#3ED0BE" stroke-width="3" />
                <!-- Derin Uyku Vurgulu Blokları -->
                <rect x="35" y="55" width="40" height="15" fill="rgba(62,208,190,0.3)" />
                <rect x="125" y="55" width="30" height="15" fill="rgba(62,208,190,0.3)" />
              </svg>
              <div style="display:flex; justify-content:space-between; font-family:var(--mono); font-size:0.6rem; color:var(--faint); margin-top:4px;">
                <span>23:15</span><span>01:30</span><span>04:00</span><span>07:10</span>
              </div>
            </div>

            <!-- Evre Zamanlama Şeridi -->
            <div class="silent-metric-strip">
              <div class="item"><span class="lbl">Yattın</span><span class="val">23:15</span></div>
              <div class="item"><span class="lbl">Uyudun</span><span class="val">7,4<span class="unit"> sa</span></span></div>
              <div class="item"><span class="lbl">Uyandın</span><span class="val">07:10</span></div>
              <div class="item"><span class="lbl">Verim</span><span class="val">%94</span></div>
            </div>

            <!-- Tek L2 Kart: Uyku Borcu -->
            <div class="app-l2-card">
              <div class="head">
                <span class="title">Uyku Borcu & İhtiyaç</span>
                <span class="tag" style="background:rgba(62,208,190,0.18); color:var(--accent)">Dengede</span>
              </div>
              <p class="body">Son 7 günlük uyku açığı: −35 dk. Bu gece 8 sa 15 dk uyku, toparlanma rezervini tam kapasiteye ulaştırır.</p>
            </div>

          </div></div>
        </div>
      </div>

      <div class="prose">
        <h3>Dört gece yetmez, on dört yeter.</h3>
        <p>Taban çizgin oturana kadar Zenithium skor uydurmaz. Kalibrasyon süresince kararın toplum normlarıyla harmanlandığını ve kaç gecelik veri kaldığını açıkça söyler.</p>
        <p>Saatini takmadan uyuduğun bir gecenin ardından da uydurmaz: o sabah skor yerine hangi sinyalin eksik olduğunu yazar. Eksik veriyle üretilen bir skor ölçüme değil, tahmine dayanırdı.</p>
        <div style="display:grid; gap:12px; margin-top:8px;">
          <div style="border-left:2px solid var(--accent); padding-left:14px;">
            <strong style="color:var(--text); font-size:0.92rem;">Evreler ölçülür, tahmin edilmez.</strong>
            <p style="font-size:0.85rem; color:var(--dim); margin-top:2px;">Derin, REM ve hafif uyku süreleri Apple Health'in polisomnografiyle kalibre edilmiş kendi evre kayıtlarından okunur.</p>
          </div>
          <div style="border-left:2px solid var(--moderate); padding-left:14px;">
            <strong style="color:var(--text); font-size:0.92rem;">Borç birikir ve kapanır.</strong>
            <p style="font-size:0.85rem; color:var(--dim); margin-top:2px;">Uyku borcu tek gecelik değil, hareketli bir bakiyedir; sirkadiyen ritmi bozmadan birkaç geceye yayılarak telafi edilir.</p>
          </div>
        </div>
      </div>
    </div>
  </section>

  <!-- 7 ADIMLI DETERMINISTIK KANIT ZİNCİRİ -->
  <section id="karar">
    <div class="sec-head">
      <span class="eyebrow">Deterministik Karar</span>
      <h2>Kara kutu yapay zekâ yok. 7 adımlı kanıt zinciri var.</h2>
      <p>Zenithium'da hiçbir öneri bulanık bir dil modelinin halüsinasyonu değildir. Sinyalden karara uzanan her basamak matematiksel ve akran denetimli kaynaklarla doğrulanabilir.</p>
    </div>

    <div class="showcase reverse">
      <div class="art">
        <div class="device" role="img" aria-label="Kanıt Zinciri Ekranı: 7 adımlı dikey karar izi, ham sinyalden bilimsel künyeye.">
          <div class="frame"><div class="island"></div><div class="screen">
            <div class="sbar"><span>09:41</span><span class="r">Zenithium<span class="bat"></span></span></div>
            <div class="app-h"><span class="t">Kanıt İzi</span><span class="d">7 Adım</span></div>

            <div class="trace-chain">
              <div class="trace-step">
                <div class="trace-num">1</div>
                <div class="trace-info">
                  <div class="trace-title-row"><span>Ham Sinyal</span><span class="trace-badge">Biyometrik</span></div>
                  <div class="trace-detail">HRV 41 ms · Dinlenik Nabız 58 bpm</div>
                </div>
              </div>
              <div class="trace-step">
                <div class="trace-num">2</div>
                <div class="trace-info">
                  <div class="trace-title-row"><span>Taban Sapması</span><span class="trace-badge">Z = −1,4</span></div>
                  <div class="trace-detail">14 günlük bireysel ortalamanın 5,4 ms altında</div>
                </div>
              </div>
              <div class="trace-step">
                <div class="trace-num">3</div>
                <div class="trace-info">
                  <div class="trace-title-row"><span>Katkı ve Ağırlık</span><span class="trace-badge">%60 Pay</span></div>
                  <div class="trace-detail">Otonom toparlanma %60, uyku mimarisi %40</div>
                </div>
              </div>
              <div class="trace-step">
                <div class="trace-num">4</div>
                <div class="trace-info">
                  <div class="trace-title-row"><span>Kural / Eşik</span><span class="trace-badge">Tetiklendi</span></div>
                  <div class="trace-detail">Z &lt; −1,0 eşiği toparlanma önceliği kuralını açtı</div>
                </div>
              </div>
              <div class="trace-step">
                <div class="trace-num">5</div>
                <div class="trace-info">
                  <div class="trace-title-row"><span>Karar Hükmü</span><span class="trace-badge" style="color:var(--moderate)">Dengeli Yük</span></div>
                  <div class="trace-detail">Hafif aerobik seans veya mobilite çalışması</div>
                </div>
              </div>
              <div class="trace-step">
                <div class="trace-num">6</div>
                <div class="trace-info">
                  <div class="trace-title-row"><span>Güven Düzeyi</span><span class="trace-badge">%84</span></div>
                  <div class="trace-detail">14 günlük eksiksiz taban verisiyle yüksek güven</div>
                </div>
              </div>
              <div class="trace-step">
                <div class="trace-num">7</div>
                <div class="trace-info">
                  <div class="trace-title-row"><span>Kaynak Künyesi</span><span class="trace-badge">EVIDENCE.md</span></div>
                  <div class="trace-detail">Banister (1991), Plews (2013), Gabbett (2016)</div>
                </div>
              </div>
            </div>

          </div></div>
        </div>
      </div>

      <div class="prose">
        <h3>Gerekçesini gösteremeyen öneri astrolojidir.</h3>
        <p>Piyasadaki giyilebilir cihaz uygulamaları "Bugün zorlanmaya hazırsın" der ama nedenini söyleyemez. Bir tavsiyeyi sorgulayamıyorsan ona güvenemezsin.</p>
        <p>Zenithium'da her sabah ekranın altındaki <strong>"Neden bu?"</strong> düğmesine dokunarak bu 7 adımı incelersin: hangi biyometrik sinyalin karara kaç puan etki ettiğini, hangi bilimsel eşiğin aşıldığını ve fikrini neyin değiştireceğini görürsün.</p>
        <p>Yarın sabah HRV değerin tabanına dönerse karar anında değişir; çünkü sistem inanca değil, deterministik matematiğe dayanır.</p>
      </div>
    </div>
  </section>

  <!-- KAS HARİTASI VE TAHLİL -->
  <section id="kas-tahlil">
    <div class="sec-head">
      <span class="eyebrow">Biyomekanik & Tahlil</span>
      <h2>Kas yorgunluğu ve kan tablosu bir arada.</h2>
      <p>Kuvvet antrenmanları kalp atışından ibaret değildir. 21 kas grubunun mekanik yük dağılımı ve laboratuvar kan tahlillerin, tek bir tutarlı modelde birleşir.</p>
    </div>

    <div class="showcase">
      <div class="art">
        <div class="device" role="img" aria-label="Kas Haritası ve Tahlil Ekranı: Gergin anatomik insan figürü, yorulan kas grupları ve referans aralıklı laboratuvar sonuçları.">
          <div class="frame"><div class="island"></div><div class="screen">
            <div class="sbar"><span>09:41</span><span class="r">Zenithium<span class="bat"></span></span></div>
            <div class="app-h"><span class="t">Biyomekanik</span><span class="d">21 Kas Grubu</span></div>

            <!-- Kas Haritası Silueti -->
            <div class="muscle-map-box">
              <svg class="muscle-canvas-svg" viewBox="0 0 100 130">
                <!-- Baş & Gövde -->
                <circle cx="50" cy="14" r="8" fill="#1F2836" />
                <path d="M 40 24 L 60 24 L 56 60 L 44 60 Z" fill="#3ED0BE" opacity="0.8" />
                <!-- Kollar -->
                <path d="M 38 26 L 24 50 L 28 52 L 40 30 Z" fill="#3FCF8E" />
                <path d="M 62 26 L 76 50 L 72 52 L 60 30 Z" fill="#3FCF8E" />
                <!-- Bacaklar (Yorgun - Kırmızı/Sarı) -->
                <path d="M 43 62 L 38 95 L 44 95 L 48 62 Z" fill="#EF5560" />
                <path d="M 57 62 L 62 95 L 56 95 L 52 62 Z" fill="#EF5560" />
                <!-- Baldırlar -->
                <path d="M 38 97 L 36 122 L 42 122 L 44 97 Z" fill="#F0B23F" />
                <path d="M 62 97 L 64 122 L 58 122 L 56 97 Z" fill="#F0B23F" />
              </svg>
              <div class="fatigue-strip">
                <span class="eyebrow" style="font-size:0.6rem;">En Çok Yorulan Gruplar</span>
                <div class="fatigue-row"><span class="grp">Kuadriseps</span><span class="pct" style="color:var(--recovering)">%52 toparlandı (18 sa)</span></div>
                <div class="fatigue-row"><span class="grp">Hamstring</span><span class="pct" style="color:var(--moderate)">%64 toparlandı (10 sa)</span></div>
                <div class="fatigue-row"><span class="grp">Sırt (Lats)</span><span class="pct" style="color:var(--ready)">%88 hazır</span></div>
              </div>
            </div>

            <!-- Tek L2 Öneri Kartı -->
            <div class="app-l2-card">
              <div class="head">
                <span class="title">Seans Önerisi</span>
                <span class="tag" style="background:rgba(62,208,190,0.18); color:var(--accent)">Üst Gövde</span>
              </div>
              <p class="body">Bacakları dinlendir, üst gövde hazır. Göğüs, sırt veya omuz odaklı bir seans ideal toparlanma dengesi sağlar.</p>
            </div>

          </div></div>
        </div>
      </div>

      <div class="prose">
        <h3>Kan tahlilinde teşhis yok, sakin gerçekler var.</h3>
        <p>Hastaneden aldığın PDF tahlil sonucunu doğrudan cihaza aktarırsın. Sistem 50 farklı biyobelirteci ve 202 eş anlamlı laboratuvar adını cihaz üzerinde tarar.</p>
        <p>Zenithium doktorculuk oynamaz: tahlili teşhis etmez; sadece değerin nerede durduğunu, referans aralığında olup olmadığını ve son antrenmanının sonucu etkileyip etkilemediğini söyler.</p>
        <div class="panel" style="margin-top:12px;">
          <div class="panel-head"><span class="panel-title">Tahlil Belirteç Örneği</span><span class="panel-note">Cihaz İçi Eşleme</span></div>
          <div class="panel-body">
            <div class="lab-table">
              <div class="lab-row">
                <div><span class="name">Ferritin</span><span class="ref">Ref: 30 – 400 µg/L</span></div>
                <div><span class="val">142</span></div>
              </div>
              <div class="lab-row">
                <div><span class="name">D Vitamini</span><span class="ref">Ref: 30 – 100 ng/mL</span></div>
                <div><span class="val" style="color:var(--recovering)">24</span><span class="out-badge">Aralık Dışı</span></div>
              </div>
              <div class="lab-row">
                <div><span class="name">TSH</span><span class="ref">Ref: 0,4 – 4,0 mIU/L</span></div>
                <div><span class="val">1,8</span></div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>

  <!-- SAAT EKRANI VE SINIRLAR -->
  <section id="saat-sinirlar">
    <div class="sec-head">
      <span class="eyebrow">Bilekteki Sadakat</span>
      <h2>Bileğinde bağırmayan bir gösterge.</h2>
      <p>Apple Watch ekranı dikkat çekmek için yanıp sönmez. Günün skorunu ve hedef zorlanma sınırını yüksek kontrastlı tek bir bakışta sunar.</p>
    </div>

    <div class="showcase">
      <div class="art">
        <div class="watch" role="img" aria-label="Apple Watch maketi: 41/50 ekran oranı, siyah zemin üzerinde 59 toparlanma skoru ve hedef zorlanma rozeti.">
          <div class="case"><div class="wscreen">
            <div style="display:flex; justify-content:space-between; font-family:var(--mono); font-size:0.65rem; color:var(--dim);">
              <span>09:41</span><span style="color:var(--accent)">●</span>
            </div>
            <div>
              <div class="w-score">59</div>
              <div class="w-lbl">Toparlanma</div>
            </div>
            <div class="w-badge">
              Hedef Zorlanma: 14,2
            </div>
          </div></div>
        </div>
      </div>

      <div class="prose">
        <h3>Uygulamanın bilerek yapmadıkları.</h3>
        <p>Bir ürünün kalitesini ne yaptığı kadar, neyi yapmayı <strong>reddettiği</strong> belirler. Zenithium pazarlama hevesiyle eklenmiş şu sahte özellikleri içermez:</p>
        <ul style="list-style:none; padding:0; margin:0; display:grid; gap:8px; font-size:0.9rem; color:var(--dim);">
          <li><strong style="color:var(--text)">✕ Bildirim ve hatırlatıcı spam'i:</strong> Sabah saati açtığında veri oradadır; seni gün içinde taciz etmez.</li>
          <li><strong style="color:var(--text)">✕ Yatış saati koçluğu:</strong> Bir algoritma senin ne zaman uyuyacağına dikte edemez.</li>
          <li><strong style="color:var(--text)">✕ Biyolojik yaş uydurmacası:</strong> Tek bir formülle biyolojik yaş satmak bilimsel değil, astrolojiktir.</li>
          <li><strong style="color:var(--text)">✕ Sahte sohbet botları:</strong> Karar bir dil modelinin tahmininden değil, deterministik formüllerden çıkar.</li>
        </ul>
      </div>
    </div>
  </section>

</main>
"""
    return page_layout(title, desc, url, "index", content)

# ── 2. PRIVACY.HTML İÇERİĞİ ─────────────────────────────────────────
def build_privacy():
    title = "Zenithium — Gizlilik Politikası"
    desc = "Zenithium'un sunucusu, hesabı ve ağ bağlantı yetkisi yoktur. Sağlık verileri cihazdan asla çıkmaz."
    url = "https://projectcagla.github.io/zenithium/privacy.html"

    content = """
<div class="hero-band"><div class="wrap hero">
  <div class="hero-copy">
    <span class="eyebrow">Gizlilik Protokolü · Privacy Protocol</span>
    <h1>Sıfır sunucu.<br><em>Sıfır hesap. Sıfır izleme.</em></h1>
    <p class="lede">Zenithium bir gizlilik sözü vermez; gizlilik ihlalini <strong>teknik olarak imkânsız</strong> kılan bir mimariyle çalışır. Uygulamanın işletim sisteminden ağ bağlantı izni (Network Capability) dahi yoktur.</p>
    <div class="manifest">
      <div class="mhead">Mimari Güvenceler</div>
      <div class="mrow"><span class="x">✕</span><span class="lab">Sunucu altyapısı</span><span class="st">0 Bayt</span></div>
      <div class="mrow"><span class="x">✕</span><span class="lab">Kullanıcı kaydı ve e-posta</span><span class="st">Yok</span></div>
      <div class="mrow"><span class="x">✕</span><span class="lab">Üçüncü parti SDK</span><span class="st">0 Adet</span></div>
      <div class="mrow"><span class="x">✕</span><span class="lab">İnternet erişim yetkisi</span><span class="st">Kapalı</span></div>
      <p class="foot">Gizlilik politikamız bir hukuk metni değil, kaynak koduyla denetlenebilen teknik bir gerçektir.</p>
    </div>
  </div>
</div></div>

<main class="wrap">
  <section style="border-top:0;">
    <div class="sec-head">
      <span class="eyebrow">Hükümler · Clauses</span>
      <h2>Verilerin Yalnızca Cihazında Yaşar</h2>
    </div>

    <div style="display:grid; gap:24px; max-width:var(--measure);">
      <article class="panel" style="padding:20px;">
        <span class="eyebrow">01 · Sağlık Verileri</span>
        <h3 style="font-size:1.15rem; margin:6px 0 10px; color:var(--text);">Apple HealthKit Entegrasyonu</h3>
        <p style="color:var(--dim); font-size:0.92rem; line-height:1.6;">Zenithium, kalp atış hızı, HRV, uyku evreleri ve antrenman kayıtlarını yalnızca cihaz üzerindeki Apple HealthKit veri tabanından okur. Okunan hiçbir veri harici bir belleğe veya üçüncü tarafa kopyalanmaz. Hesaplamalar Apple'ın korumalı sandbox ortamında gerçekleşir.</p>
        <p style="color:var(--faint); font-size:0.85rem; margin-top:8px; line-height:1.5;"><em>English:</em> Zenithium reads biometric data exclusively from your on-device Apple HealthKit store. No health metrics ever leave your device. All mathematical calculations execute inside Apple's sandboxed environment.</p>
      </article>

      <article class="panel" style="padding:20px;">
        <span class="eyebrow">02 · Ağ ve İletişim</span>
        <h3 style="font-size:1.15rem; margin:6px 0 10px; color:var(--text);">Sıfır Ağ Yetkisi</h3>
        <p style="color:var(--dim); font-size:0.92rem; line-height:1.6;">Uygulama derlenirken hiçbir ağ kütüphanesi (URLSession, WebKit vb.) içermez. Xcode Info.plist dosyasında harici iletişim için hiçbir yetki talep edilmemiştir. Uygulama internete bağlanamaz.</p>
        <p style="color:var(--faint); font-size:0.85rem; margin-top:8px; line-height:1.5;"><em>English:</em> The application binary does not include network libraries or communication capabilities. It is structurally impossible for Zenithium to transmit telemetry or biometric data over the internet.</p>
      </article>

      <article class="panel" style="padding:20px;">
        <span class="eyebrow">03 · Analitik ve Çerezler</span>
        <h3 style="font-size:1.15rem; margin:6px 0 10px; color:var(--text);">Sıfır Telemetri ve İzleme</h3>
        <p style="color:var(--dim); font-size:0.92rem; line-height:1.6;">Uygulama ve bu tanıtım sitesi; Google Analytics, Meta Pixel, Firebase, Crashlytics veya çerez kullanmaz. Ziyaretçilerin IP adresleri saklanmaz veya profillenmez.</p>
        <p style="color:var(--faint); font-size:0.85rem; margin-top:8px; line-height:1.5;"><em>English:</em> We do not employ tracking pixels, cookies, crash reporting frameworks, or behavioral analytics of any kind. Your identity and usage remain completely anonymous.</p>
      </article>

      <article class="panel" style="padding:20px;">
        <span class="eyebrow">04 · Veri Silme ve İhracat</span>
        <h3 style="font-size:1.15rem; margin:6px 0 10px; color:var(--text);">Tam Kullanıcı Kontrolü</h3>
        <p style="color:var(--dim); font-size:0.92rem; line-height:1.6;">Uygulamayı sildiğinizde, cihazda tutulan yerel hesaplama arşivi kalıcı olarak silinir. Apple Health'teki orijinal verileriniz korunur. Verilerini dışa aktarmak istediğinizde standart iOS paylaşım menüsü üzerinden .zenithium formatında tamamen sizin denetiminizde yedek alınır.</p>
        <p style="color:var(--faint); font-size:0.85rem; margin-top:8px; line-height:1.5;"><em>English:</em> Uninstalling Zenithium purges all local model parameters immediately. Data export is strictly user-driven via standard encrypted iOS share sheets.</p>
      </article>
    </div>

    <div style="margin-top:40px; padding:20px; background:var(--surface); border:1px solid var(--hairline); border-radius:4px; max-width:var(--measure);">
      <span class="eyebrow">İletişim · Contact</span>
      <p style="margin-top:6px; font-size:0.95rem; color:var(--text);">Gizlilikle ilgili tüm sorularınız için: <a href="mailto:hi@zenithium.app">hi@zenithium.app</a></p>
    </div>
  </section>
</main>
"""
    return page_layout(title, desc, url, "privacy", content)

# ── 3. SUPPORT.HTML İÇERİĞİ ─────────────────────────────────────────
def build_support():
    title = "Zenithium — Destek ve Kılavuz"
    desc = "Zenithium için sıkça sorulan sorular, kalibrasyon davranışı, eksik gece modeli ve doğrudan geliştirici iletişimi."
    url = "https://projectcagla.github.io/zenithium/support.html"

    content = """
<div class="hero-band"><div class="wrap hero">
  <div class="hero-copy">
    <span class="eyebrow">Destek & Kılavuz · Support</span>
    <h1>Bir sorun mu var,<br><em>yoksa bilerek mi öyle?</em></h1>
    <p class="lede">Zenithium'un bazı davranışları ilk bakışta eksiklik gibi görünebilir; ancak hepsi sahte veriyi engellemek için <strong>kasıtlı olarak</strong> tasarlanmıştır. Aşağıdaki kılavuz en sık karşılaşılan durumları açıklar.</p>
    <div class="hero-cta">
      <a class="btn solid" href="mailto:hi@zenithium.app">Doğrudan İletişim</a>
      <a class="btn" href="https://github.com/projectcagla/zenithium/issues">GitHub Sorun Bildir</a>
    </div>
  </div>
</div></div>

<main class="wrap">
  <section style="border-top:0;">
    <div class="sec-head">
      <span class="eyebrow">Sıkça Sorulan Sorular</span>
      <h2>Fizyolojik Karar Davranışı</h2>
    </div>

    <div style="display:grid; gap:20px; max-width:var(--measure);">

      <!-- Şartname Gereği Eklenen Yeni SSS: Skor Vermeme / Kalibrasyon -->
      <div class="panel" style="padding:20px;">
        <span class="eyebrow" style="color:var(--moderate)">En Çok Sorulan</span>
        <h3 style="font-size:1.15rem; margin:6px 0 10px; color:var(--text);">Uygulama neden bazı günler toparlanma skoru vermiyor?</h3>
        <p style="color:var(--dim); font-size:0.92rem; line-height:1.6;">Zenithium uydurma veri üretmez. Eğer o gece Apple Watch takılmadıysa veya optik sensör yeterli HRV/nabız kaydı alamadıysa uygulama skor tahmin etmez. Olmayan bir ölçümün yerine tahmini skor koymak bilimsel güvenilirliği sıfırlardı. Bu günlerde sistem "Eksik Gece Biyometrisi" uyarısı verir ve taban çizgisi hesaplamasını korur.</p>
      </div>

      <div class="panel" style="padding:20px;">
        <span class="eyebrow">Kalibrasyon Dönemi</span>
        <h3 style="font-size:1.15rem; margin:6px 0 10px; color:var(--text);">İlk günlerde skor neden değişken veya kısıtlı?</h3>
        <p style="color:var(--dim); font-size:0.92rem; line-height:1.6;">Her bireyin otonom sinir sistemi benzersizdir. Bir sporcuda 45 ms HRV toparlanma anlamına gelirken, bir diğerinde aşırı yorgunluk işaretidir. Bireysel taban aralığının (normal dağılım bandının) oturması için en az 14 gecelik sürekli ölçüm gereklidir. Kalibrasyon süresince öneriler düşük güven katsayısıyla verilir.</p>
      </div>

      <div class="panel" style="padding:20px;">
        <span class="eyebrow">Öneri Dili</span>
        <h3 style="font-size:1.15rem; margin:6px 0 10px; color:var(--text);">Neden bazı öneriler emir kipi ("yap") yerine "düşünebilirsin" diyor?</h3>
        <p style="color:var(--dim); font-size:0.92rem; line-height:1.6;">Bir tavsiyenin ne kadar iddialı olabileceğini arkasındaki akademik çalışmanın kanıt gücü belirler. Eğer dayanak alınan literatür (örneğin Plews 2013) tekil gün sapmalarında kesin hüküm vermiyorsa, Zenithium kullanıcıya yapay kesinlik satmaz; sınırları korur.</p>
      </div>

      <div class="panel" style="padding:20px;">
        <span class="eyebrow">Tahlil Entegrasyonu</span>
        <h3 style="font-size:1.15rem; margin:6px 0 10px; color:var(--text);">Kan tahlilim neden klinik olarak teşhis edilmiyor?</h3>
        <p style="color:var(--dim); font-size:0.92rem; line-height:1.6;">Zenithium bir teşhis cihazı değildir. Tahlil modülü yalnızca belirteçlerin sporcu referans aralıklarındaki konumunu ve antrenman yüküyle olan kinetiğini gösterir. Anormal değerlerin klinik değerlendirmesi daima hekiminiz tarafından yapılmalıdır.</p>
      </div>

      <div class="panel" style="padding:20px;">
        <span class="eyebrow">Yapay Zekâ ve Sohbet</span>
        <h3 style="font-size:1.15rem; margin:6px 0 10px; color:var(--text);">Neden serbest sohbet edebileceğim bir yapay zekâ botu yok?</h3>
        <p style="color:var(--dim); font-size:0.92rem; line-height:1.6;">Büyük dil modelleri (LLM) biyometrik veride halüsinasyon görmeye ve tutarsız tavsiyeler üretmeye yatkındır. Zenithium deterministik bir matematik motoruyla çalışır; aynı biyometrik girdi her zaman aynı şeffaf kanıt zincirini üretir.</p>
      </div>

    </div>

    <!-- İletişim Bloğu -->
    <div style="margin-top:40px; padding:24px; background:var(--surface); border:1px solid var(--hairline); border-radius:4px; max-width:var(--measure);">
      <span class="eyebrow">Doğrudan Geliştiriciye</span>
      <h3 style="font-size:1.15rem; margin:8px 0 12px; color:var(--text);">Sorunuzun cevabını bulamadınız mı?</h3>
      <p style="color:var(--dim); font-size:0.92rem; line-height:1.6;">Hata bildirimleri, metodoloji soruları veya geri bildirimleriniz için doğrudan e-posta gönderebilirsiniz:</p>
      <p style="margin-top:12px;"><a class="btn solid" href="mailto:hi@zenithium.app">hi@zenithium.app</a></p>
      <p style="margin-top:12px; font-size:0.8rem; color:var(--faint);">Cihaz modelinizi, watchOS ve iOS sürümünüzü belirtmeniz incelemeyi hızlandırır.</p>
    </div>
  </section>
</main>
"""
    return page_layout(title, desc, url, "support", content)

# ── 4. DERLEME VE KONTROL ───────────────────────────────────────────
def main():
    check_mode = "--check" in sys.argv

    pages = {
        "index.html": build_index(),
        "privacy.html": build_privacy(),
        "support.html": build_support(),
    }

    if check_mode:
        mismatches = []
        for filename, generated_html in pages.items():
            path = os.path.join(DOCS, filename)
            if not os.path.exists(path):
                mismatches.append(f"{filename} diskte yok!")
                continue
            with open(path, "r", encoding="utf-8") as f:
                disk_html = f.read()
            if disk_html.strip() != generated_html.strip():
                diff = difflib.unified_diff(
                    disk_html.strip().splitlines()[:20],
                    generated_html.strip().splitlines()[:20],
                    fromfile=f"disk/{filename}",
                    tofile=f"gen/{filename}"
                )
                mismatches.append(f"{filename} üretici çıktısıyla uyuşmuyor!\n" + "\n".join(diff))

        if mismatches:
            print("\033[31mHATA: Tanıtım sitesi dosyaları Scripts/gen-site.py ile uyuşmuyor!\033[0m")
            for m in mismatches:
                print(m)
            sys.exit(1)
        else:
            print("\033[32mOK\033[0m    docs/ HTML dosyaları Scripts/gen-site.py ile birebir tutarlı (0 sapma).")
            sys.exit(0)

    # Normal mod: Dosyaları yaz
    os.makedirs(DOCS, exist_ok=True)
    for filename, html in pages.items():
        path = os.path.join(DOCS, filename)
        with open(path, "w", encoding="utf-8") as f:
            f.write(html)
        print(f"Üretildi: {path} ({len(html.encode('utf-8')) / 1024:.1f} KB)")

if __name__ == "__main__":
    main()
