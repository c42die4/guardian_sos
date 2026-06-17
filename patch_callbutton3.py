"""
Guardian SOS - Add CALL RIDER button (line-based v3)
Run from C:\\dev\\guardian_sos:
    python patch_callbutton3.py
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

# Find the SizedBox(height:12) that is immediately followed by
# a Row containing NAVIGATE — search for NAVIGATE then look back
navigate_idx = None
for i, line in enumerate(lines):
    if '"NAVIGATE"' in line:
        # Look back up to 10 lines for SizedBox(height: 12)
        for j in range(i, max(0, i-10), -1):
            if 'SizedBox(height: 12)' in lines[j]:
                navigate_idx = j
                break
        if navigate_idx is not None:
            break

if navigate_idx is not None:
    print(f'  Found SizedBox(height:12) before NAVIGATE at line {navigate_idx+1}: {repr(lines[navigate_idx].rstrip())}')

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

    lines[navigate_idx] = call_block
    print('  [OK] Added CALL RIDER button before NAVIGATE row')
    patches += 1
else:
    print('  [SKIP] Could not find SizedBox(height:12) before NAVIGATE')

with open(TARGET, 'w', encoding='utf-8') as f:
    f.writelines(lines)

print(f'\n{patches} patches applied.')
print('\nNext steps:')
print('  flutter run --flavor adventure')
print('  git add lib/main.dart')
print('  git commit -m "Add CALL RIDER button to alert panel"')
print('  git push')
