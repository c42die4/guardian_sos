with open("lib/main.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()
# Fix line 567 (0-indexed: 566)
print("Before:", repr(lines[566].strip()))
lines[566] = "        'EMERGENCY ALERT\\n\\n'\n"
print("After:", repr(lines[566].strip()))
with open("lib/main.dart", "w", encoding="utf-8") as f:
    f.writelines(lines)
