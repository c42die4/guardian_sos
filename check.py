with open("lib/main.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()
for i, line in enumerate(lines, 1):
    if "EMERGENCY ALERT" in line or "SOS ALERT" in line or "notificationTitle" in line or "notificationText" in line:
        print(f"{i}: {repr(line.strip())}")
