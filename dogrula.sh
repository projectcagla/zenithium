#!/bin/bash
# --swift: Debug/Release tür denetimi. --compile: nesne/modül üretimi ve test kaynak denetimi.
# --tests: yalnızca Debug uygulama modülü ve test kaynaklarının tür denetimi.
# İki seçenek de xcodebuild, simülatör, imzalama veya test çalıştırması yapmaz.
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
if any(flag in sys.argv for flag in ['--swift', '--compile', '--tests']):
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
        result = sorted(map(str,found))
        require(bool(result), f'{target}: proje tanımından kaynaklar bulundu')
        return result
    with tempfile.TemporaryDirectory(prefix='zenithium-astra-') as tmp:
        compile_sources = '--compile' in sys.argv
        tests_only = '--tests' in sys.argv and not compile_sources
        for target, sdk_name, triple in [('Zenithium','iphoneos','arm64-apple-ios18.0'), ('ZenithiumWidgets','iphoneos','arm64-apple-ios18.0'), ('ZenithiumWatch','watchos','arm64_32-apple-watchos11.0')]:
            if tests_only and target != 'Zenithium': continue
            sdk = subprocess.check_output(['xcrun','--sdk',sdk_name,'--show-sdk-path'],text=True).strip()
            inputs = sources(target)
            for configuration in (['Debug'] if tests_only else ['Debug', 'Release']):
                output = Path(tmp)/configuration
                output.mkdir(exist_ok=True)
                command = ['xcrun','swiftc','-swift-version','6','-strict-concurrency=complete',
                           '-enable-upcoming-feature','ExistentialAny','-parse-as-library',
                           '-module-name',target,'-target',triple,'-sdk',sdk,
                           '-module-cache-path',tmp+'/modules']
                if configuration == 'Debug':
                    command += ['-D','DEBUG','-Onone','-enable-testing']
                else:
                    command += ['-O','-warnings-as-errors']
                if target == 'ZenithiumWidgets':
                    command += ['-application-extension']
                if compile_sources:
                    command += ['-whole-module-optimization','-emit-object','-emit-module',
                                '-emit-module-path',str(output/(target+'.swiftmodule')),
                                '-o',str(output/(target+'.o'))]
                elif tests_only:
                    command += ['-emit-module','-emit-module-path',str(output/(target+'.swiftmodule'))]
                else:
                    command += ['-typecheck']
                print(f'DENETLENİYOR: {target} {configuration}', flush=True)
                subprocess.run(command+inputs,check=True,cwd=root)
                mode = 'nesne ve modül derlemesi' if compile_sources else ('modül derlemesi' if tests_only else 'tür denetimi')
                print(f'GEÇTİ: {target} {configuration}, Swift 6 strict concurrency {mode}', flush=True)
        if compile_sources or tests_only:
            sdk = subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
            platform = subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-platform-path'],text=True).strip()
            swiftc = Path(subprocess.check_output(['xcrun','--find','swiftc'],text=True).strip())
            plugins = swiftc.parent.parent/'lib/swift/host/plugins/testing'
            require((plugins/'libTestingMacros.dylib').is_file(), 'Swift Testing derleyici eklentisi bulundu')
            command = ['xcrun','swiftc','-typecheck','-swift-version','6','-strict-concurrency=complete',
                       '-enable-upcoming-feature','ExistentialAny','-D','DEBUG','-parse-as-library',
                       '-module-name','ZenithiumTests','-target','arm64-apple-ios18.0','-sdk',sdk,
                       '-I',tmp+'/Debug','-I',platform+'/Developer/usr/lib',
                       '-F',platform+'/Developer/Library/Frameworks',
                       '-plugin-path',str(plugins),
                       '-module-cache-path',tmp+'/modules']
            subprocess.run(command+sources('ZenithiumTests'),check=True,cwd=root)
            print('GEÇTİ: ZenithiumTests kaynaklarının Debug modülüyle tür denetimi', flush=True)
            print('NOT: Nesne/modül derlemesi; varlık derleme, bağlama, imzalama ve paketleme yapılmadı.')
        print('NOT: xcodebuild, preflight, simülatör ve ekran görüntüsü kullanılmadı. Testler çalıştırılmadı.')
PY
