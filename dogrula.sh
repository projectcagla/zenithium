#!/bin/bash
# Sunum kapsamı ve kaynak denetimi. --swift: Xcode derlemesi olmadan üç hedefin tür denetimi.
set -euo pipefail
cd -- "$(dirname -- "$0")"
python3 - "$@" <<'PY'
from pathlib import Path
import json, re, subprocess, sys, tempfile
root = Path.cwd()
base = '6310c9c'
def git(*args):
    return subprocess.check_output(['git', *args], cwd=root, text=True).strip()
def require(ok, message):
    if not ok:
        raise SystemExit('BAŞARISIZ: ' + message)
    print('GEÇTİ: ' + message)
require(git('branch', '--show-current') == 'design/astra', 'design/astra dalı')
changed = set(git('diff', '--name-only', base).splitlines())
changed.update(git('ls-files', '--others', '--exclude-standard').splitlines())
existing = {'Zenithium.xcodeproj/project.xcworkspace/contents.xcworkspacedata'}
allowed = ('Zenithium/Views/', 'Zenithium/Resources/', 'ZenithiumWatch/', 'ZenithiumWidgets/')
require(all(p in existing or p == 'dogrula.sh' or p.startswith(allowed) for p in changed), 'Yalnızca yetkili sunum dosyaları ve dogrula.sh')
protected = ['Zenithium/Engines', 'Zenithium/Models', 'Zenithium/Persistence', 'Zenithium/Health', 'Zenithium/Domain', 'Zenithium/Orchestration', 'Zenithium/ViewModels', 'ZenithiumTests', 'project.yml', 'Zenithium.xcodeproj/project.pbxproj']
require(not git('diff', base, '--', *protected), 'Motorlar, modeller, veri katmanı, testler ve proje yapılandırması değişmedi')
hub = 'Zenithium/Views/DesignSystem/HubView.swift'
require((root/hub).read_text() == git('show', f'{base}:{hub}')+'\n', '15 HubDestination ve erişim kuralları korundu')
expected = {'Today/TodayView':1, 'Sleep/SleepView':1, 'Load/TrainingLoadView':1, 'Trends/TrendsView':0, 'Muscle/MuscleMapView':1, 'Bloodwork/BloodworkView':1, 'Today/ReasonView':0}
for view, count in expected.items():
    path = f'Zenithium/Views/{view}.swift'
    text = (root/path).read_text()
    before = len(re.findall(r'\bSectionCard\s*(?:\(|\{)', git('show', f'{base}:{path}')))
    now = len(re.findall(r'\bSectionCard\s*(?:\(|\{)', text))
    require(now == count, f'{view}: SectionCard {before} → {now}')
    require('accessibilityReduceMotion' in text, f'{view}: azaltılmış hareket desteği')
for path in sorted(changed):
    if not path.endswith('.swift') or not path.startswith(allowed): continue
    text = (root/path).read_text()
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'(?m)^\s*//.*$', '', text)
    forbidden = re.search(r'\b(?:URLSession|NWConnection|Combine|DispatchQueue)\b|\bprint\s*\(|\b(?:try|as)\s*!|[\w\]\)]!(?!=)', text)
    require(forbidden is None, f'{path}: ağ, Combine, DispatchQueue, print ve zorla açma yok')
    require('.shadow(' not in text, f'{path}: gölge yok')
for path in (root/'Zenithium/Resources').rglob('Contents.json'):
    json.loads(path.read_text())
require(True, 'Kaynak kataloglarının JSON yapısı')
for script in ['check-assets.py', 'check-pbxproj.py', 'check-target-sources.py', 'check-privacy-manifest.py']:
    subprocess.run([sys.executable, str(root/'Scripts'/script)], check=True, cwd=root)
subprocess.run(['git','diff','--check',base],check=True,cwd=root)
print('NOT: Önceden mevcut çalışma alanı dosyası değişikliği bu teslimata dahil değildir.')
print('NOT: Kaynak taraması, çalışma zamanı veya görsel doğrulamanın yerine geçmez.')
if '--swift' in sys.argv:
    lines = (root/'project.yml').read_text().splitlines()
    def sources(target):
        inside = False
        in_sources = False
        found = set()
        for line in lines:
            if re.match(rf'^  {re.escape(target)}:\s*$', line):
                inside = True; continue
            if inside and re.match(r'^  \S', line): break
            if inside and re.match(r'^    sources:\s*$', line):
                in_sources = True; continue
            if in_sources:
                match = re.match(r'^      - path:\s*(\S+)',line)
                if match:
                    path = root/match.group(1)
                    if path.is_dir(): found.update(path.rglob('*.swift'))
                    elif path.suffix == '.swift': found.add(path)
                elif re.match(r'^    \S',line): in_sources = False
        return sorted(map(str,found))
    with tempfile.TemporaryDirectory(prefix='zenithium-astra-') as tmp:
        for target, sdk_name, triple in [('Zenithium','iphoneos','arm64-apple-ios18.0'), ('ZenithiumWidgets','iphoneos','arm64-apple-ios18.0'), ('ZenithiumWatch','watchos','arm64_32-apple-watchos11.0')]:
            sdk = subprocess.check_output(['xcrun','--sdk',sdk_name,'--show-sdk-path'],text=True).strip()
            command = ['xcrun','swiftc','-typecheck','-swift-version','6','-strict-concurrency=complete','-module-name',target,'-target',triple,'-sdk',sdk,'-module-cache-path',tmp+'/modules'] + sources(target)
            subprocess.run(command,check=True,cwd=root)
            print(f'GEÇTİ: {target}, Swift 6 strict concurrency tür denetimi')
        print('NOT: xcodebuild, preflight, simülatör ve ekran görüntüsü kullanılmadı. Testler çalıştırılmadı.')
PY
