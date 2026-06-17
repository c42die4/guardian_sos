"""
Guardian SOS - Call button + remind fix v2 (line-based)
Run from C:\\dev\\guardian_sos:
    python patch_callbutton2.py
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
# 1. Remove remind_10 handler (lines 57-59, indices 56-58)
#    Line 57: '  } else if (actionId == 'remind_10') {'
#    Line 58: ''  (blank or comment)
#    Line 59: '    SOSEscalationManager.snoozeEscalation(...)'
#    Line 60: '  }'
# We need to find and remove the else-if block cleanly
# ─────────────────────────────────────────────────────────────────
remind_start = None
for i, line in enumerate(lines):
    if "actionId == 'remind_10'" in line:
        remind_start = i
        break

if remind_start is not None:
    # Find the closing } of this else-if block
    # Pattern: line i = } else if...
    #          line i+1 = blank or comment
    #          line i+2 = snoozeEscalation
    #          line i+3 = }  <- remove up to here
    # Replace the whole else-if with nothing
    end = remind_start
    # Find the closing brace
    for j in range(remind_start, min(len(lines), remind_start + 6)):
        if lines[j].strip() == '}' and j > remind_start:
            end = j
            break
    
    print(f'  Found remind_10 block at lines {remind_start+1}-{end+1}:')
    for k in range(remind_start, end+1):
        print(f'    {k+1}: {repr(lines[k].rstrip())}')
    
    # Remove lines from remind_start to end inclusive
    del lines[remind_start:end+1]
    print(f'  [OK] Removed remind_10 handler ({end - remind_start + 1} lines deleted)')
    patches += 1
else:
    print('  [SKIP] remind_10 handler — not found')

# ─────────────────────────────────────────────────────────────────
# 2. Add CALL RIDER button before the NAVIGATE row
#    Find the SizedBox(height: 12) that precedes the NAVIGATE row
#    by looking for the NAVIGATE button nearby
# ─────────────────────────────────────────────────────────────────
navigate_line = None
for i, line in enumerate(lines):
    if 'NAVIGATE' in line and 'Colors.blue' in lines[min(i+3, len(lines)-1)]:
        # Go back to find the SizedBox(height: 12) before this Row
        for j in range(i, max(0, i-10), -1):
            if 'SizedBox(height: 12)' in lines[j]:
                navigate_line = j
                break
        if navigate_line is not None:
            break

if navigate_line is not None:
    print(f'  Found SizedBox(height:12) before NAVIGATE at line {navigate_line+1}')
    
    call_block = (
        '                            const SizedBox(height: 12),\n'
        '                            Builder(builder: (context) {\n'
        '                              final phone = (_selectedAlert![\'mobilePhone\'] ?? \'\').toString().trim();\n'
        '                              if (phone.isEmpty) return const SizedBox.shrink();\n'
        '                              return Padding(\n'
        '                                padding: const EdgeInsets.only(bottom: 8),\n'
        '                                child: SizedBox(\n'
        '                                  width: double.infinity,\n'
        '                                  child: ElevatedButton.icon(\n'
        '                                    icon: const Icon(Icons.phone, color: Colors.white),\n'
        '                                    label: Text(\n'
        '                                      \'CALL RIDER  \u2014  $phone\',\n'
        '                                      style: const TextStyle(\n'
        '                                          color: Colors.white,\n'
        '                                          fontWeight: FontWeight.bold,\n'
        '                                          fontSize: 15),\n'
        '                                    ),\n'
        '                                    style: ElevatedButton.styleFrom(\n'
        '                                        backgroundColor: Colors.green[700],\n'
        '                                        padding: const EdgeInsets.all(14)),\n'
        '                                    onPressed: () async {\n'
        '                                      final uri = Uri(scheme: \'tel\', path: phone);\n'
        '                                      if (await canLaunchUrl(uri)) {\n'
        '                                        await launchUrl(uri);\n'
        '                                      }\n'
        '                                    },\n'
        '                                  ),\n'
        '                                ),\n'
        '                              );\n'
        '                            }),\n'
    )
    
    # Replace the SizedBox(height:12) line with call block
    # (the call block already includes the SizedBox(height:12))
    lines[navigate_line] = call_block
    print('  [OK] Added CALL RIDER button before NAVIGATE row')
    patches += 1
else:
    print('  [SKIP] NAVIGATE row anchor not found')

# ─────────────────────────────────────────────────────────────────
# Write output
# ─────────────────────────────────────────────────────────────────
with open(TARGET, 'w', encoding='utf-8') as f:
    f.writelines(lines)

print(f'\n{patches} patches applied.')
print('\nNext steps:')
print('  flutter run --flavor adventure')
print('  git add lib/main.dart')
print('  git commit -m "Add CALL RIDER button, remove REMIND IN 10 MIN"')
print('  git push')
