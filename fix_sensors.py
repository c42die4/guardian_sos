with open('lib/main.dart', 'r', encoding='utf-8') as f:
    c = f.read()

# Find and replace the accelerometer listener block
import re
c = re.sub(
    r'_accelSubscription = accelerometerEventStream\(.*?\.listen\(.*?\{.*?_lastHighGEvent = now;\s*\}\s*\}\s*\}\s*\}\s*\}\s*\}\s*\}\s*\}\);',
    '// Crash detection stub - sensors_plus temporarily removed\n    debugPrint("Crash detection not available");',
    c, flags=re.DOTALL
)

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(c)
print('Done. Lines:', len(c.splitlines()))
