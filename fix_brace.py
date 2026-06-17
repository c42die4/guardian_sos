"""
Guardian SOS - fix missing closing brace
Run from C:\\dev\\guardian_sos:
    python fix_brace.py
"""
import shutil
from datetime import datetime

TARGET = 'lib/main.dart'

with open(TARGET, 'r', encoding='utf-8') as f:
    lines = f.readlines()

backup = f'lib/main.dart.bak.{datetime.now().strftime("%Y%m%d_%H%M%S")}'
shutil.copy(TARGET, backup)

# Line 57 (index 56) is '}\n' — the if block close
# We need to add '}\n' after it to close _handleNotificationAction
for i, line in enumerate(lines):
    if i == 56 and line.strip() == '}':
        lines.insert(i + 1, '}\n')
        print(f'  [OK] Inserted closing brace for _handleNotificationAction after line {i+1}')
        break

with open(TARGET, 'w', encoding='utf-8') as f:
    f.writelines(lines)

print('Done. Run: flutter run --flavor adventure')
