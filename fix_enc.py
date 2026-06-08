with open("C:/dev/guardian_sos/lib/main.dart", "r", encoding="utf-8") as f:
    c = f.read()

# Fix em dash in app bar title
c = c.replace('\u00e2\u20ac\u201c OFFICER', ' \u2014 OFFICER')

# Fix radar emoji in "Showing alerts within" text
c = c.replace('\u00f0\u0178\u201c\u00a1', '\U0001f4e1')

with open("C:/dev/guardian_sos/lib/main.dart", "w", encoding="utf-8") as f:
    f.write(c)
print("Done. Lines:", len(c.splitlines()))
