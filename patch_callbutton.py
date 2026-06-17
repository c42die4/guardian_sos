"""
Guardian SOS - Add CALL RIDER button + remove REMIND IN 10 MIN
Run from C:\\dev\\guardian_sos:
    python patch_callbutton.py
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
# 1. Add CALL RIDER button above NAVIGATE/RESPOND row
# ─────────────────────────────────────────────────────────────────
patch(
    'Add CALL RIDER button to alert panel',
    """                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.navigation, color: Colors.white),
                                    label: const Text("NAVIGATE", style: TextStyle(color: Colors.white)),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        padding: const EdgeInsets.all(12)),
                                    onPressed: () => _navigateTo(_selectedAlert!),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.directions_run, color: Colors.black),
                                    label: const Text("RESPOND", style: TextStyle(color: Colors.black,
           fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange,
                                        padding: const EdgeInsets.all(12)),
                                    onPressed: () => _markResponding(_selectedAlertId!),
                                  ),
                                ),
                              ],
                            ),""",
    """                            const SizedBox(height: 12),
                            Builder(builder: (context) {
                              final phone = (_selectedAlert!['mobilePhone'] ?? '').toString().trim();
                              if (phone.isEmpty) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.phone, color: Colors.white),
                                    label: Text(
                                      'CALL RIDER  —  $phone',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green[700],
                                        padding: const EdgeInsets.all(14)),
                                    onPressed: () async {
                                      final uri = Uri(scheme: 'tel', path: phone);
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri);
                                      }
                                    },
                                  ),
                                ),
                              );
                            }),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.navigation, color: Colors.white),
                                    label: const Text("NAVIGATE", style: TextStyle(color: Colors.white)),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        padding: const EdgeInsets.all(12)),
                                    onPressed: () => _navigateTo(_selectedAlert!),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.directions_run, color: Colors.black),
                                    label: const Text("RESPOND", style: TextStyle(color: Colors.black,
           fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange,
                                        padding: const EdgeInsets.all(12)),
                                    onPressed: () => _markResponding(_selectedAlertId!),
                                  ),
                                ),
                              ],
                            ),"""
)

# ─────────────────────────────────────────────────────────────────
# 2. Remove REMIND IN 10 MIN action from notifications
#    Keep only RESPONDING action
# ─────────────────────────────────────────────────────────────────
patch(
    'Remove REMIND IN 10 MIN notification action',
    """    const AndroidNotificationAction(
      'remind_10',
      'REMIND IN 10 MIN',
      showsUserInterface: false,
      cancelNotification: true,
    ),""",
    ""
)

# ─────────────────────────────────────────────────────────────────
# 3. Remove the snooze handler from _handleNotificationAction
#    since REMIND IN 10 MIN button no longer exists
# ─────────────────────────────────────────────────────────────────
patch(
    'Remove remind_10 handler from _handleNotificationAction',
    """  } else if (actionId == 'remind_10') {
    SOSEscalationManager.snoozeEscalation(alertId, const Duration(minutes: 10));
  }""",
    """  }"""
)

# ─────────────────────────────────────────────────────────────────
# Write output
# ─────────────────────────────────────────────────────────────────
with open(TARGET, 'w', encoding='utf-8') as f:
    f.write(src)

print(f'\n{patches} patches applied.')
if errors:
    print('\nNotes:')
    for e in errors:
        print(f'  {e}')

print('\nNext steps:')
print('  git add lib/main.dart')
print('  git commit -m "Add CALL RIDER button to alert panel, remove REMIND IN 10 MIN"')
print('  git push')
