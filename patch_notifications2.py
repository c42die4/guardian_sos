"""
Guardian SOS - notification fix v2 (line-based)
Run from C:\\dev\\guardian_sos:
    python patch_notifications2.py

Fixes:
  1. Strip emoji from action button labels (lines 85, 91)
  2. Add phone param to showAlertNotification (lines 80-81)
  3. Add CALL RIDER action button
  4. Handle CALL action in _handleNotificationAction
"""

import shutil
from datetime import datetime

TARGET = 'lib/main.dart'

with open(TARGET, 'r', encoding='utf-8') as f:
    lines = f.readlines()

backup = f'lib/main.dart.bak.{datetime.now().strftime("%Y%m%d_%H%M%S")}'
shutil.copy(TARGET, backup)
print(f'Backup saved to {backup}')

patches = 0

# ─────────────────────────────────────────────────────────────────
# 1. Fix showAlertNotification signature (line 81, index 80)
#    Add phone parameter
# ─────────────────────────────────────────────────────────────────
idx = 80  # line 81, 0-based index 80
if '    {int notificationId = 0, String? alertId}) async {' in lines[idx]:
    lines[idx] = '    {int notificationId = 0, String? alertId, String? phone}) async {\n'
    print('  [OK] Added phone param to showAlertNotification signature')
    patches += 1
else:
    print(f'  [SKIP] showAlertNotification signature — line 81 content unexpected: {repr(lines[idx][:60])}')

# ─────────────────────────────────────────────────────────────────
# 2. Fix action labels - strip emoji (lines 85, 91 — indices 84, 90)
# ─────────────────────────────────────────────────────────────────
idx84 = 84  # line 85
if 'RESPONDING' in lines[idx84]:
    lines[idx84] = "      'RESPONDING',\n"
    print('  [OK] Stripped emoji from RESPONDING label')
    patches += 1
else:
    print(f'  [SKIP] RESPONDING label — unexpected: {repr(lines[idx84][:60])}')

idx90 = 90  # line 91
if 'REMIND IN 10 MIN' in lines[idx90]:
    lines[idx90] = "      'REMIND IN 10 MIN',\n"
    print('  [OK] Stripped emoji from REMIND IN 10 MIN label')
    patches += 1
else:
    print(f'  [SKIP] REMIND label — unexpected: {repr(lines[idx90][:60])}')

# ─────────────────────────────────────────────────────────────────
# 3. Add CALL RIDER action before RESPONDING action (after line 82, index 81)
#    line 82 = '  final List<AndroidNotificationAction> actions = ['
#    line 83 = '    const AndroidNotificationAction('   <- RESPONDING starts here
# We insert the CALL block between lines 82 and 83
# ─────────────────────────────────────────────────────────────────
idx82 = 81  # line 82 (0-based)
if 'List<AndroidNotificationAction> actions' in lines[idx82]:
    call_block = (
        "    if (phone != null && phone.isNotEmpty)\n"
        "      AndroidNotificationAction(\n"
        "        'call_$phone',\n"
        "        'CALL RIDER',\n"
        "        showsUserInterface: true,\n"
        "        cancelNotification: false,\n"
        "      ),\n"
    )
    lines.insert(idx82 + 1, call_block)
    print('  [OK] Added CALL RIDER action block')
    patches += 1
else:
    print(f'  [SKIP] CALL RIDER insert — unexpected line 82: {repr(lines[idx82][:60])}')

# ─────────────────────────────────────────────────────────────────
# 4. Handle CALL action in _handleNotificationAction (line 41, index 40)
#    Current: if (actionId == 'responding') {
#    Insert CALL handler before it
# ─────────────────────────────────────────────────────────────────
# After the insert above, line numbers shifted by 1 for everything after line 82
# Line 41 (index 40) is BEFORE line 82, so no shift needed
idx40 = 40  # line 41
if "actionId == 'responding'" in lines[idx40]:
    call_handler = (
        "  if (actionId != null && actionId.startsWith('call_')) {\n"
        "    final number = actionId.substring(5);\n"
        "    // Launch dialer — needs to be handled in UI context\n"
        "    // Store for AppShell to pick up\n"
        "    _pendingCallNumber = number;\n"
        "    return;\n"
        "  }\n"
    )
    lines.insert(idx40, call_handler)
    print('  [OK] Added CALL action handler')
    patches += 1
else:
    print(f'  [SKIP] CALL handler insert — unexpected line 41: {repr(lines[idx40][:60])}')

# ─────────────────────────────────────────────────────────────────
# 5. Add _pendingCallNumber global variable near top
#    Find 'void _handleNotificationAction' and add above it
# ─────────────────────────────────────────────────────────────────
found_handle = False
for i, line in enumerate(lines):
    if 'void _handleNotificationAction' in line:
        lines.insert(i, 'String? _pendingCallNumber;\n\n')
        print('  [OK] Added _pendingCallNumber global')
        patches += 1
        found_handle = True
        break
if not found_handle:
    print('  [SKIP] _pendingCallNumber — _handleNotificationAction not found')

with open(TARGET, 'w', encoding='utf-8') as f:
    f.writelines(lines)

print(f'\n{patches} patches applied.')
print('\nNext steps:')
print('  git add lib/main.dart')
print('  git commit -m "Fix notification emoji, add CALL RIDER button"')
print('  git push')
