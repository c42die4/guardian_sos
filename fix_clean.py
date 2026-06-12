with open("lib/main.dart", "r", encoding="utf-8") as f:
    c = f.read()
# Fix 1: WhatsApp return faster
c = c.replace(
    "    final url = 'whatsapp://send?phone=$cleaned&text=$message';\n    final uri = Uri.parse(url);\n    if (await canLaunchUrl(uri)) {\n      await launchUrl(uri, mode: LaunchMode.externalApplication);\n      await Future.delayed(const Duration(seconds: 2));\n    }",
    "    final url = 'https://wa.me/$cleaned?text=$message';\n    final uri = Uri.parse(url);\n    if (await canLaunchUrl(uri)) {\n      await launchUrl(uri, mode: LaunchMode.externalApplication);\n      await Future.delayed(const Duration(milliseconds: 1500));\n    }"
)
print("Fix 1 (WhatsApp):", "wa.me" in c)
# Fix 2: Add _tilesLoaded to OfficerDashboard state
c = c.replace(
    "  bool _mapReady = false;\n  bool _isMuted = false;",
    "  bool _mapReady = false;\n  bool _isMuted = false;\n  bool _tilesLoaded = false;"
)
print("Fix 2 (_tilesLoaded):", "_tilesLoaded" in c)
# Fix 3: Add tileBuilder and errorTileCallback
c = c.replace(
    "                TileLayer(\n                    urlTemplate:\n                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',\n                    userAgentPackageName: 'com.cyberwarriors.sos',\n                    maxZoom: 19,\n                    ),",
    "                TileLayer(\n                    urlTemplate:\n                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',\n                    userAgentPackageName: 'com.cyberwarriors.sos',\n                    maxZoom: 19,\n                    tileBuilder: (context, tileWidget, tile) {\n                      if (!_tilesLoaded && mounted) {\n                        WidgetsBinding.instance.addPostFrameCallback((_) {\n                          if (mounted) setState(() => _tilesLoaded = true);\n                        });\n                      }\n                      return tileWidget;\n                    },\n                    errorTileCallback: (tile, error, stackTrace) {\n                      if (mounted) setState(() => _tilesLoaded = false);\n                    },\n                    ),"
)
print("Fix 3 (tile detection):", "tileBuilder" in c)
# Fix 4: Add offline GPS fallback card
c = c.replace(
    "            // Radius indicator badge\n            if (widget.responseRadiusKm < 9000)",
    """            // Offline GPS fallback
            if (!_tilesLoaded && alerts.isNotEmpty && _officerPosition != null)
              Positioned(
                top: 80, left: 16, right: 16,
                child: Card(
                  color: Colors.black.withOpacity(0.85),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.wifi_off, color: Colors.orange, size: 16),
                          SizedBox(width: 6),
                          Text('No map data - GPS mode', style: TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 12),
                        ...alerts.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final alertLat = (data['lat'] as num?)?.toDouble() ?? 0;
                          final alertLng = (data['lng'] as num?)?.toDouble() ?? 0;
                          final dist = distanceKm(_officerPosition!.latitude, _officerPosition!.longitude, alertLat, alertLng);
                          final bearing = Geolocator.bearingBetween(_officerPosition!.latitude, _officerPosition!.longitude, alertLat, alertLng);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(children: [
                              Transform.rotate(angle: bearing * (3.14159 / 180), child: Icon(Icons.navigation, color: color, size: 28)),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(data['userName'] ?? 'Rider', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                Text(dist < 1 ? '${(dist*1000).toStringAsFixed(0)}m away' : '${dist.toStringAsFixed(1)}km away', style: const TextStyle(color: Colors.orange, fontSize: 14, fontWeight: FontWeight.bold)),
                                Text('${alertLat.toStringAsFixed(5)}, ${alertLng.toStringAsFixed(5)}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                              ])),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                                onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$alertLat,$alertLng&travelmode=driving'), mode: LaunchMode.externalApplication),
                                child: const Text('GO', style: TextStyle(color: Colors.white, fontSize: 12)),
                              ),
                            ]),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ),
              ),
            // Radius indicator badge
            if (widget.responseRadiusKm < 9000)"""
)
print("Fix 4 (offline fallback):", "GPS mode" in c)
print("Lines:", len(c.splitlines()))
with open("lib/main.dart", "w", encoding="utf-8") as f:
    f.write(c)
