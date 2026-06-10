with open("lib/main.dart", "r", encoding="utf-8") as f:
    c = f.read()
c = c.replace("'ð¨ SOS ALERT", "'SOS ALERT")
c = c.replace("'ð¨ SOS Active'", "'SOS Active'")
print("Fixed lines 114, 316, 367")
with open("lib/main.dart", "w", encoding="utf-8") as f:
    f.write(c)
