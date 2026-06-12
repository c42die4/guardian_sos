with open("lib/main.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()
# Fix indentation of Padding and Column inside SingleChildScrollView
lines[3753] = "                          child: Padding(\n"
lines[3754] = "                            padding: const EdgeInsets.all(16.0),\n"
lines[3755] = "                            child: Column(\n"
lines[3756] = "                              mainAxisSize: MainAxisSize.min,\n"
lines[3757] = "                              crossAxisAlignment:\n"
lines[3758] = "                                  CrossAxisAlignment.start,\n"
lines[3759] = "                              children: [\n"
print("Fixed indentation")
print("Lines:", len(lines))
with open("lib/main.dart", "w", encoding="utf-8") as f:
    f.writelines(lines)
