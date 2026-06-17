"""
Guardian SOS - fix wrong number being dialled
Run from C:\\dev\\guardian_sos:
    python patch_callfix.py

When officer taps PROFILE on an alert, the profile data comes from
the nested 'profile' map embedded in the alert document at creation time.
Old alerts won't have mobilePhone in that nested map.
This patch merges the top-level alert fields (mobilePhone, userName) into
the profile map before passing it to _showProfile, so the correct number
is always available.
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
        errors.append(f'SKIP [{label}] — not found (may already be applied)')
        return
    if count > 1:
        errors.append(f'WARN [{label}] — found {count} times, skipping')
        return
    src = src.replace(old, new, 1)
    patches += 1
    print(f'  [OK] {label}')

# ─────────────────────────────────────────────────────────────────
# When officer taps PROFILE, merge top-level alert fields into
# the nested profile map so mobilePhone is always present
# ─────────────────────────────────────────────────────────────────
patch(
    'Merge top-level mobilePhone into profile before _showProfile',
    """                                    onPressed: () {
                                      final profile = _selectedAlert!['profile'];
                                      if (profile != null) {
                                        _showProfile(context, Map<String, dynamic>.from(profile));
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text("No profile available.")));
                                      }
                                    },""",
    """                                    onPressed: () {
                                      final rawProfile = _selectedAlert!['profile'];
                                      if (rawProfile != null) {
                                        // Merge top-level alert fields into profile so
                                        // mobilePhone is available even on older alerts
                                        final merged = Map<String, dynamic>.from(rawProfile);
                                        if ((merged['mobilePhone'] ?? '').toString().isEmpty) {
                                          merged['mobilePhone'] = (_selectedAlert!['mobilePhone'] ?? '').toString();
                                        }
                                        if ((merged['email'] ?? '').toString().isEmpty) {
                                          merged['email'] = (_selectedAlert!['email'] ?? '').toString();
                                        }
                                        _showProfile(context, merged);
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text("No profile available.")));
                                      }
                                    },"""
)

# ─────────────────────────────────────────────────────────────────
# Also fix _playSiren call at line ~3077 which calls showAlertNotification
# without the new phone param — add it from latestData
# ─────────────────────────────────────────────────────────────────
patch(
    'Pass phone to showAlertNotification in _playSiren',
    """    showAlertNotification(
      latestData?['userName'] ?? 'Unknown',
      '${latestData?['lat']?.toStringAsFixed(4) ?? ''}, '
          '${latestData?['lng']?.toStringAsFixed(4) ?? ''}',
    );""",
    """    showAlertNotification(
      latestData?['userName'] ?? 'Unknown',
      '${latestData?['lat']?.toStringAsFixed(4) ?? ''}, '
          '${latestData?['lng']?.toStringAsFixed(4) ?? ''}',
      phone: (latestData?['mobilePhone'] ?? '').toString(),
    );"""
)

with open(TARGET, 'w', encoding='utf-8') as f:
    f.write(src)

print(f'\n{patches} patches applied.')
if errors:
    print('\nNotes:')
    for e in errors:
        print(f'  {e}')

print('\nNext steps:')
print('  git add lib/main.dart')
print('  git commit -m "Fix wrong number in call button, pass mobilePhone through alert chain"')
print('  git push')
