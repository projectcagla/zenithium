#!/usr/bin/env bash
# Everything that can be checked without a Swift compiler, in one command.
#
# Run before `xcodegen generate && xcodebuild`. None of this replaces a build — see the
# note at the bottom — but each check covers a failure a build would find late, or one a
# build would not find at all because it only breaks a target nobody compiled that day.
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 1

failed=0
run() {
    printf '\n\033[1m── %s\033[0m\n' "$1"
    shift
    if ! "$@"; then failed=1; fi
}

run "Yapılandırma tutarlılığı"  python3 Scripts/check-target-sources.py
run "Sembol çözümlemesi"        python3 Scripts/check-symbols.py
run "Gizlilik bildirimi"        python3 Scripts/check-privacy-manifest.py
run "Varlık kataloğu"           python3 Scripts/check-assets.py
run "Xcode projesi"             python3 Scripts/generate-project.py
# After generating, not before: this reads what was just written. The project shipped in
# v0.1 was one Xcode refused to open at all, and nothing in the repository disagreed with
# itself about it — XcodeGen quotes correctly, so only the checked-in file was broken.
run "Bilimsel kaynaklar"      python3 Scripts/check-citations.py
run "Proje dosyası çözümlemesi" python3 Scripts/check-pbxproj.py

printf '\n'
if [ "$failed" -eq 0 ]; then
    printf '\033[32mHepsi temiz.\033[0m Derlemeye hazır sayılabilecek her şey kontrol edildi.\n'
    printf 'Sonraki adım gerçek derleme:\n'
    printf '    xcodebuild -project Zenithium.xcodeproj -scheme Zenithium \\\n'
    printf '               -destination "platform=iOS Simulator,name=iPhone 16 Pro" build\n'
else
    printf '\033[31mSorun var.\033[0m Yukarıdaki çıktıya bak.\n'
fi
exit "$failed"
