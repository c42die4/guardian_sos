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
              activeColor: Colors.blueAccent,
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

  void _triggerSOS() async {
    _stopHolding();
    Vibration.vibrate(duration: 1000);
    Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    await FirebaseFirestore.instance.collection('alerts').add({
      'userName': _nameController.text.isEmpty ? "User" : _nameController.text,
      'lat': pos.latitude,
      'lng': pos.longitude,
      'status': 'ACTIVE',
      'timestamp': FieldValue.serverTimestamp(),
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("🚨 SOS SENT 🚨")));
  }

  void _startHolding() {
    setState(() => _isHolding = true);
    _controller.forward();
    _timer = Timer(
        const Duration(seconds: 3), () => _isHolding ? _triggerSOS() : null);
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
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(30.0),
      child: Column(
        children: [
          TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                  labelText: "Your Name", border: OutlineInputBorder())),
          const Spacer(),
          GestureDetector(
            onTapDown: (_) => _startHolding(),
            onTapUp: (_) => _stopHolding(),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                    width: 250,
                    height: 250,
                    child: CircularProgressIndicator(
                        value: _progress, strokeWidth: 15, color: Colors.red)),
                Container(
                  width: 200,
                  height: 200,
                  decoration: const BoxDecoration(
                      color: Colors.red, shape: BoxShape.circle),
                  child: const Center(
                      child: Text("SOS",
                          style: TextStyle(
                              fontSize: 40, fontWeight: FontWeight.bold))),
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('alerts')
          .where('status', isEqualTo: 'ACTIVE')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
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
                      width: 50,
                      height: 50,
                      child: const Icon(Icons.warning,
                          color: Colors.red, size: 40));
                }).toList()),
              ],
            ),
            if (alerts.isNotEmpty)
              Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.all(20)),
                    onPressed: () => launchUrl(Uri.parse(
                        'google.navigation:q=${alerts.first['lat']},${alerts.first['lng']}')),
                    child: const Text("NAVIGATE TO EMERGENCY"),
                  )),
          ],
        );
      },
    );
  }
}
