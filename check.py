with open("lib/main.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()
for i in range(218, 232):
    print(f"{i+1}: {repr(lines[i])}")
