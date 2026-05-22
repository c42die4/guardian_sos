with open('lib/main.dart', 'r', encoding='utf-8') as f:
    c = f.read()

# Fix 3: _loadRadius in ProfileScreen
old3 = '  void initState() {\n    super.initState();\n    _loadProfile();\n  }\n\n  Future<void> _loadProfile()'
new3 = '  void initState() {\n    super.initState();\n    _loadProfile();\n    _loadRadius();\n  }\n\n  Future<void> _loadRadius() async {\n    final prefs = await SharedPreferences.getInstance();\n    final r = prefs.getDouble(\'response_radius_km\') ?? 50.0;\n    if (mounted) setState(() => _radiusKm = r);\n  }\n\n  Future<void> _loadProfile()'
c = c.replace(old3, new3, 1)

# Fix 4: Save radius on profile save
old4 = '    setState(() => _saving = false);\n    if (mounted) {\n      ScaffoldMessenger.of(context).showSnackBar(\n          const SnackBar(content: Text("Profile saved successfully!")));\n      Navigator.of(context).pop();\n    }\n  }'
new4 = '    setState(() => _saving = false);\n    if (currentRole == \'officer\') {\n      final prefs = await SharedPreferences.getInstance();\n      await prefs.setDouble(\'response_radius_km\', _radiusKm);\n    }\n    if (mounted) {\n      ScaffoldMessenger.of(context).showSnackBar(\n          const SnackBar(content: Text("Profile saved successfully!")));\n      Navigator.of(context).pop();\n    }\n  }'
c = c.replace(old4, new4, 1)

# Fix 5: _quickRadius helper
old5 = '  Widget _sectionHeader(String title, IconData icon'
new5 = '  Widget _quickRadius(String label, double value) {\n    final selected = value >= 9000 ? _radiusKm >= 9000 : (_radiusKm - value).abs() < 1;\n    return GestureDetector(\n      onTap: () => setState(() => _radiusKm = value),\n      child: Container(\n        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),\n        decoration: BoxDecoration(\n          color: selected ? Colors.blue : Colors.grey[800],\n          borderRadius: BorderRadius.circular(20),\n        ),\n        child: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.grey, fontSize: 12, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),\n      ),\n    );\n  }\n\n  Widget _sectionHeader(String title, IconData icon'
c = c.replace(old5, new5, 1)

# Fix 6: Officer Settings section
old6 = '                  const SizedBox(height: 24),\n                  SizedBox(\n                    width: double.infinity,\n                    height: 54,\n                    child: ElevatedButton.icon(\n                      icon: _saving'
new6 = '                  if (currentRole == \'officer\') ...[\n                    Padding(\n                      padding: const EdgeInsets.only(top: 24, bottom: 8),\n                      child: Row(children: [\n                        const Icon(Icons.radar, color: Colors.blue, size: 20),\n                        const SizedBox(width: 8),\n                        const Text(\'Officer Settings\', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),\n                      ]),\n                    ),\n                    const Text(\'Set your response radius - alerts outside this range are hidden.\', style: TextStyle(color: Colors.grey, fontSize: 12)),\n                    const SizedBox(height: 12),\n                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [\n                      const Text(\'Response Radius\', style: TextStyle(color: Colors.white70)),\n                      Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(20)), child: Text(_radiusKm >= 9000 ? \'All areas\' : \'${_radiusKm.toStringAsFixed(0)} km\', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),\n                    ]),\n                    Slider(value: _radiusKm >= 9000 ? 500 : _radiusKm, min: 10, max: 500, divisions: 49, activeColor: Colors.blue, onChanged: (v) => setState(() => _radiusKm = v)),\n                    Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_quickRadius(\'10 km\', 10), _quickRadius(\'50 km\', 50), _quickRadius(\'100 km\', 100), _quickRadius(\'All\', 9999)]),\n                    const SizedBox(height: 16),\n                  ],\n                  const SizedBox(height: 24),\n                  SizedBox(\n                    width: double.infinity,\n                    height: 54,\n                    child: ElevatedButton.icon(\n                      icon: _saving'
c = c.replace(old6, new6, 1)

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(c)
print('Lines:', len(c.splitlines()))
print('_radiusKm count:', c.count('_radiusKm'))
print('Officer Settings:', 'Officer Settings' in c)
print('_quickRadius:', '_quickRadius' in c)
