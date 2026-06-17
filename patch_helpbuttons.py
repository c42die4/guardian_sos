"""
Guardian SOS - Show help buttons for all flavors
Run from C:\\dev\\guardian_sos:
    python patch_helpbuttons.py
"""

import shutil
from datetime import datetime

TARGET = 'lib/main.dart'

with open(TARGET, 'r', encoding='utf-8') as f:
    src = f.read()

backup = f'lib/main.dart.bak.{datetime.now().strftime("%Y%m%d_%H%M%S")}'
shutil.copy(TARGET, backup)
print(f'Backup saved to {backup}')

old = "                  // Adventure mode help buttons\n                  if (widget.company.isAdventure) ...["
new = "                  // Help buttons — available for all company types\n                  ...["

count = src.count(old)
if count == 1:
    src = src.replace(old, new, 1)
    print('  [OK] Help buttons now show for all flavors')
else:
    print(f'  [SKIP] Pattern found {count} times — not found or ambiguous')

with open(TARGET, 'w', encoding='utf-8') as f:
    f.write(src)

print('\nNext steps:')
print('  flutter build apk --flavor highway_devils --release')
print('  Then share the APK from:')
print('  build\\app\\outputs\\flutter-apk\\app-highway_devils-release.apk')
