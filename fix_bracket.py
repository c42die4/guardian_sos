"""
Guardian SOS - bracket fix
Run from C:\\dev\\guardian_sos:
    python fix_bracket.py

Fixes the unmatched parenthesis at line 851 caused by the
SingleChildScrollView wrapper missing its closing bracket.
"""

import shutil
from datetime import datetime

TARGET = 'lib/main.dart'

with open(TARGET, 'r', encoding='utf-8') as f:
    src = f.read()

backup = f'lib/main.dart.bak.{datetime.now().strftime("%Y%m%d_%H%M%S")}'
shutil.copy(TARGET, backup)
print(f'Backup saved to {backup}')

# The registration screen was wrapped in SingleChildScrollView but
# is missing the closing ) for it. Find the exact closing sequence
# and add the missing paren.

# Pattern: end of the registration screen Column children, before TRIAL EXPIRED SCREEN comment
# We look for the unique sequence that closes the Scaffold in that specific screen

found = False

# Try several possible closing patterns to find which one is in this file
candidates = [
    (
        "            ],\n          ),\n        ),\n      ),\n    );\n  }\n}\n\n// ",
        "            ],\n          ),\n        ),\n        ),\n      ),\n    );\n  }\n}\n\n// "
    ),
    (
        "            ],\n          ),\n        ),\n      ),\n    );\n  }\n}\r\n\r\n// ",
        "            ],\n          ),\n        ),\n        ),\n      ),\n    );\n  }\n}\r\n\r\n// "
    ),
]

for old, new in candidates:
    count = src.count(old)
    if count == 1:
        src = src.replace(old, new, 1)
        print("Found and fixed closing bracket pattern.")
        found = True
        break
    elif count > 1:
        print(f"Pattern found {count} times — too ambiguous, trying next...")

if not found:
    # Fallback: search around line 851 area by finding SingleChildScrollView
    # and counting bracket balance
    print("Standard patterns not found. Trying line-based fix...")
    lines = src.split('\n')
    
    # Find the SingleChildScrollView line
    scv_line = None
    for i, line in enumerate(lines):
        if 'SingleChildScrollView' in line and i < 950:
            scv_line = i
            print(f"  Found SingleChildScrollView at line {i+1}: {line.strip()}")
            break
    
    if scv_line is None:
        print("ERROR: Could not find SingleChildScrollView. The overflow fix may not have been applied.")
        print("Please share the output of: python fix_bracket.py")
    else:
        # Find the closing of the Scaffold.body after the SingleChildScrollView
        # by looking for the pattern:  ),\n      ),\n    );\n  }\n}
        # and inserting an extra ),  before the SafeArea closing
        
        # Print lines around the suspected problem area for diagnosis
        print(f"\nLines {scv_line-2} to {scv_line+5}:")
        for i in range(max(0, scv_line-2), min(len(lines), scv_line+6)):
            print(f"  {i+1}: {lines[i]}")
        
        # Find the end of the registration class (next class definition)
        end_line = None
        for i in range(scv_line, min(len(lines), scv_line+200)):
            if lines[i].strip().startswith('class ') and i > scv_line + 10:
                end_line = i
                break
        
        if end_line:
            print(f"\nLines {end_line-8} to {end_line+1} (end of registration class):")
            for i in range(max(0, end_line-8), end_line+1):
                print(f"  {i+1}: {lines[i]}")
        
        print("\nCould not auto-fix. Please paste the output above so we can target precisely.")
        import sys; sys.exit(1)

with open(TARGET, 'w', encoding='utf-8') as f:
    f.write(src)

print(f'\nDone. Run: flutter run --flavor adventure')
