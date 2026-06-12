with open("lib/main.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()
for i in range(3844, 3862):
    print(f"{i+1}: {repr(lines[i])}")
