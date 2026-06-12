with open("lib/main.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()
# Remove duplicate line 3753 (0-indexed: 3752)
lines.pop(3752)
print("Lines after fix:", len(lines))
for i in range(3748, 3758):
    print(f"{i+1}: {repr(lines[i])}")
with open("lib/main.dart", "w", encoding="utf-8") as f:
    f.writelines(lines)
