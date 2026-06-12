with open("lib/main.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()
# Remove duplicate closing brackets (lines 3857, 3858, 3859 are extra)
# Keep: 3849-3856, then skip 3857-3859, keep rest
lines = lines[:3856] + lines[3859:]
print("Lines after fix:", len(lines))
# Verify
for i in range(3848, 3862):
    print(f"{i+1}: {repr(lines[i])}")
with open("lib/main.dart", "w", encoding="utf-8") as f:
    f.writelines(lines)
