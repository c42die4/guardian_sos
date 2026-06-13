with open("lib/main.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()
# Insert the missing notificationId line before line 222 (0-indexed 221)
lines.insert(221, "    final notificationId = alertId.hashCode.abs() % 10000;\n")
print("Lines:", len(lines))
for i in range(219, 232):
    print(f"{i+1}: {repr(lines[i])}")
with open("lib/main.dart", "w", encoding="utf-8") as f:
    f.writelines(lines)
