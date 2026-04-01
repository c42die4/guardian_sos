import 'dart:async';
import 'dart:math';
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

// ─────────────────────────────────────────────
// DEVICE ID HELPER
// ─────────────────────────────────────────────
Future<String> getDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  String? id = prefs.getString('device_id');
  if (id == null) {
    id = DateTime.now().millisecondsSinceEpoch.toString() +
        Random().nextInt(99999).toString();
    await prefs.setString('device_id', id);
  }
  return id;
}

class SOSApp extends StatelessWidget {
  const SOSApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, primarySwatch: Colors.red),
      home: const AppEntry(),
    );
  }
}

// ─────────────────────────────────────────────
// APP ENTRY — checks if profile exists
// ─────────────────────────────────────────────
class AppEntry extends StatefulWidget {
  const AppEntry({super.key});
  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> {
  bool _loading = true;
  bool _hasProfile = false;

  @override
  void initState() {
    super.initState();
    _checkProfile();
  }

  Future<void> _checkProfile() async {
    final id = await getDeviceId();
    final doc =
        await FirebaseFirestore.instance.collection('profiles').doc(id).get();
    setState(() {
      _hasProfile = doc.exists && (doc.data()?['name'] ?? '').isNotEmpty;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_hasProfile) {
      return const ProfileScreen(isFirstTime: true);
    }
    return const MainSwitcher();
  }
}

// ─────────────────────────────────────────────
// PROFILE SCREEN
// ─────────────────────────────────────────────
class ProfileScreen extends StatefulWidget {
  final bool isFirstTime;
  const ProfileScreen({super.key, this.isFirstTime = false});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _loading = true;

  final _nameCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _bloodTypeCtrl = TextEditingController();
  final _allergiesCtrl = TextEditingController();
  final _conditionsCtrl = TextEditingController();
  final _medicationsCtrl = TextEditingController();
  final _contact1NameCtrl = TextEditingController();
  final _contact1PhoneCtrl = TextEditingController();
  final _contact1RelCtrl = TextEditingController();
  final _contact2NameCtrl = TextEditingController();
  final _contact2PhoneCtrl = TextEditingController();
  final _contact2RelCtrl = TextEditingController();
  final _homeAddressCtrl = TextEditingController();
  final _workAddressCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final id = await getDeviceId();
    final doc =
        await FirebaseFirestore.instance.collection('profiles').doc(id).get();
    if (doc.exists) {
      final d = doc.data()!;
      _nameCtrl.text = d['name'] ?? '';
      _idCtrl.text = d['idNumber'] ?? '';
      _ageCtrl.text = d['age'] ?? '';
      _bloodTypeCtrl.text = d['bloodType'] ?? '';
      _allergiesCtrl.text = d['allergies'] ?? '';
      _conditionsCtrl.text = d['conditions'] ?? '';
      _medicationsCtrl.text = d['medications'] ?? '';
      _contact1NameCtrl.text = d['contact1Name'] ?? '';
      _contact1PhoneCtrl.text = d['contact1Phone'] ?? '';
      _contact1RelCtrl.text = d['contact1Rel'] ?? '';
      _contact2NameCtrl.text = d['contact2Name'] ?? '';
      _contact2PhoneCtrl.text = d['contact2Phone'] ?? '';
      _contact2RelCtrl.text = d['contact2Rel'] ?? '';
      _homeAddressCtrl.text = d['homeAddress'] ?? '';
      _workAddressCtrl.text = d['workAddress'] ?? '';
    }
    setState(() => _loading = false);
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final id = await getDeviceId();
    await FirebaseFirestore.instance.collection('profiles').doc(id).set({
      'name': _nameCtrl.text.trim(),
      'idNumber': _idCtrl.text.trim(),
      'age': _ageCtrl.text.trim(),
      'bloodType': _bloodTypeCtrl.text.trim(),
      'allergies': _allergiesCtrl.text.trim(),
      'conditions': _conditionsCtrl.text.trim(),
      'medications': _medicationsCtrl.text.trim(),
      'contact1Name': _contact1NameCtrl.text.trim(),
      'contact1Phone': _contact1PhoneCtrl.text.trim(),
      'contact1Rel': _contact1RelCtrl.text.trim(),
      'contact2Name': _contact2NameCtrl.text.trim(),
      'contact2Phone': _contact2PhoneCtrl.text.trim(),
      'contact2Rel': _contact2RelCtrl.text.trim(),
      'homeAddress': _homeAddressCtrl.text.trim(),
      'workAddress': _workAddressCtrl.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile saved successfully!")));
      if (widget.isFirstTime) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainSwitcher()));
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.red)),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {TextInputType? keyboardType, bool required = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
            labelText: label + (required ? ' *' : ''),
            border: const OutlineInputBorder()),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
            : null,
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idCtrl.dispose();
    _ageCtrl.dispose();
    _bloodTypeCtrl.dispose();
    _allergiesCtrl.dispose();
    _conditionsCtrl.dispose();
    _medicationsCtrl.dispose();
    _contact1NameCtrl.dispose();
    _contact1PhoneCtrl.dispose();
    _contact1RelCtrl.dispose();
    _contact2NameCtrl.dispose();
    _contact2PhoneCtrl.dispose();
    _contact2RelCtrl.dispose();
    _homeAddressCtrl.dispose();
    _workAddressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isFirstTime ? "Setup Your Profile" : "Edit Profile"),
        leading: widget.isFirstTime ? null : const BackButton(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (widget.isFirstTime)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red[900],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        "Please fill in your profile so emergency responders have the information they need. You can update this anytime.",
                        style: TextStyle(fontSize: 14),
                      ),
                    ),

                  // PERSONAL
                  _sectionHeader("Personal Information", Icons.person),
                  _field("Full Name", _nameCtrl, required: true),
                  _field("ID Number", _idCtrl,
                      keyboardType: TextInputType.number),
                  _field("Age", _ageCtrl, keyboardType: TextInputType.number),
                  _field("Blood Type (e.g. O+)", _bloodTypeCtrl),

                  // MEDICAL
                  _sectionHeader("Medical Information", Icons.medical_services),
                  _field("Allergies", _allergiesCtrl, maxLines: 2),
                  _field("Medical Conditions", _conditionsCtrl, maxLines: 2),
                  _field("Current Medications", _medicationsCtrl, maxLines: 2),

                  // EMERGENCY CONTACTS
                  _sectionHeader("Emergency Contact 1", Icons.contact_phone),
                  _field("Contact Name", _contact1NameCtrl),
                  _field("Phone Number", _contact1PhoneCtrl,
                      keyboardType: TextInputType.phone),
                  _field("Relationship", _contact1RelCtrl),

                  _sectionHeader("Emergency Contact 2", Icons.contact_phone),
                  _field("Contact Name", _contact2NameCtrl),
                  _field("Phone Number", _contact2PhoneCtrl,
                      keyboardType: TextInputType.phone),
                  _field("Relationship", _contact2RelCtrl),

                  // LOCATION
                  _sectionHeader("Addresses", Icons.home),
                  _field("Home Address", _homeAddressCtrl, maxLines: 2),
                  _field("Work Address", _workAddressCtrl, maxLines: 2),

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save),
                      label: Text(_saving ? "Saving..." : "SAVE PROFILE",
                          style: const TextStyle(fontSize: 16)),
                      style:
                          ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: _saving ? null : _saveProfile,
                    ),
                  ),

                  if (widget.isFirstTime)
                    TextButton(
                      onPressed: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                              builder: (_) => const MainSwitcher())),
                      child: const Text("Skip for now",
                          style: TextStyle(color: Colors.grey)),
                    ),
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────
// MAIN SWITCHER
// ─────────────────────────────────────────────
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
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(isOfficerMode ? "OFFICER ON-DUTY" : "GUARDIAN SOS"),
        actions: [
          if (!isOfficerMode)
            IconButton(
              icon: const Icon(Icons.person),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ProfileScreen(isFirstTime: false))),
            ),
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

// ─────────────────────────────────────────────
// SOS SCREEN
// ─────────────────────────────────────────────
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
  Timer? _heartbeatTimer;
  late AnimationController _controller;
  final _nameController = TextEditingController();
  String? _activeAlertId;

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
    // Also load from Firestore profile
    final id = await getDeviceId();
    final doc =
        await FirebaseFirestore.instance.collection('profiles').doc(id).get();
    if (doc.exists && mounted) {
      setState(() {
        _nameController.text = doc.data()?['name'] ?? _nameController.text;
      });
    }
  }

  Future<void> _requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              "Location permission denied. Please enable it in settings.")));
    }
  }

  Future<Map<String, dynamic>> _getProfileSnapshot() async {
    final id = await getDeviceId();
    final doc =
        await FirebaseFirestore.instance.collection('profiles').doc(id).get();
    if (doc.exists) return doc.data()!;
    return {
      'name': _nameController.text.isEmpty ? 'User' : _nameController.text
    };
  }

  void _triggerSOS() async {
    _stopHolding();
    Vibration.vibrate(duration: 1000);

    try {
      Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      final profile = await _getProfileSnapshot();

      DocumentReference doc =
          await FirebaseFirestore.instance.collection('alerts').add({
        'userName': profile['name'] ?? 'User',
        'lat': pos.latitude,
        'lng': pos.longitude,
        'status': 'ACTIVE',
        'timestamp': FieldValue.serverTimestamp(),
        'profile': profile,
      });

      _activeAlertId = doc.id;
      _startHeartbeat();

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

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (timer) async {
      if (_activeAlertId == null) return;
      try {
        Position pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        await FirebaseFirestore.instance
            .collection('alerts')
            .doc(_activeAlertId)
            .update({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint("Heartbeat error: $e");
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _activeAlertId = null;
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
    _stopHeartbeat();
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
                readOnly: true,
                decoration: const InputDecoration(
                    labelText: "Your Name",
                    border: OutlineInputBorder(),
                    helperText: "Update your name in Profile")),
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

// ─────────────────────────────────────────────
// OFFICER DASHBOARD
// ─────────────────────────────────────────────
class OfficerDashboard extends StatefulWidget {
  const OfficerDashboard({super.key});
  @override
  State<OfficerDashboard> createState() => _OfficerDashboardState();
}

class _OfficerDashboardState extends State<OfficerDashboard> {
  final MapController _mapCtrl = MapController();
  final AudioPlayer _player = AudioPlayer();
  int _lastCount = 0;

  Map<String, dynamic>? _selectedAlert;
  String? _selectedAlertId;
  bool _panelOpen = false;

  void _selectAlert(String id, Map<String, dynamic> data) {
    setState(() {
      _selectedAlertId = id;
      _selectedAlert = data;
      _panelOpen = false;
    });
    _mapCtrl.move(LatLng(data['lat'], data['lng']), 17.0);
  }

  void _navigateTo(Map<String, dynamic> data) {
    launchUrl(Uri.parse('google.navigation:q=${data['lat']},${data['lng']}'));
  }

  Future<void> _resolveAlert(String id) async {
    await FirebaseFirestore.instance
        .collection('alerts')
        .doc(id)
        .update({'status': 'RESOLVED'});
    setState(() {
      _selectedAlert = null;
      _selectedAlertId = null;
    });
  }

  String _lastSeen(dynamic timestamp) {
    if (timestamp == null) return "Last seen just now";
    final dt = (timestamp as Timestamp).toDate();
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return "Last seen ${diff.inSeconds}s ago";
    if (diff.inMinutes < 60) return "Last seen ${diff.inMinutes}m ago";
    return "Last seen ${diff.inHours}h ago";
  }

  void _showProfile(BuildContext context, Map<String, dynamic> profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text("Emergency Profile",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Divider(height: 24),

            // PERSONAL
            _profileSection("Personal Information", Icons.person, [
              _profileRow("Name", profile['name']),
              _profileRow("ID Number", profile['idNumber']),
              _profileRow("Age", profile['age']),
              _profileRow("Blood Type", profile['bloodType']),
            ]),

            // MEDICAL
            _profileSection("Medical Information", Icons.medical_services, [
              _profileRow("Allergies", profile['allergies']),
              _profileRow("Conditions", profile['conditions']),
              _profileRow("Medications", profile['medications']),
            ]),

            // EMERGENCY CONTACTS
            _profileSection("Emergency Contacts", Icons.contact_phone, [
              if ((profile['contact1Name'] ?? '').isNotEmpty) ...[
                _profileRow("Contact 1", profile['contact1Name']),
                _profileRow("Relationship", profile['contact1Rel']),
                _callableRow(context, "Phone", profile['contact1Phone']),
              ],
              if ((profile['contact2Name'] ?? '').isNotEmpty) ...[
                const Divider(),
                _profileRow("Contact 2", profile['contact2Name']),
                _profileRow("Relationship", profile['contact2Rel']),
                _callableRow(context, "Phone", profile['contact2Phone']),
              ],
            ]),

            // ADDRESSES
            _profileSection("Addresses", Icons.home, [
              _profileRow("Home", profile['homeAddress']),
              _profileRow("Work", profile['workAddress']),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _profileSection(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(icon, color: Colors.red, size: 18),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.red)),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _profileRow(String label, dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }

  Widget _callableRow(BuildContext context, String label, dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
              width: 110,
              child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
          IconButton(
            icon: const Icon(Icons.call, color: Colors.green, size: 22),
            onPressed: () => launchUrl(Uri.parse('tel:$text')),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
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
          .orderBy('timestamp', descending: false)
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
            // ── MAP ──
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
                    final isSelected = doc.id == _selectedAlertId;
                    return Marker(
                      point: LatLng(data['lat'], data['lng']),
                      width: 60,
                      height: 70,
                      child: GestureDetector(
                        onTap: () => _selectAlert(doc.id, data),
                        child: Column(
                          children: [
                            Icon(Icons.warning,
                                color: isSelected ? Colors.orange : Colors.red,
                                size: isSelected ? 48 : 40),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                data['userName'] ?? 'User',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),

            // ── NO ALERTS ──
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

            // ── ALERT COUNT BANNER ──
            if (alerts.isNotEmpty)
              Positioned(
                top: 20,
                left: 20,
                right: 20,
                child: GestureDetector(
                  onTap: () => setState(() => _panelOpen = !_panelOpen),
                  child: Card(
                    color: Colors.red[900],
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.list, color: Colors.white),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              "🚨 ${alerts.length} ACTIVE ALERT${alerts.length > 1 ? 'S' : ''} — Tap to view list",
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // ── SELECTED ALERT POPUP ──
            if (_selectedAlert != null)
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
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.warning,
                                    color: Colors.red, size: 28),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _selectedAlert!['userName'] ?? 'User',
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () =>
                                      setState(() => _selectedAlert = null),
                                ),
                              ],
                            ),
                            Text(
                              "📍 ${_selectedAlert!['lat'].toStringAsFixed(5)}, ${_selectedAlert!['lng'].toStringAsFixed(5)}",
                              style: const TextStyle(color: Colors.grey),
                            ),
                            Text(
                              _lastSeen(_selectedAlert!['timestamp']),
                              style: const TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.navigation),
                                    label: const Text("NAVIGATE"),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        padding: const EdgeInsets.all(12)),
                                    onPressed: () =>
                                        _navigateTo(_selectedAlert!),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.check_circle),
                                    label: const Text("RESOLVE"),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        padding: const EdgeInsets.all(12)),
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
                                        backgroundColor: Colors.orange[800],
                                        padding: const EdgeInsets.all(12)),
                                    onPressed: () {
                                      final profile =
                                          _selectedAlert!['profile'];
                                      if (profile != null) {
                                        _showProfile(context,
                                            Map<String, dynamic>.from(profile));
                                      } else {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text(
                                                    "No profile available for this alert.")));
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // ── ALERT LIST PANEL ──
            if (_panelOpen && alerts.isNotEmpty)
              Positioned(
                top: 90,
                left: 16,
                right: 16,
                child: Card(
                  color: Colors.grey[900],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            const Text("Active Alerts",
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  setState(() => _panelOpen = false),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 300),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: alerts.length,
                          itemBuilder: (context, index) {
                            var doc = alerts[index];
                            var data = doc.data() as Map<String, dynamic>;
                            final isSelected = doc.id == _selectedAlertId;
                            return ListTile(
                              leading: Icon(Icons.warning,
                                  color:
                                      isSelected ? Colors.orange : Colors.red),
                              title: Text(data['userName'] ?? 'User',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal)),
                              subtitle: Text(_lastSeen(data['timestamp'])),
                              trailing: Row(
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
                                    icon: const Icon(Icons.check_circle,
                                        color: Colors.green),
                                    onPressed: () => _resolveAlert(doc.id),
                                  ),
                                ],
                              ),
                              onTap: () => _selectAlert(doc.id, data),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
