with open("lib/main.dart", "r", encoding="utf-8") as f:
    c = f.read()
import re
c = re.sub(r'[^\x00-\x7F]+ \$\{alerts\.length\} ACTIVE ALERT', '${alerts.length} ACTIVE ALERT', c)
print("Fixed:", "${alerts.length} ACTIVE ALERT" in c)
with open("lib/main.dart", "w", encoding="utf-8") as f:
    f.write(c)
