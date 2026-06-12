with open("lib/main.dart", "r", encoding="utf-8") as f:
    content = f.read()

old = "            // Radius indicator badge\n            if (widget.responseRadiusKm < 9000)"

new = """            // Offline fallback - show when map tiles fail to load
            if (!_tilesLoaded && alerts.isNotEmpty && _officerPosition != null)
              Positioned(
                top: 80,
                left: 16,
                right: 16,
                child: Card(
                  color: Colors.black.withOpacity(0.85),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.wifi_off, color: Colors.orange, size: 16),
                            SizedBox(width: 6),
                            Text('No map data - GPS mode',
                                style: TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...alerts.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final alertLat = (data['lat'] as num?)?.toDouble() ?? 0;
                          final alertLng = (data['lng'] as num?)?.toDouble() ?? 0;
                          final dist = distanceKm(
                            _officerPosition!.latitude,
                            _officerPosition!.longitude,
                            alertLat, alertLng,
                          );
                          final bearing = Geolocator.bearingBetween(
                            _officerPosition!.latitude,
                            _officerPosition!.longitude,
                            alertLat, alertLng,
                          );
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Transform.rotate(
                                  angle: bearing * (3.14159 / 180),
                                  child: Icon(Icons.navigation, color: color, size: 32),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(data['userName'] ?? 'Rider',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      Text(dist < 1
                                          ? '${(dist * 1000).toStringAsFixed(0)}m away'
                                          : '${dist.toStringAsFixed(1)}km away',
                                          style: const TextStyle(color: Colors.orange, fontSize: 16, fontWeight: FontWeight.bold)),
                                      Text('${alertLat.toStringAsFixed(5)}, ${alertLng.toStringAsFixed(5)}',
                                          style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                    ],
                                  ),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  ),
                                  onPressed: () {
                                    final uri = Uri.parse(
                                        'https://www.google.com/maps/dir/?api=1&destination=$alertLat,$alertLng&travelmode=driving');
                                    launchUrl(uri, mode: LaunchMode.externalApplication);
                                  },
                                  child: const Text('GO', style: TextStyle(color: Colors.white, fontSize: 12)),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ),
              ),
            // Radius indicator badge
            if (widget.responseRadiusKm < 9000)"""

if old in content:
    content = content.replace(old, new, 1)
    print("Fix 3c OK")
else:
    print("NOT FOUND")

print("Lines:", len(content.splitlines()))
with open("lib/main.dart", "w", encoding="utf-8") as f:
    f.write(content)
