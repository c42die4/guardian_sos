with open("lib/main.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()
# Fix notification to show alert type
for i, line in enumerate(lines):
    if "await showAlertNotification(" in line and i > 200 and i < 240:
        lines[i-1] = "    final helpType = data['helpType'] as String?;\n    final alertPrefix = helpType != null && helpType.isNotEmpty ? '[' + helpType + '] ' : '[SOS] ';\n"
        lines[i] = "    await showAlertNotification(\n"
        lines[i+1] = "      alertPrefix + name,\n"
        lines[i+2] = "      '$lat, $lng - Started $ageLabel',\n"
        break
print("Notification fix OK")
print("Lines:", len(lines))
with open("lib/main.dart", "w", encoding="utf-8") as f:
    f.writelines(lines)
