"""
Guardian SOS - bracket fix v2
Run from C:\\dev\\guardian_sos:
    python fix_bracket2.py
"""

import shutil
from datetime import datetime

TARGET = 'lib/main.dart'

with open(TARGET, 'r', encoding='utf-8') as f:
    lines = f.readlines()

backup = f'lib/main.dart.bak.{datetime.now().strftime("%Y%m%d_%H%M%S")}'
shutil.copy(TARGET, backup)
print(f'Backup saved to {backup}')

# From the diagnostic output we know:
# Line 854 (index 853): child: SingleChildScrollView(
# Line 911 (index 910): ),       <-- this closes SafeArea, but needs to also close SingleChildScrollView first
# Line 912 (index 911): );       <-- closes Scaffold
# Line 913 (index 912):   }
# Line 914 (index 913): }
# Line 915 (index 914): (blank)
# Line 916 (index 915): // TRIAL EXPIRED SCREEN comment

# We need to insert an extra '),' before line 911 (index 910)
# BUT only in the registration screen, not elsewhere.
# We find the SingleChildScrollView in the registration screen (before line 920)
# then find its closing area.

# Strategy: find line index 853 (0-based) which has SingleChildScrollView
# then scan forward for the closing pattern:
#   '      ),\n'   (6 spaces - closes SafeArea)
#   '    );\n'     (4 spaces - closes Scaffold body)
# and insert '        ),\n' before it (8 spaces - closes SingleChildScrollView)

scv_index = None
for i, line in enumerate(lines):
    if 'SingleChildScrollView' in line and i < 920:
        scv_index = i
        print(f'Found SingleChildScrollView at line {i+1}')
        break

if scv_index is None:
    print('ERROR: SingleChildScrollView not found')
    exit(1)

# Scan forward for the closing of the registration class
# Look for the exact sequence:
#   line N:   '      ),\n'
#   line N+1: '    );\n'  
#   line N+2: '  }\n'
#   line N+3: '}\n'

insert_at = None
for i in range(scv_index, min(len(lines), scv_index + 100)):
    if (lines[i] == '      ),\n' and
        i+1 < len(lines) and lines[i+1] == '    );\n' and
        i+2 < len(lines) and lines[i+2] == '  }\n' and
        i+3 < len(lines) and lines[i+3] == '}\n'):
        insert_at = i
        print(f'Found closing sequence at line {i+1}')
        break

if insert_at is None:
    print('ERROR: Could not find closing sequence. Lines around end of class:')
    for i in range(905, min(len(lines), 920)):
        print(f'  {i+1}: {repr(lines[i])}')
    exit(1)

# Insert the closing ) for SingleChildScrollView
lines.insert(insert_at, '        ),\n')
print(f'Inserted closing ) at line {insert_at+1}')

with open(TARGET, 'w', encoding='utf-8') as f:
    f.writelines(lines)

print('\nFixed! Run: flutter run --flavor adventure')
