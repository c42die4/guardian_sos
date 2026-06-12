with open("lib/main.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()
# Remove duplicate children: [ at line 3760 (0-indexed: 3759)
lines.pop(3759)
print("Lines:", len(lines))
for i in range(3753, 3763):
    print(f"{i+1}: {repr(lines[i])}")
with open("lib/main.dart", "w", encoding="utf-8") as f:
    f.writelines(lines)
