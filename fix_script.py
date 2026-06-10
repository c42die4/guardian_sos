with open("lib/main.dart", "r", encoding="utf-8") as f:
    c = f.read()
c = c.replace(
    "ðŸš¨ ${alerts.length} ACTIVE ALERT",
    "🚨 ${alerts.length} ACTIVE ALERT"
)
print("Fixed:", "🚨 ${alerts.length}" in c)
with open("lib/main.dart", "w", encoding="utf-8") as f:
    f.write(c)
