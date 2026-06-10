with open("lib/main.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()
for i, line in enumerate(lines, 1):
    if "ACTIVE ALERT" in line:
        print(f"Line {i}: {repr(line.strip())}")
