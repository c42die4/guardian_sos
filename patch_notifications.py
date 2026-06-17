"""
Guardian SOS - notification fixes
Run from C:\\dev\\guardian_sos:
    python patch_notifications.py

Fixes:
  1. Strip emoji from notification action button labels
  2. Add CALL action button to notifications using rider's mobilePhone
"""

import shutil
from datetime import datetime

TARGET = 'lib/main.dart'

with open(TARGET, 'r', encoding='utf-8') as f:
    src = f.read()

backup = f'lib/main.dart.bak.{datetime.now().strftime("%Y%m%d_%H%M%S")}'
shutil.copy(TARGET, backup)
print(f'Backup saved to {backup}')

errors = []
patches = 0

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
# 1. Fix showAlertNotification signature to accept phone number
#    and add CALL action, strip emoji from action labels
# ─────────────────────────────────────────────────────────────────
patch(
    'showAlertNotification: add phone param + fix action labels',
    """Future<void> showAlertNotification(String name, String location,
    {int notificationId = 0, String? alertId}) async {
  final List<AndroidNotificationAction> actions = [
    const AndroidNotificationAction(
      'responding',
      '\u2708\ufe0f\u00a0RESPONDING',
      showsUserInterface: true,
      cancelNotification: true,
    ),
    const AndroidNotificationAction(
      'remind_10',
      '\u23f0 REMIND IN 10 MIN',
      showsUserInterface: false,
      cancelNotification: true,
    ),
  ];""",
    """Future<void> showAlertNotification(String name, String location,
    {int notificationId = 0, String? alertId, String? phone}) async {
  final List<AndroidNotificationAction> actions = [
    if (phone != null && phone.isNotEmpty)
      AndroidNotificationAction(
        'call_$phone',
        'CALL RIDER',
        showsUserInterface: true,
        cancelNotification: false,
      ),
    const AndroidNotificationAction(
      'responding',
      'RESPONDING',
      showsUserInterface: true,
      cancelNotification: true,
    ),
    const AndroidNotificationAction(
      'remind_10',
      'REMIND IN 10 MIN',
      showsUserInterface: false,
      cancelNotification: true,
    ),
  ];"""
)

# ─────────────────────────────────────────────────────────────────
# 2. Handle CALL action in notification response handler
#    Find the existing _onNotificationResponse and add call handling
# ─────────────────────────────────────────────────────────────────
patch(
    'Handle CALL action in notification response',
    """  if (response.actionId == 'responding') {""",
    """  if (response.actionId != null && response.actionId!.startsWith('call_')) {
    final number = response.actionId!.substring(5);
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
    return;
  }
  if (response.actionId == 'responding') {"""
)

# ─────────────────────────────────────────────────────────────────
# 3. Pass phone number from escalation _notify through to showAlertNotification
# ─────────────────────────────────────────────────────────────────
patch(
    'Pass phone to showAlertNotification in _notify',
    """    final helpType = data['helpType'] as String?;
    final alertPrefix = helpType != null && helpType.isNotEmpty ? '[' + helpType + '] ' : '[SOS] ';
    await showAlertNotification(
      alertPrefix + name,
      '$lat, $lng - Started $ageLabel',
      notificationId: notificationId,
      alertId: alertId,
    );""",
    """    final helpType = data['helpType'] as String?;
    final alertPrefix = helpType != null && helpType.isNotEmpty ? '[' + helpType + '] ' : '[SOS] ';
    final profile = data['profile'] as Map<String, dynamic>?;
    final phone = profile?['mobilePhone'] as String? ?? '';
    await showAlertNotification(
      alertPrefix + name,
      '$lat, $lng - Started $ageLabel',
      notificationId: notificationId,
      alertId: alertId,
      phone: phone,
    );"""
)

# ─────────────────────────────────────────────────────────────────
# 4. Write mobilePhone into SOS alert document (line ~2172)
# ─────────────────────────────────────────────────────────────────
patch(
    'Write mobilePhone into SOS alert document',
    """      DocumentReference doc =
          await FirebaseFirestore.instance.collection('alerts').add({
        'userName': profile['name'] ?? 'User',
        'lat': pos.latitude,
        'lng': pos.longitude,
        'status': 'ACTIVE',
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'profile': profile,
        'companyId': widget.company.id,
      });""",
    """      DocumentReference doc =
          await FirebaseFirestore.instance.collection('alerts').add({
        'userName': profile['name'] ?? 'User',
        'mobilePhone': profile['mobilePhone'] ?? '',
        'lat': pos.latitude,
        'lng': pos.longitude,
        'status': 'ACTIVE',
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'profile': profile,
        'companyId': widget.company.id,
      });"""
)

# ─────────────────────────────────────────────────────────────────
# 5. Write mobilePhone into help alert document (line ~2253)
# ─────────────────────────────────────────────────────────────────
patch(
    'Write mobilePhone into help alert document',
    """      await FirebaseFirestore.instance.collection('alerts').add({
        'userName': profile['name'] ?? 'Rider',
        'lat': pos.latitude,
        'lng': pos.longitude,
        'status': 'ACTIVE',
        'helpType': type,
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'profile': profile,
        'companyId': widget.company.id,
      });""",
    """      await FirebaseFirestore.instance.collection('alerts').add({
        'userName': profile['name'] ?? 'Rider',
        'mobilePhone': profile['mobilePhone'] ?? '',
        'lat': pos.latitude,
        'lng': pos.longitude,
        'status': 'ACTIVE',
        'helpType': type,
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'profile': profile,
        'companyId': widget.company.id,
      });"""
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
print('  git commit -m "Fix notification emoji, add CALL button, write mobilePhone to alerts"')
print('  git push')
