with open("lib/main.dart", "r", encoding="utf-8") as f:
    content = f.read()

# Fix 1: Add alertType to sendWhatsAppAlert
old1 = """Future<void> sendWhatsAppAlert({
  required String phone,
  required String userName,
  required double lat,
  required double lng,
  String countryCode = '27',
}) async {
  try {
    final whatsappCheck = Uri.parse('whatsapp://send');
    if (!await canLaunchUrl(whatsappCheck)) {
      debugPrint('WhatsApp not installed, skipping alert');
      return;
    }
    String cleaned = phone.replaceAll(RegExp(r'[\\s\\-\\(\\)\\+]'), '');
    if (cleaned.startsWith('00')) cleaned = cleaned.substring(2);
    if (cleaned.startsWith('0')) cleaned = countryCode + cleaned.substring(1);
    if (!cleaned.startsWith(countryCode)) cleaned = countryCode + cleaned;
    final mapsLink = 'https://www.google.com/maps?q=$lat,$lng';
    final message = Uri.encodeComponent(
        'EMERGENCY ALERT\\n\\n'
        '$userName needs urgent help!\\n\\n'
        'Location: $mapsLink\\n\\n'
        'Please respond immediately or call emergency services.');"""

new1 = """Future<void> sendWhatsAppAlert({
  required String phone,
  required String userName,
  required double lat,
  required double lng,
  String countryCode = '27',
  String alertType = 'SOS',
  String? riderPhone,
}) async {
  try {
    final whatsappCheck = Uri.parse('whatsapp://send');
    if (!await canLaunchUrl(whatsappCheck)) {
      debugPrint('WhatsApp not installed, skipping alert');
      return;
    }
    String cleaned = phone.replaceAll(RegExp(r'[\\s\\-\\(\\)\\+]'), '');
    if (cleaned.startsWith('00')) cleaned = cleaned.substring(2);
    if (cleaned.startsWith('0')) cleaned = countryCode + cleaned.substring(1);
    if (!cleaned.startsWith(countryCode)) cleaned = countryCode + cleaned;
    final mapsLink = 'https://www.google.com/maps?q=$lat,$lng';
    String alertTitle;
    switch (alertType) {
      case 'CRASH': alertTitle = 'CRASH DETECTED - $userName may be injured!'; break;
      case 'LOST': alertTitle = 'RIDER LOST - $userName needs directions'; break;
      case 'FUEL': alertTitle = 'FUEL REQUEST - $userName has run out of fuel'; break;
      case 'BREAKDOWN': alertTitle = 'BREAKDOWN - $userName needs mechanical help'; break;
      case 'MEDICAL': alertTitle = 'MEDICAL EMERGENCY - $userName needs medical help'; break;
      default: alertTitle = 'EMERGENCY SOS - $userName needs urgent help!';
    }
    final phoneInfo = riderPhone != null && riderPhone.isNotEmpty
        ? 'Call $userName: $riderPhone\\n\\n' : '';
    final message = Uri.encodeComponent(
        '$alertTitle\\n\\n'
        'Location: $mapsLink\\n\\n'
        '${phoneInfo}Please respond immediately or call emergency services.');"""

if old1 in content:
    content = content.replace(old1, new1, 1)
    print("Fix 1 OK")
else:
    print("Fix 1 NOT FOUND")

# Fix 2: Pass alertType in _sendWhatsAppAlerts
old2 = """  Future<void> _sendWhatsAppAlerts(
      Map<String, dynamic> profile, double lat, double lng) async {
    final userName = profile['name'] ?? 'User';
    final countryCode = (profile['countryCode'] ?? '27').toString();
    final contacts = ["""

new2 = """  Future<void> _sendWhatsAppAlerts(
      Map<String, dynamic> profile, double lat, double lng,
      {String alertType = 'SOS'}) async {
    final userName = profile['name'] ?? 'User';
    final countryCode = (profile['countryCode'] ?? '27').toString();
    final riderPhone = (profile['contact1Phone'] ?? '').toString().trim();
    final contacts = ["""

if old2 in content:
    content = content.replace(old2, new2, 1)
    print("Fix 2 OK")
else:
    print("Fix 2 NOT FOUND")

# Fix 2b: Add alertType and riderPhone to sendWhatsAppAlert call
old2b = """        await sendWhatsAppAlert(
          phone: phone,
          userName: userName,
          lat: lat,
          lng: lng,
          countryCode: countryCode,
        );"""

new2b = """        await sendWhatsAppAlert(
          phone: phone,
          userName: userName,
          lat: lat,
          lng: lng,
          countryCode: countryCode,
          alertType: alertType,
          riderPhone: riderPhone,
        );"""

if old2b in content:
    content = content.replace(old2b, new2b, 1)
    print("Fix 2b OK")
else:
    print("Fix 2b NOT FOUND")

# Fix 3: Send WhatsApp for help buttons too
old3 = """      Vibration.vibrate(duration: 500);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(label + ' alert sent - organiser notified!'),
            backgroundColor: Colors.green[800],
          ));"""

new3 = """      Vibration.vibrate(duration: 500);
      await _sendWhatsAppAlerts(profile, pos.latitude, pos.longitude, alertType: type);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(label + ' alert sent - organiser notified!'),
            backgroundColor: Colors.green[800],
          ));"""

if old3 in content:
    content = content.replace(old3, new3, 1)
    print("Fix 3 OK")
else:
    print("Fix 3 NOT FOUND")

print("Lines:", len(content.splitlines()))
with open("lib/main.dart", "w", encoding="utf-8") as f:
    f.write(content)
