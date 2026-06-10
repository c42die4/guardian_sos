with open("lib/main.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()
# Find and remove duplicate declarations
responding_lines = [i for i, l in enumerate(lines) if "_respondingBy" in l and "String?" in l]
listener_lines = [i for i, l in enumerate(lines) if "_alertListener" in l and "StreamSubscription?" in l]
print("_respondingBy at lines:", [i+1 for i in responding_lines])
print("_alertListener at lines:", [i+1 for i in listener_lines])
# Remove the second occurrence of each
if len(responding_lines) > 1:
    lines.pop(responding_lines[1])
    # recalculate after removal
    listener_lines = [i for i, l in enumerate(lines) if "_alertListener" in l and "StreamSubscription?" in l]
if len(listener_lines) > 1:
    lines.pop(listener_lines[1])
print("Lines after fix:", len(lines))
with open("lib/main.dart", "w", encoding="utf-8") as f:
    f.writelines(lines)
