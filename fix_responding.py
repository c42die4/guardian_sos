with open("lib/main.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()
# Add respondingBy and alertListener after line 1649 (int _seconds = 0;)
insert_after = 1648  # 0-indexed = line 1649
new_lines = [
    "  String? _respondingBy;\n",
    "  StreamSubscription? _alertListener;\n",
]
lines = lines[:insert_after+1] + new_lines + lines[insert_after+1:]
# Add listener to initState - after line 1662 (end of _timer setup)
# Find the line with setState(() => _seconds++);
for i, line in enumerate(lines):
    if "setState(() => _seconds++)" in line:
        timer_end = i + 2  # line after the }); closing the timer
        break
listener_code = [
    "    _alertListener = FirebaseFirestore.instance\n",
    "        .collection('alerts')\n",
    "        .doc(widget.alertId)\n",
    "        .snapshots()\n",
    "        .listen((snap) async {\n",
    "      if (!snap.exists) return;\n",
    "      final data = snap.data()!;\n",
    "      final status = data['status'] as String?;\n",
    "      final respondingBy = data['respondingBy'] as String?;\n",
    "      if (mounted) setState(() => _respondingBy = respondingBy);\n",
    "      if (status == 'RESOLVED' || status == 'CANCELLED') {\n",
    "        await stopLocationService();\n",
    "        if (mounted) widget.onCancel();\n",
    "      }\n",
    "    });\n",
]
lines = lines[:timer_end] + listener_code + lines[timer_end:]
# Add _alertListener?.cancel(); to dispose
for i, line in enumerate(lines):
    if "_pulseController.dispose();" in line and i > 1660:
        lines.insert(i, "    _alertListener?.cancel();\n")
        break
print("Lines:", len(lines))
print("Has _respondingBy:", any("_respondingBy" in l for l in lines))
print("Has _alertListener:", any("_alertListener" in l for l in lines))
with open("lib/main.dart", "w", encoding="utf-8") as f:
    f.writelines(lines)
