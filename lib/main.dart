import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase Init Error: $e");
  }
  runApp(const SOSApp());
}

class SOSApp extends StatelessWidget {
  const SOSApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, primarySwatch: Colors.red),
      home: const MainSwitcher(),
    );
  }
}

class MainSwitcher extends StatefulWidget {
  const MainSwitcher({super.key});
  @override
  State<MainSwitcher> createState() => _MainSwitcherState();
}

class _MainSwitcherState extends State<MainSwitcher> {
  bool isOfficerMode = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isOfficerMode ? "OFFICER ON-DUTY" : "GUARDIAN SOS"),
        actions: [
          Switch(
              value: isOfficerMode,
              activeThumbColor: Colors.blueAccent,
              onChanged: (v) => setState(() => isOfficerMode = v)),
          const Icon(Icons.security),
          const SizedBox(width: 10),
        ],
      ),
      body: isOfficerMode ? const OfficerDashboard() : const SOSScreen(),
    );
  }
}

class SOSScreen extends StatefulWidget {
  const SOSScreen({super.key});
  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen>
    with SingleTickerProviderStateMixin {
  bool _isHolding = false;
  double _progress = 0.0;
  Timer? _timer;
  late AnimationController _controller;
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _requestLocationPermission();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..addListener(() => setState(() => _progress = _controller.value));
  }

  _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('name') ?? "";
    });
  }

  Future<void> _requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                "Location permission denied. Please enable it in settings.")));
      }
    }
  }

  void _triggerSOS() async {
    _stopHolding();
    Vibration.vibrate(duration: 1000);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Location permission required to send SOS.")));
        }
        return;
      }

      Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      final prefs = await SharedPreferences.getInstance();
      final name = _nameController.text.trim();
      if (name.isNotEmpty) {
        await prefs.setString('name', name);
      }

      await FirebaseFirestore.instance.collection('alerts').add({
        'userName': name.isEmpty ? "Unknown" : name,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'status': 'ACTIVE',
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("🚨 SOS SENT 🚨")));
      }
    } catch (e) {
      debugPrint("SOS Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Failed to send SOS: $e")));
      }
    }
  }

  void _startHolding() {
    setState(() => _isHolding = true);
    _controller.forward();
    _timer = Timer(const Duration(seconds: 3), () {
      if (_isHolding) _triggerSOS();
    });
  }

  void _stopHolding() {
    _timer?.cancel();
    _controller.reset();
    setState(() {
      _isHolding = false;
      _progress = 0.0;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final buttonSize = keyboardOpen ? 150.0 : 200.0;
    final indicatorSize = keyboardOpen ? 185.0 : 250.0;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                    labelText: "Your Name", border: OutlineInputBorder())),
            SizedBox(height: keyboardOpen ? 20 : 60),
            GestureDetector(
              onLongPressStart: (_) => _startHolding(),
              onLongPressEnd: (_) => _stopHolding(),
              onLongPressCancel: () => _stopHolding(),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                      width: indicatorSize,
                      height: indicatorSize,
                      child: CircularProgressIndicator(
                          value: _progress,
                          strokeWidth: 15,
                          color: Colors.red)),
                  Container(
                    width: buttonSize,
                    height: buttonSize,
                    decoration: BoxDecoration(
                        color: _isHolding ? Colors.red[800] : Colors.red,
                        shape: BoxShape.circle),
                    child: Center(
                        child: Text("HOLD\nSOS",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: keyboardOpen ? 24 : 36,
                                fontWeight: FontWeight.bold))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _isHolding ? "Keep holding..." : "Hold for 3 seconds to send SOS",
              style: TextStyle(
                  color: _isHolding ? Colors.red : Colors.grey, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class OfficerDashboard extends StatefulWidget {
  const OfficerDashboard({super.key});
  @override
  State<OfficerDashboard> createState() => _OfficerDashboardState();
}

class _OfficerDashboardState extends State<OfficerDashboard> {
  final MapController _mapCtrl = MapController();
  final AudioPlayer _player = AudioPlayer();
  int _lastCount = 0;

  void _showResolveDialog(BuildContext context, QueryDocumentSnapshot doc) {
    var data = doc.data() as Map<String, dynamic>;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('🚨 Active Alert'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name: ${data['userName'] ?? 'Unknown'}'),
            const SizedBox(height: 8),
            Text('Lat: ${(data['lat'] as double).toStringAsFixed(5)}'),
            Text('Lng: ${(data['lng'] as double).toStringAsFixed(5)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CLOSE', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('alerts')
                  .doc(doc.id)
                  .update({'status': 'RESOLVED'});
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('MARK RESOLVED'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('alerts')
          .where('status', isEqualTo: 'ACTIVE')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var alerts = snapshot.data!.docs;

        if (alerts.length > _lastCount) {
          _player.play(AssetSource('siren.mp3'));
          var data = alerts.last.data() as Map<String, dynamic>;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _mapCtrl.move(LatLng(data['lat'], data['lng']), 17.0);
          });
        }
        _lastCount = alerts.length;

        return Stack(
          children: [
            FlutterMap(
              mapController: _mapCtrl,
              options: const MapOptions(
                  initialCenter: LatLng(-26.107, 28.05), initialZoom: 13),
              children: [
                TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.cyberwarriors.sos'),
                MarkerLayer(
                    markers: alerts.map((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  return Marker(
                      point: LatLng(data['lat'], data['lng']),
                      width: 100,
                      height: 70,
                      child: GestureDetector(
                        onTap: () => _showResolveDialog(context, doc),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning,
                                color: Colors.red, size: 40),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                data['userName'] ?? 'Unknown',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ));
                }).toList()),
              ],
            ),
            if (alerts.isEmpty)
              const Center(
                child: Card(
                  color: Colors.black54,
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text("No active alerts",
                        style: TextStyle(fontSize: 18, color: Colors.white)),
                  ),
                ),
              ),
            if (alerts.isNotEmpty)
              Positioned(
                top: 20,
                left: 20,
                right: 20,
                child: Card(
                  color: Colors.red[900],
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text(
                      "🚨 ${alerts.length} ACTIVE ALERT${alerts.length > 1 ? 'S' : ''} — Tap marker to resolve",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            if (alerts.isNotEmpty)
              Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: const EdgeInsets.all(20)),
                        onPressed: () => launchUrl(Uri.parse(
                            'google.navigation:q=${alerts.first['lat']},${alerts.first['lng']}')),
                        child: const Text("NAVIGATE TO EMERGENCY",
                            style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  )),
          ],
        );
      },
    );
  }
}
