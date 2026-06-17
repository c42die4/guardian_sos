"""
Guardian SOS - Fix Firebase web initialization
Run from C:\\dev\\guardian_sos:
    python patch_firebase_web.py
"""

import shutil
from datetime import datetime

TARGET = 'lib/main.dart'

with open(TARGET, 'r', encoding='utf-8') as f:
    src = f.read()

backup = f'lib/main.dart.bak.{datetime.now().strftime("%Y%m%d_%H%M%S")}'
shutil.copy(TARGET, backup)
print(f'Backup saved to {backup}')

patches = 0
errors = []

def patch(label, old, new):
    global src, patches
    count = src.count(old)
    if count == 0:
        errors.append(f'SKIP [{label}] — not found')
        return
    if count > 1:
        errors.append(f'WARN [{label}] — found {count} times, skipping')
        return
    src = src.replace(old, new, 1)
    patches += 1
    print(f'  [OK] {label}')

# Add firebase_options import
patch(
    'Add firebase_options import',
    """import 'package:firebase_core/firebase_core.dart';""",
    """import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';"""
)

# Fix main() Firebase init to use DefaultFirebaseOptions
patch(
    'Fix main() Firebase init with options',
    """  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase Init Error: $e");
  }""",
    """  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase Init Error: $e");
  }"""
)

with open(TARGET, 'w', encoding='utf-8') as f:
    f.write(src)

print(f'\n{patches} patches applied.')
if errors:
    print('\nNotes:')
    for e in errors:
        print(f'  {e}')

print('\nNext steps:')
print('  flutter build web')
print('  firebase deploy --only hosting')
