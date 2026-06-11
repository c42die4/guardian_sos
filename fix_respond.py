with open("lib/main.dart", "r", encoding="utf-8") as f:
    content = f.read()
old1 = """                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon:
                                        const Icon(Icons.navigation),
                                    label: const Text("NAVIGATE"),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        padding:
                                            const EdgeInsets.all(12)),
                                    onPressed: () =>
                                        _navigateTo(_selectedAlert!),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon:
                                        const Icon(Icons.check_circle),
                                    label: const Text("RESOLVE"),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        padding:
                                            const EdgeInsets.all(12)),
                                    onPressed: () =>
                                        _resolveAlert(_selectedAlertId!),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.person),
                                    label: const Text("PROFILE"),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            Colors.orange[800],
                                        padding:
                                            const EdgeInsets.all(12)),
                                    onPressed: () {
                                      final profile =
                                          _selectedAlert!['profile'];
                                      if (profile != null) {
                                        _showProfile(
                                            context,
                                            Map<String, dynamic>.from(
                                                profile));
                                      } else {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text(
                                                    "No profile available.")));
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),"""
new1 = """                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.navigation, color: Colors.white),
                                    label: const Text("NAVIGATE", style: TextStyle(color: Colors.white)),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        padding: const EdgeInsets.all(12)),
                                    onPressed: () => _navigateTo(_selectedAlert!),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.directions_run, color: Colors.black),
                                    label: const Text("RESPOND", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange,
                                        padding: const EdgeInsets.all(12)),
                                    onPressed: () => _markResponding(_selectedAlertId!),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.check_circle, color: Colors.white),
                                    label: const Text("RESOLVE", style: TextStyle(color: Colors.white)),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        padding: const EdgeInsets.all(12)),
                                    onPressed: () => _resolveAlert(_selectedAlertId!),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.person, color: Colors.black),
                                    label: const Text("PROFILE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange[700],
                                        padding: const EdgeInsets.all(12)),
                                    onPressed: () {
                                      final profile = _selectedAlert!['profile'];
                                      if (profile != null) {
                                        _showProfile(context, Map<String, dynamic>.from(profile));
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text("No profile available.")));
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),"""
if old1 in content:
    content = content.replace(old1, new1, 1)
    print("Fix 1 OK")
else:
    print("Fix 1 NOT FOUND")
old2 = """                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.navigation,
                                        color: Colors.blue),
                                    onPressed: () {
                                      _selectAlert(doc.id, data);
                                      _navigateTo(data);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                        Icons.check_circle,
                                        color: Colors.green),
                                    onPressed: () =>
                                        _resolveAlert(doc.id),
                                  ),
                                ],
                              ),"""
new2 = """                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.navigation,
                                        color: Colors.blue),
                                    onPressed: () {
                                      _selectAlert(doc.id, data);
                                      _navigateTo(data);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.directions_run,
                                        color: Colors.orange),
                                    onPressed: () => _markResponding(doc.id),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                        Icons.check_circle,
                                        color: Colors.green),
                                    onPressed: () =>
                                        _resolveAlert(doc.id),
                                  ),
                                ],
                              ),"""
if old2 in content:
    content = content.replace(old2, new2, 1)
    print("Fix 2 OK")
else:
    print("Fix 2 NOT FOUND")
print("Lines:", len(content.splitlines()))
with open("lib/main.dart", "w", encoding="utf-8") as f:
    f.write(content)
