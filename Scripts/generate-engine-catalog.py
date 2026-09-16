#!/usr/bin/env python3
"""Keep README's inventory derived from engine declarations, never a second manual list."""
from pathlib import Path
import re
root = Path(__file__).resolve().parent.parent
rows = []
for path in sorted((root / 'Zenithium/Engines').glob('*Engine.swift')):
    source = path.read_text()
    if not re.search(r'\benum\s+' + re.escape(path.stem) + r'\b', source):
        continue
    entries = list(dict.fromkeys(re.findall(r'^    static func (\w+)\s*\(', source, re.M)))
    link = path.relative_to(root).as_posix()
    rows.append(f'| [{path.stem}]({link}) | ' + ', '.join(f'`{x}`' for x in entries) + ' |')
block = f'Kodda **{len(rows)} hesap modülü** var.\n\n| Modül | Kaynaktaki giriş noktaları |\n|---|---|\n' + '\n'.join(rows)
readme = root / 'README.md'
text = readme.read_text()
text = re.sub(r'<!-- ENGINE-CATALOG:START -->.*?<!-- ENGINE-CATALOG:END -->',
              '<!-- ENGINE-CATALOG:START -->\n' + block + '\n<!-- ENGINE-CATALOG:END -->', text, flags=re.S)
readme.write_text(text)
print(f'{len(rows)} engine declarations synchronized to README.')
