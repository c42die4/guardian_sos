with open('lib/main.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# ─────────────────────────────────────────────────────────────────
# FIX 1: Auto-return after WhatsApp - use background send approach
# ─────────────────────────────────────────────────────────────────
old1 = '''    final url = 'whatsapp://send?phone=$cleaned&text=$message';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      await Future.delayed(const Duration(seconds: 2));
    }'''

new1 = '''    // Use wa.me link which opens WhatsApp and returns to app faster
    final url = 'https://wa.me/$cleaned?text=$message';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      // Brief delay then return focus to our app
      await Future.delayed(const Duration(milliseconds: 1500));
    }'''

if old1 in content:
    content = content.replace(old1, new1, 1)
    print('Fix 1 (WhatsApp return) OK')
else:
    print('Fix 1 NOT FOUND')

# ─────────────────────────────────────────────────────────────────
# FIX 2: Make bottom alert card scrollable so Profile is visible
# ─────────────────────────────────────────────────────────────────
old2 = '''            if (_selectedAlert != null)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Card(
                      color: Colors.grey[900],
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,'''

new2 = '''            if (_selectedAlert != null)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Card(
                      color: Colors.grey[900],
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.45,
                        ),
                        child: SingleChildScrollView(
                          child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,'''

if old2 in content:
    content = content.replace(old2, new2, 1)
    print('Fix 2a (scrollable card start) OK')
else:
    print('Fix 2a NOT FOUND')

# Close the extra widgets added above
old2b = '''                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_panelOpen && alerts.isNotEmpty)'''

new2b = '''                          ],
                        ),
                      ),
                    ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_panelOpen && alerts.isNotEmpty)'''

if old2b in content:
    content = content.replace(old2b, new2b, 1)
    print('Fix 2b (scrollable card end) OK')
else:
    print('Fix 2b NOT FOUND')

# ─────────────────────────────────────────────────────────────────
# FIX 3: Add offline fallback with coordinates + direction arrow
# ─────────────────────────────────────────────────────────────────

# Add _tilesLoaded state variable to OfficerDashboard
old3a = '''  bool _mapReady = false;
  bool _isMuted = false;'''

new3a = '''  bool _mapReady = false;
  bool _isMuted = false;
  bool _tilesLoaded = false;'''

if old3a in content:
    content = content.replace(old3a, new3a, 1)
    print('Fix 3a (tiles state) OK')
else:
    print('Fix 3a NOT FOUND')

# Add errorTileProvider to TileLayer to detect tile failures
old3b = '''                TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.cyberwarriors.sos',
                    maxZoom: 19,
                    ),'''

new3b = '''                TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.cyberwarriors.sos',
                    maxZoom: 19,
                    tileBuilder: (context, tileWidget, tile) {
                      if (!_tilesLoaded && mounted) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _tilesLoaded = true);
                        });
                      }
                      return tileWidget;
                    },
                    errorTileCallback: (tile, error, stackTrace) {
                      if (mounted) setState(() => _tilesLoaded = false);
                    },
                    ),'''

if old3b in content:
    content = content.replace(old3b, new3b, 1)
    print('Fix 3b (tile error detection) OK')
else:
    print('Fix 3b NOT FOUND')

# Add offline fallback overlay when tiles not loaded and alerts exist
old3c = '''            if (alerts.isEmpty)
              Center(
                child: Card(
                  color: Colors.black54,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("No active alerts",
                            style: TextStyle(
                                fontSize: 18, color: Colors.white)),
                        if (widget.responseRadiusKm < 9000)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              "Showing alerts within ${widget.responseRadiusKm.toStringAsFixed(0)} km",
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),'''

new3c = '''            if (alerts.isEmpty)
              Center(
                child: Card(
                  color: Colors.black54,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("No active alerts",
                            style: TextStyle(
                                fontSize: 18, color: Colors.white)),
                        if (widget.responseRadiusKm < 9000)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              "Showing alerts within ${widget.responseRadiusKm.toStringAsFixed(0)} km",
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            // Offline fallback - show when map tiles fail to load
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
                                  child: Icon(Icons.navigation,
                                      color: color, size: 32),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(data['userName'] ?? 'Rider',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      Text('${dist < 1 ? '${(dist * 1000).toStringAsFixed(0)}m' : '${dist.toStringAsFixed(1)}km'} away',
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
              ),'''

if old3c in content:
    content = content.replace(old3c, new3c, 1)
    print('Fix 3c (offline fallback) OK')
else:
    print('Fix 3c NOT FOUND')

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print(f'Lines: {len(content.splitlines())}')
