with open("lib/main.dart", "r", encoding="utf-8") as f:
    c = f.read()
# Fix 1: Remove duplicate alert listener - keep only first occurrence
first = c.find("    _alertListener = FirebaseFirestore.instance")
second = c.find("    _alertListener = FirebaseFirestore.instance", first + 1)
if second > 0:
    end = c.find("    });", second) + len("    });")
    c = c[:second] + c[end:]
    print("Fix 1 (duplicate listener) OK")
else:
    print("Fix 1 - no duplicate found")
# Fix 2: Remove duplicate dispose cancel
c = c.replace(
    "    _alertListener?.cancel();\n    _alertListener?.cancel();",
    "    _alertListener?.cancel();"
)
print("Fix 2 (duplicate dispose) OK")
# Fix 3: Fix WhatsApp message encoding
c = c.replace(
    "'Ã°Â¨ EMERGENCY ALERT Ã°Â¨\\n\\n'",
    "'EMERGENCY ALERT\\n\\n'"
)
c = c.replace(
    "' Location: $mapsLink\\n\\n'",
    "'Location: $mapsLink\\n\\n'"
)
print("Fix 3 (WhatsApp message) OK")
# Fix 4: Add countryCode parameter to sendWhatsAppAlert
c = c.replace(
    "Future<void> sendWhatsAppAlert({\n  required String phone,\n  required String userName,\n  required double lat,\n  required double lng,\n}) async {",
    "Future<void> sendWhatsAppAlert({\n  required String phone,\n  required String userName,\n  required double lat,\n  required double lng,\n  String countryCode = '27',\n}) async {"
)
print("Fix 4 (countryCode param) OK")
# Fix 5: Use countryCode in phone cleaning
c = c.replace(
    "    String cleaned = phone.replaceAll(RegExp(r'[\\s\\-\\(\\)]'), '');\n    if (cleaned.startsWith('0')) {\n      cleaned = '+27${cleaned.substring(1)}';\n    }\n    cleaned = cleaned.replaceAll('+', '');",
    "    String cleaned = phone.replaceAll(RegExp(r'[\\s\\-\\(\\)\\+]'), '');\n    if (cleaned.startsWith('00')) cleaned = cleaned.substring(2);\n    if (cleaned.startsWith('0')) cleaned = countryCode + cleaned.substring(1);\n    if (!cleaned.startsWith(countryCode)) cleaned = countryCode + cleaned;"
)
print("Fix 5 (phone cleaning) OK")
# Fix 6: Pass countryCode in _sendWhatsAppAlerts
c = c.replace(
    "  Future<void> _sendWhatsAppAlerts(\n      Map<String, dynamic> profile, double lat, double lng) async {\n    final userName = profile['name'] ?? 'User';\n    final contacts = [",
    "  Future<void> _sendWhatsAppAlerts(\n      Map<String, dynamic> profile, double lat, double lng) async {\n    final userName = profile['name'] ?? 'User';\n    final countryCode = (profile['countryCode'] ?? '27').toString();\n    final contacts = ["
)
c = c.replace(
    "        await sendWhatsAppAlert(\n          phone: phone,\n          userName: userName,\n          lat: lat,\n          lng: lng,\n        );",
    "        await sendWhatsAppAlert(\n          phone: phone,\n          userName: userName,\n          lat: lat,\n          lng: lng,\n          countryCode: countryCode,\n        );"
)
print("Fix 6 (pass countryCode) OK")
print("Lines:", len(c.splitlines()))
with open("lib/main.dart", "w", encoding="utf-8") as f:
    f.write(c)
