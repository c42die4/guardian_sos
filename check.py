with open("lib/main.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()
for i in range(3848, 3865):
    print(f"{i+1}: {repr(lines[i])}")
