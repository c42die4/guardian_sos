with open("lib/main.dart", "r", encoding="utf-8") as f:
    c = f.read()
# Remove the duplicate - keep only the first occurrence
first = c.find("  Widget _helpButton(")
second = c.find("  Widget _helpButton(", first + 1)
if second > 0:
    # Find end of second duplicate block (ends before _onSOSCancelled)
    end = c.find("  void _onSOSCancelled() {", second)
    c = c[:second] + c[end:]
    print("Duplicate removed!")
else:
    print("No duplicate found")
print("Count of _helpButton:", c.count("Widget _helpButton("))
print("Lines:", len(c.splitlines()))
with open("lib/main.dart", "w", encoding="utf-8") as f:
    f.write(c)
