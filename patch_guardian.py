"""
Guardian SOS - patch script
Run from C:\\dev\\guardian_sos:
    python patch_guardian.py

Applies all changes from session 2026-06-14:
  1. Coloured help-type markers on officer map
  2. Crash detection: flashing car_crash icon
  3. Rider profile: mobile number field
  4. Rider profile: email address field
  5. Registration screen overflow fix (keyboard squash)
"""

import sys
import shutil
from datetime import datetime

TARGET = 'lib/main.dart'

with open(TARGET, 'r', encoding='utf-8') as f:
    src = f.read()

# Backup first
backup = f'lib/main.dart.bak.{datetime.now().strftime("%Y%m%d_%H%M%S")}'
shutil.copy(TARGET, backup)
print(f'Backup saved to {backup}')

errors = []
patches_applied = 0

def patch(label, old, new):
    global src, patches_applied
    count = src.count(old)
    if count == 0:
        errors.append(f'SKIP [{label}] — pattern not found (may already be applied)')
        return
    if count > 1:
        errors.append(f'WARN [{label}] — pattern found {count} times, skipping to be safe')
        return
    src = src.replace(old, new, 1)
    patches_applied += 1
    print(f'  [OK] {label}')

# ─────────────────────────────────────────────────────────────────
# 1. Coloured markers — use _alertIcon/_alertColor in MarkerLayer
# ─────────────────────────────────────────────────────────────────
patch(
    'Coloured help markers',
    """                        child: Column(
                          children: [
                            Icon(Icons.warning,
                                color: isSelected
                                    ? Colors.orange
                                    : color,
                                size: isSelected ? 48 : 40),""",
    """                        child: Column(
                          children: [
                            Icon(
                                isSelected
                                    ? Icons.warning
                                    : _alertIcon(data['helpType'] as String?),
                                color: isSelected
                                    ? Colors.orange
                                    : (data['helpType'] == 'CRASH'
                                        ? (_crashFlash ? Colors.redAccent : Colors.white)
                                        : _alertColor(data['helpType'] as String?, color)),
                                size: data['helpType'] == 'CRASH' ? 44 : (isSelected ? 48 : 40)),"""
)

# ─────────────────────────────────────────────────────────────────
# 2a. Add _crashFlash + _flashTimer state fields
# ─────────────────────────────────────────────────────────────────
patch(
    'Crash flash state fields',
    """  bool _panelOpen = false;
  Position? _officerPosition;""",
    """  bool _panelOpen = false;
  Position? _officerPosition;
  bool _crashFlash = false;
  Timer? _flashTimer;"""
)

# ─────────────────────────────────────────────────────────────────
# 2b. Start flash timer in initState
# ─────────────────────────────────────────────────────────────────
patch(
    'Flash timer in initState',
    """  @override
  void initState() {
    super.initState();
    _getOfficerPosition();
  }""",
    """  @override
  void initState() {
    super.initState();
    _getOfficerPosition();
    _flashTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _crashFlash = !_crashFlash);
    });
  }"""
)

# ─────────────────────────────────────────────────────────────────
# 2c. Cancel flash timer in dispose
# ─────────────────────────────────────────────────────────────────
patch(
    'Flash timer cancel in dispose',
    """  @override
  void dispose() {
    // Stop all escalation timers when dashboard is closed
    SOSEscalationManager.stopAll();
    super.dispose();
  }""",
    """  @override
  void dispose() {
    _flashTimer?.cancel();
    // Stop all escalation timers when dashboard is closed
    SOSEscalationManager.stopAll();
    super.dispose();
  }"""
)

# ─────────────────────────────────────────────────────────────────
# 2d. Add CRASH to _alertIcon
# ─────────────────────────────────────────────────────────────────
patch(
    'CRASH icon in _alertIcon',
    """  IconData _alertIcon(String? helpType) {
    switch (helpType) {
      case 'LOST': return Icons.explore_off;""",
    """  IconData _alertIcon(String? helpType) {
    switch (helpType) {
      case 'CRASH': return Icons.car_crash;
      case 'LOST': return Icons.explore_off;"""
)

# ─────────────────────────────────────────────────────────────────
# 3a. Add mobilePhone + email controller declarations
# ─────────────────────────────────────────────────────────────────
patch(
    'mobilePhone + email controller declarations',
    """  final _wa3NameCtrl = TextEditingController();
  final _wa3PhoneCtrl = TextEditingController();""",
    """  final _wa3NameCtrl = TextEditingController();
  final _wa3PhoneCtrl = TextEditingController();
  final _mobilePhoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();"""
)

# ─────────────────────────────────────────────────────────────────
# 3b. Load mobilePhone + email in _loadProfile
# ─────────────────────────────────────────────────────────────────
patch(
    'Load mobilePhone + email from Firestore',
    """      _wa3NameCtrl.text = d['wa3Name'] ?? '';
      _wa3PhoneCtrl.text = d['wa3Phone'] ?? '';""",
    """      _wa3NameCtrl.text = d['wa3Name'] ?? '';
      _wa3PhoneCtrl.text = d['wa3Phone'] ?? '';
      _mobilePhoneCtrl.text = d['mobilePhone'] ?? '';
      _emailCtrl.text = d['email'] ?? '';"""
)

# ─────────────────────────────────────────────────────────────────
# 3c. Save mobilePhone + email in _saveProfile
# ─────────────────────────────────────────────────────────────────
patch(
    'Save mobilePhone + email to Firestore',
    """      'wa3Name': _wa3NameCtrl.text.trim(),
      'wa3Phone': _wa3PhoneCtrl.text.trim(),
      'companyId': currentCompany?.id ?? '',""",
    """      'wa3Name': _wa3NameCtrl.text.trim(),
      'wa3Phone': _wa3PhoneCtrl.text.trim(),
      'mobilePhone': _mobilePhoneCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'companyId': currentCompany?.id ?? '',"""
)

# ─────────────────────────────────────────────────────────────────
# 3d. Add form fields for mobile + email
# ─────────────────────────────────────────────────────────────────
patch(
    'Mobile + email form fields',
    """                  _field("Full Name", _nameCtrl, required: true),
                  _field("ID Number", _idCtrl,
                      keyboardType: TextInputType.number),""",
    """                  _field("Full Name", _nameCtrl, required: true),
                  _field("Your Mobile Number", _mobilePhoneCtrl,
                      keyboardType: TextInputType.phone),
                  _field("Email Address", _emailCtrl,
                      keyboardType: TextInputType.emailAddress),
                  _field("ID Number", _idCtrl,
                      keyboardType: TextInputType.number),"""
)

# ─────────────────────────────────────────────────────────────────
# 3e. Dispose mobilePhone + email controllers
# ─────────────────────────────────────────────────────────────────
patch(
    'Dispose mobilePhone + email controllers',
    """    _wa3NameCtrl.dispose();
    _wa3PhoneCtrl.dispose();
    super.dispose();""",
    """    _wa3NameCtrl.dispose();
    _wa3PhoneCtrl.dispose();
    _mobilePhoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();"""
)

# ─────────────────────────────────────────────────────────────────
# 3f. Show mobile + email in officer profile popup
# ─────────────────────────────────────────────────────────────────
patch(
    'Mobile + email in officer profile view',
    """            _profileSection("Personal Information", Icons.person, [
              _profileRow("Name", profile['name']),
              _profileRow("ID Number", profile['idNumber']),""",
    """            _profileSection("Personal Information", Icons.person, [
              _profileRow("Name", profile['name']),
              _callableRow(context, "Mobile", profile['mobilePhone']),
              _callableEmailRow(context, "Email", profile['email']),
              _profileRow("ID Number", profile['idNumber']),"""
)

# ─────────────────────────────────────────────────────────────────
# 3g. Add _callableEmailRow helper
# ─────────────────────────────────────────────────────────────────
patch(
    '_callableEmailRow helper method',
    """  Widget _callableRow(
      BuildContext context, String label, dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(""",
    """  Widget _callableEmailRow(
      BuildContext context, String label, dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(color: Colors.grey))),
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final uri = Uri(scheme: 'mailto', path: text);
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
              child: Text(
                text,
                style: const TextStyle(
                    fontSize: 15,
                    color: Colors.lightBlue,
                    decoration: TextDecoration.underline),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _callableRow(
      BuildContext context, String label, dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding("""
)

# ─────────────────────────────────────────────────────────────────
# 4. Registration screen overflow fix
# ─────────────────────────────────────────────────────────────────
patch(
    'Registration screen overflow fix',
    """    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield, size: 80, color: Colors.red),""",
    """    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield, size: 80, color: Colors.red),"""
)

patch(
    'Registration screen overflow fix - closing bracket',
    """            ],
          ),
        ),
      ),
    );
  }
}

// """,
    """            ],
          ),
        ),
        ),
      ),
    );
  }
}

// """
)

# ─────────────────────────────────────────────────────────────────
# Write output
# ─────────────────────────────────────────────────────────────────
with open(TARGET, 'w', encoding='utf-8') as f:
    f.write(src)

print(f'\n{patches_applied} patches applied successfully.')
if errors:
    print('\nNotes:')
    for e in errors:
        print(f'  {e}')

print('\nNext steps:')
print('  git add lib/main.dart')
print('  git commit -m "Coloured markers, crash flash, mobile/email fields, overflow fix"')
print('  git push')
