import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

// ─────────────────────────────────────────────
// NOTIFICATIONS
// ─────────────────────────────────────────────
final FlutterLocalNotificationsPlugin _notifications =
    FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings settings =
      InitializationSettings(android: androidSettings);
  await _notifications.initialize(settings);

  // Create notification channel with siren sound
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'sos_alerts',
    'SOS Alerts',
    description: 'Emergency SOS alerts',
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('siren'),
    enableVibration: true,
  );
  await _notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

Future<void> showAlertNotification(String name, String location) async {
  final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'sos_alerts',
    'SOS Alerts',
    channelDescription: 'Emergency SOS alerts',
    importance: Importance.max,
    priority: Priority.high,
    sound: const RawResourceAndroidNotificationSound('siren'),
    playSound: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 500, 200, 500, 200, 500]),
    fullScreenIntent: true,
  );
  final NotificationDetails details =
      NotificationDetails(android: androidDetails);
  await _notifications.show(
    0,
    '🚨 SOS ALERT — $name',
    '📍 $location',
    details,
  );
}

// ─────────────────────────────────────────────
// FOREGROUND TASK HANDLER
// ─────────────────────────────────────────────
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTaskHandler());
}

class LocationTaskHandler extends TaskHandler {
  String? _alertId;
  String? _companyId;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Firebase init in task: $e');
    }
    _alertId = await FlutterForegroundTask.getData<String>(key: 'alertId');
    _companyId = await FlutterForegroundTask.getData<String>(key: 'companyId');
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    if (_alertId == null) return;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) return;

      Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      await FirebaseFirestore.instance
          .collection('alerts')
          .doc(_alertId)
          .update({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'timestamp': FieldValue.serverTimestamp(),
      });

      FlutterForegroundTask.updateService(
        notificationTitle: '🚨 SOS Active',
        notificationText: 'SOS Active — Sharing your location with officers',
      );
    } catch (e) {
      debugPrint('Location task error: $e');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {}
}

// ─────────────────────────────────────────────
// FOREGROUND SERVICE HELPERS
// ─────────────────────────────────────────────
void initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'sos_tracking',
      channelName: 'SOS Tracking',
      channelDescription: 'Tracks your location during an active SOS',
      channelImportance: NotificationChannelImportance.HIGH,
      priority: NotificationPriority.HIGH,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: true,
      playSound: true,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(30000),
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}

Future<void> startLocationService(String alertId, String companyId) async {
  await FlutterForegroundTask.saveData(key: 'alertId', value: alertId);
  await FlutterForegroundTask.saveData(key: 'companyId', value: companyId);

  if (await FlutterForegroundTask.isRunningService) {
    await FlutterForegroundTask.restartService();
  } else {
    await FlutterForegroundTask.startService(
      notificationTitle: '🚨 SOS Active',
      notificationText: 'Sharing your location with officers...',
      callback: startCallback,
    );
  }
}

Future<void> stopLocationService() async {
  await FlutterForegroundTask.stopService();
}

// ─────────────────────────────────────────────
// COMPANY CONFIG MODEL
// ─────────────────────────────────────────────
class CompanyConfig {
  final String id;
  final String name;
  final String logoUrl;
  final Color primaryColor;
  final bool isActive;
  final int maxDevices;
  final String emergencyPhone;

  CompanyConfig({
    required this.id,
    required this.name,
    required this.logoUrl,
    required this.primaryColor,
    required this.isActive,
    required this.maxDevices,
    required this.emergencyPhone,
  });

  factory CompanyConfig.fromFirestore(String id, Map<String, dynamic> data) {
    Color color = Colors.red;
    try {
      final hex =
          data['primaryColor']?.toString().replaceAll('#', '') ?? 'FF0000';
      color = Color(int.parse('FF$hex', radix: 16));
    } catch (_) {}
    return CompanyConfig(
      id: id,
      name: data['name'] ?? 'Guardian SOS',
      logoUrl: data['logoUrl'] ?? '',
      primaryColor: color,
      isActive: data['isActive'] ?? true,
      maxDevices: data['maxDevices'] ?? 10,
      emergencyPhone: data['emergencyPhone'] ?? '',
    );
  }
}

CompanyConfig? currentCompany;
String currentRole = 'client';

// ─────────────────────────────────────────────
// HELPERS
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

Future<String?> getSavedCompanyId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('company_id');
}

Future<void> saveCompanyId(String companyId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('company_id', companyId);
}

Future<String> getSavedRole() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('device_role') ?? 'client';
}

Future<void> saveRole(String role) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('device_role', role);
}

// Save full company data locally so app works offline
Future<void> saveCompanyData(CompanyConfig company) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('company_name', company.name);
  await prefs.setString('company_logo', company.logoUrl);
  await prefs.setString('company_color',
      company.primaryColor.value.toRadixString(16));
  await prefs.setBool('company_active', company.isActive);
  await prefs.setInt('company_max_devices', company.maxDevices);
  await prefs.setString('company_phone', company.emergencyPhone);
}

Future<CompanyConfig?> getCompanyData(String companyId) async {
  final prefs = await SharedPreferences.getInstance();
  final name = prefs.getString('company_name');
  if (name == null) return null;
  Color color = Colors.red;
  try {
    final hex = prefs.getString('company_color') ?? 'ffcc0000';
    color = Color(int.parse(hex, radix: 16));
  } catch (_) {}
  return CompanyConfig(
    id: companyId,
    name: name,
    logoUrl: prefs.getString('company_logo') ?? '',
    primaryColor: color,
    isActive: prefs.getBool('company_active') ?? true,
    maxDevices: prefs.getInt('company_max_devices') ?? 10,
    emergencyPhone: prefs.getString('company_phone') ?? '',
  );
}

Future<void> sendWhatsAppAlert({
  required String phone,
  required String userName,
  required double lat,
  required double lng,
}) async {
  try {
    final whatsappCheck = Uri.parse('whatsapp://send');
    if (!await canLaunchUrl(whatsappCheck)) {
      debugPrint('WhatsApp not installed, skipping alert');
      return;
    }
    String cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleaned.startsWith('0')) {
      cleaned = '+27${cleaned.substring(1)}';
    }
    cleaned = cleaned.replaceAll('+', '');
    final mapsLink = 'https://www.google.com/maps?q=$lat,$lng';
    final message = Uri.encodeComponent(
        '🚨 EMERGENCY ALERT 🚨\n\n'
        '$userName needs urgent help!\n\n'
        '📍 Location: $mapsLink\n\n'
        'Please respond immediately or call emergency services.');
    final url = 'whatsapp://send?phone=$cleaned&text=$message';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      await Future.delayed(const Duration(seconds: 2));
    }
  } catch (e) {
    debugPrint('WhatsApp alert error: $e');
  }
}

// ─────────────────────────────────────────────
// CONNECTIVITY
// ─────────────────────────────────────────────
Future<bool> hasInternet() async {
  try {
    final socket = await Socket.connect('8.8.8.8', 53,
        timeout: const Duration(seconds: 3));
    socket.destroy();
    return true;
  } catch (e) {
    return false;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase Init Error: $e");
  }
  await initNotifications();
  initForegroundTask();
  runApp(const SOSApp());
}

class SOSApp extends StatelessWidget {
  const SOSApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Secure Response',
      theme: ThemeData(brightness: Brightness.dark, primarySwatch: Colors.red),
      home: const AppEntry(),
    );
  }
}

// ─────────────────────────────────────────────
// APP ENTRY
// ─────────────────────────────────────────────
class AppEntry extends StatefulWidget {
  const AppEntry({super.key});
  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final companyId = await getSavedCompanyId();
      if (companyId == null) {
        setState(() => _loading = false);
        return;
      }

      // Always load from SharedPreferences first — works offline instantly
      currentRole = await getSavedRole();
      currentCompany = await getCompanyData(companyId);

      // Show app immediately with cached data
      setState(() => _loading = false);

      // Then try to refresh from Firestore in background if online
      final connected = await hasInternet();
      if (!connected) return;

      try {
        final doc = await FirebaseFirestore.instance
            .collection('companies')
            .doc(companyId)
            .get()
            .timeout(const Duration(seconds: 8));
        if (!doc.exists) return;
        final company = CompanyConfig.fromFirestore(doc.id, doc.data()!);
        await saveCompanyData(company);
        if (mounted) setState(() => currentCompany = company);

        final deviceId = await getDeviceId();
        FirebaseFirestore.instance
            .collection('devices')
            .doc(deviceId)
            .update({'lastSeen': FieldValue.serverTimestamp()})
            .catchError((_) {});
      } catch (e) {
        debugPrint("Background refresh error: $e");
      }
    } catch (e) {
      debugPrint("Init error: $e");
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.red),
              SizedBox(height: 16),
              Text("Connecting...", style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }
    if (currentCompany == null) {
      return const CompanyRegistrationScreen();
    }
    if (!currentCompany!.isActive) {
      return SubscriptionSuspendedScreen(company: currentCompany!);
    }
    return AppShell(company: currentCompany!);
  }
}

// ─────────────────────────────────────────────
// COMPANY REGISTRATION SCREEN
// ─────────────────────────────────────────────
class CompanyRegistrationScreen extends StatefulWidget {
  const CompanyRegistrationScreen({super.key});
  @override
  State<CompanyRegistrationScreen> createState() =>
      _CompanyRegistrationScreenState();
}

class _CompanyRegistrationScreenState
    extends State<CompanyRegistrationScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _register() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = "Please enter a registration code");
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var query = await FirebaseFirestore.instance
          .collection('companies')
          .where('officerCode', isEqualTo: code)
          .limit(1)
          .get();

      String role = 'officer';

      if (query.docs.isEmpty) {
        query = await FirebaseFirestore.instance
            .collection('companies')
            .where('clientCode', isEqualTo: code)
            .limit(1)
            .get();
        role = 'client';
      }

      if (query.docs.isEmpty) {
        setState(() {
          _error =
              "Invalid registration code. Please contact your company administrator.";
          _loading = false;
        });
        return;
      }

      final companyDoc = query.docs.first;
      final company =
          CompanyConfig.fromFirestore(companyDoc.id, companyDoc.data());

      if (!company.isActive) {
        setState(() {
          _error =
              "This company's subscription is suspended. Please contact your administrator.";
          _loading = false;
        });
        return;
      }

      final deviceId = await getDeviceId();

      if (role == 'officer') {
        final officerDevices = await FirebaseFirestore.instance
            .collection('devices')
            .where('companyId', isEqualTo: companyDoc.id)
            .where('role', isEqualTo: 'officer')
            .where('isActive', isEqualTo: true)
            .get();

        final existingDevice = await FirebaseFirestore.instance
            .collection('devices')
            .doc(deviceId)
            .get();

        if (!existingDevice.exists &&
            officerDevices.docs.length >= company.maxDevices) {
          setState(() {
            _error =
                "Maximum officer device limit reached (${company.maxDevices} devices). Please contact your administrator.";
            _loading = false;
          });
          return;
        }
      }

      await FirebaseFirestore.instance
          .collection('devices')
          .doc(deviceId)
          .set({
        'companyId': companyDoc.id,
        'role': role,
        'registeredAt': FieldValue.serverTimestamp(),
        'lastSeen': FieldValue.serverTimestamp(),
        'isActive': true,
      });

      await saveCompanyId(companyDoc.id);
      await saveRole(role);
      await saveCompanyData(company);
      currentCompany = company;
      currentRole = role;

      if (mounted) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => AppShell(company: company)));
      }
    } catch (e) {
      setState(() {
        _error = "An error occurred. Please try again.";
        _loading = false;
      });
      debugPrint("Registration error: $e");
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield, size: 80, color: Colors.red),
              const SizedBox(height: 16),
              const Text("Welcome",
                  style:
                      TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                "Enter the registration code provided by your administrator.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 15),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _codeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: "Registration Code",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.vpn_key),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.red[900],
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(_error!, style: const TextStyle(fontSize: 13)),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  icon: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.login),
                  label: Text(_loading ? "Registering..." : "REGISTER DEVICE",
                      style: const TextStyle(fontSize: 16)),
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: _loading ? null : _register,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SUBSCRIPTION SUSPENDED SCREEN
// ─────────────────────────────────────────────
class SubscriptionSuspendedScreen extends StatelessWidget {
  final CompanyConfig company;
  const SubscriptionSuspendedScreen({super.key, required this.company});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.block, size: 80, color: Colors.orange),
              const SizedBox(height: 24),
              Text(company.name,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              const Text("Your subscription has been suspended.",
                  style: TextStyle(fontSize: 18, color: Colors.orange),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              const Text(
                "Please contact support to restore access.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 15),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.call),
                  label: const Text("CONTACT SUPPORT",
                      style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[800]),
                  onPressed: () => launchUrl(Uri.parse('tel:+27000000000')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// APP SHELL
// ─────────────────────────────────────────────
class AppShell extends StatefulWidget {
  final CompanyConfig company;
  const AppShell({super.key, required this.company});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool isOfficerMode = false;
  bool _checkingProfile = true;

  @override
  void initState() {
    super.initState();
    _checkProfile();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }

  Future<void> _checkProfile() async {
    final id = await getDeviceId();
    final doc = await FirebaseFirestore.instance
        .collection('profiles')
        .doc(id)
        .get();
    final hasProfile =
        doc.exists && (doc.data()?['name'] ?? '').isNotEmpty;
    setState(() => _checkingProfile = false);
    if (!hasProfile && mounted) {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const ProfileScreen(isFirstTime: true)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOfficer = currentRole == 'officer';

    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        primaryColor: widget.company.primaryColor,
        colorScheme: ColorScheme.dark(primary: widget.company.primaryColor),
        appBarTheme: AppBarTheme(
          backgroundColor: widget.company.primaryColor.withOpacity(0.2),
        ),
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Row(
            children: [
              if (widget.company.logoUrl.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Image.network(
                    widget.company.logoUrl,
                    height: 32,
                    width: 32,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(Icons.security,
                        color: widget.company.primaryColor),
                  ),
                ),
              Flexible(
                child: Text(
                  isOfficer && isOfficerMode
                      ? "${widget.company.name} — OFFICER"
                      : widget.company.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          actions: [
            if (!isOfficerMode)
              IconButton(
                icon: const Icon(Icons.person),
                onPressed: () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const ProfileScreen(isFirstTime: false)));
                  setState(() {});
                },
              ),
            if (isOfficer) ...[
              Switch(
                  value: isOfficerMode,
                  activeThumbColor: Colors.blueAccent,
                  onChanged: (v) => setState(() => isOfficerMode = v)),
              const Icon(Icons.security),
              const SizedBox(width: 10),
            ],
          ],
        ),
        body: _checkingProfile
            ? const Center(child: CircularProgressIndicator())
            : isOfficer && isOfficerMode
                ? OfficerDashboard(company: widget.company)
                : SOSScreen(company: widget.company),
      ),
    );
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
  final _wa1NameCtrl = TextEditingController();
  final _wa1PhoneCtrl = TextEditingController();
  final _wa2NameCtrl = TextEditingController();
  final _wa2PhoneCtrl = TextEditingController();
  final _wa3NameCtrl = TextEditingController();
  final _wa3PhoneCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final id = await getDeviceId();
    final doc = await FirebaseFirestore.instance
        .collection('profiles')
        .doc(id)
        .get();
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
      _wa1NameCtrl.text = d['wa1Name'] ?? '';
      _wa1PhoneCtrl.text = d['wa1Phone'] ?? '';
      _wa2NameCtrl.text = d['wa2Name'] ?? '';
      _wa2PhoneCtrl.text = d['wa2Phone'] ?? '';
      _wa3NameCtrl.text = d['wa3Name'] ?? '';
      _wa3PhoneCtrl.text = d['wa3Phone'] ?? '';
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
      'wa1Name': _wa1NameCtrl.text.trim(),
      'wa1Phone': _wa1PhoneCtrl.text.trim(),
      'wa2Name': _wa2NameCtrl.text.trim(),
      'wa2Phone': _wa2PhoneCtrl.text.trim(),
      'wa3Name': _wa3NameCtrl.text.trim(),
      'wa3Phone': _wa3PhoneCtrl.text.trim(),
      'companyId': currentCompany?.id ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile saved successfully!")));
      Navigator.of(context).pop();
    }
  }

  Widget _sectionHeader(String title, IconData icon, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {TextInputType? keyboardType,
      bool required = false,
      int maxLines = 1}) {
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

  Widget _waContactBlock(String label, TextEditingController nameCtrl,
      TextEditingController phoneCtrl) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[700]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person, color: Colors.green, size: 16),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      color: Colors.green, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: nameCtrl,
            decoration: const InputDecoration(
                labelText: "Name",
                border: OutlineInputBorder(),
                isDense: true),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                labelText: "WhatsApp Number (e.g. 0821234567)",
                border: OutlineInputBorder(),
                isDense: true),
          ),
        ],
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
    _wa1NameCtrl.dispose();
    _wa1PhoneCtrl.dispose();
    _wa2NameCtrl.dispose();
    _wa2PhoneCtrl.dispose();
    _wa3NameCtrl.dispose();
    _wa3PhoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.isFirstTime ? "Setup Your Profile" : "Edit Profile"),
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
                          borderRadius: BorderRadius.circular(8)),
                      child: const Text(
                        "Please fill in your profile so emergency responders have the information they need.",
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  _sectionHeader("Personal Information", Icons.person),
                  _field("Full Name", _nameCtrl, required: true),
                  _field("ID Number", _idCtrl,
                      keyboardType: TextInputType.number),
                  _field("Age", _ageCtrl,
                      keyboardType: TextInputType.number),
                  _field("Blood Type (e.g. O+)", _bloodTypeCtrl),
                  _sectionHeader(
                      "Medical Information", Icons.medical_services),
                  _field("Allergies", _allergiesCtrl, maxLines: 2),
                  _field("Medical Conditions", _conditionsCtrl, maxLines: 2),
                  _field("Current Medications", _medicationsCtrl, maxLines: 2),
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
                  _sectionHeader("Addresses", Icons.home),
                  _field("Home Address", _homeAddressCtrl, maxLines: 2),
                  _field("Work Address", _workAddressCtrl, maxLines: 2),
                  _sectionHeader(
                    "WhatsApp Emergency Contacts",
                    Icons.chat,
                    subtitle:
                        "These contacts receive a WhatsApp message with your location when you trigger SOS.",
                  ),
                  _waContactBlock("Contact 1", _wa1NameCtrl, _wa1PhoneCtrl),
                  _waContactBlock("Contact 2", _wa2NameCtrl, _wa2PhoneCtrl),
                  _waContactBlock("Contact 3", _wa3NameCtrl, _wa3PhoneCtrl),
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
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red),
                      onPressed: _saving ? null : _saveProfile,
                    ),
                  ),
                  if (widget.isFirstTime)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
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
// SOS ACTIVE SCREEN
// ─────────────────────────────────────────────
class SOSActiveScreen extends StatefulWidget {
  final CompanyConfig company;
  final String alertId;
  final Map<String, dynamic> profile;
  final double lat;
  final double lng;
  final VoidCallback onCancel;

  const SOSActiveScreen({
    super.key,
    required this.company,
    required this.alertId,
    required this.profile,
    required this.lat,
    required this.lng,
    required this.onCancel,
  });

  @override
  State<SOSActiveScreen> createState() => _SOSActiveScreenState();
}

class _SOSActiveScreenState extends State<SOSActiveScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late Timer _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulseAnimation =
        Tween<double>(begin: 0.85, end: 1.0).animate(_pulseController);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _timer.cancel();
    super.dispose();
  }

  String get _elapsed {
    final m = _seconds ~/ 60;
    final s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  List<String> get _notifiedContacts {
    final contacts = <String>[];
    if ((widget.profile['wa1Name'] ?? '').isNotEmpty)
      contacts.add(widget.profile['wa1Name']);
    if ((widget.profile['wa2Name'] ?? '').isNotEmpty)
      contacts.add(widget.profile['wa2Name']);
    if ((widget.profile['wa3Name'] ?? '').isNotEmpty)
      contacts.add(widget.profile['wa3Name']);
    return contacts;
  }

  Future<void> _cancelSOS() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Cancel SOS?"),
        content: const Text(
            "Are you sure you want to cancel the active SOS alert?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("No, keep active",
                style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Yes, cancel SOS"),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('alerts')
          .doc(widget.alertId)
          .update({'status': 'CANCELLED'});
      await stopLocationService();
      Vibration.vibrate(duration: 300);
      widget.onCancel();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to cancel SOS: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.company.primaryColor;
    final contacts = _notifiedContacts;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              Row(
                children: [
                  if (widget.company.logoUrl.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Image.network(
                        widget.company.logoUrl,
                        height: 32,
                        width: 32,
                        errorBuilder: (_, __, ___) =>
                            Icon(Icons.security, color: color),
                      ),
                    ),
                  Flexible(
                    child: Text(
                      widget.company.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red[900],
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.6),
                        blurRadius: 40,
                        spreadRadius: 10,
                      )
                    ],
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.warning, color: Colors.white, size: 48),
                      SizedBox(height: 8),
                      Text("SOS ACTIVE",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Help is on the way!",
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                "Stay calm. Your location is being tracked and shared with responding officers.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
              const SizedBox(height: 20),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer, color: Colors.grey, size: 18),
                    const SizedBox(width: 8),
                    Text("SOS active for $_elapsed",
                        style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (contacts.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[900]!.withOpacity(0.3),
                    border: Border.all(color: Colors.green[700]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.chat, color: Colors.green, size: 16),
                          SizedBox(width: 6),
                          Text("WhatsApp alerts sent to:",
                              style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...contacts.map((c) => Text("• $c",
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13))),
                    ],
                  ),
                ),
              const Spacer(),
              if (widget.company.emergencyPhone.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.call),
                    label: Text("CALL ${widget.company.name.toUpperCase()}",
                        style: const TextStyle(fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        padding: const EdgeInsets.all(14)),
                    onPressed: () => launchUrl(
                        Uri.parse('tel:${widget.company.emergencyPhone}')),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.cancel),
                  label: const Text("CANCEL SOS",
                      style: TextStyle(fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[800],
                      padding: const EdgeInsets.all(14)),
                  onPressed: _cancelSOS,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SOS SCREEN
// ─────────────────────────────────────────────
class SOSScreen extends StatefulWidget {
  final CompanyConfig company;
  const SOSScreen({super.key, required this.company});
  @override
  State<SOSScreen> createState() => _SOSScreenState();
}

class _SOSScreenState extends State<SOSScreen>
    with SingleTickerProviderStateMixin {
  bool _isHolding = false;
  bool _sosActive = false;
  double _progress = 0.0;
  Timer? _timer;
  late AnimationController _controller;
  final _nameController = TextEditingController();
  String? _activeAlertId;
  Map<String, dynamic> _lastProfile = {};
  double _lastLat = 0;
  double _lastLng = 0;
  bool _hasInternet = true;
  Timer? _connectivityTimer;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _checkConnectivity();
    _connectivityTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => _checkConnectivity());
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..addListener(() => setState(() => _progress = _controller.value));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadProfile();
  }

  Future<void> _checkConnectivity() async {
    final connected = await hasInternet();
    if (mounted) setState(() => _hasInternet = connected);
  }

  _loadProfile() async {
    final id = await getDeviceId();
    final doc = await FirebaseFirestore.instance
        .collection('profiles')
        .doc(id)
        .get();
    if (doc.exists && mounted) {
      setState(() => _nameController.text = doc.data()?['name'] ?? '');
    }
  }

  Future<Map<String, dynamic>> _getProfileSnapshot() async {
    final id = await getDeviceId();
    final doc = await FirebaseFirestore.instance
        .collection('profiles')
        .doc(id)
        .get();
    if (doc.exists) return doc.data()!;
    return {
      'name': _nameController.text.isEmpty ? 'User' : _nameController.text
    };
  }

  Future<void> _sendWhatsAppAlerts(
      Map<String, dynamic> profile, double lat, double lng) async {
    final userName = profile['name'] ?? 'User';
    final contacts = [
      {'name': profile['wa1Name'], 'phone': profile['wa1Phone']},
      {'name': profile['wa2Name'], 'phone': profile['wa2Phone']},
      {'name': profile['wa3Name'], 'phone': profile['wa3Phone']},
    ];
    for (final contact in contacts) {
      final phone = (contact['phone'] ?? '').toString().trim();
      if (phone.isNotEmpty) {
        await sendWhatsAppAlert(
          phone: phone,
          userName: userName,
          lat: lat,
          lng: lng,
        );
      }
    }
  }

  void _triggerSOS() async {
    _stopHolding();

    // Check internet connectivity first
    final connected = await hasInternet();
    if (!connected) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Row(
              children: [
                Icon(Icons.wifi_off, color: Colors.red, size: 24),
                SizedBox(width: 8),
                Text('No Internet Connection'),
              ],
            ),
            content: const Text(
              'Cannot send SOS — your phone has no internet connection.\n\n'
              'Please enable WiFi or mobile data, then try again.\n\n'
              'You can still call emergency services directly.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.call),
                label: const Text('Call 112'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  launchUrl(Uri.parse('tel:112'));
                },
              ),
            ],
          ),
        );
      }
      return;
    }

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
        'companyId': widget.company.id,
      });

      _activeAlertId = doc.id;
      _lastProfile = profile;
      _lastLat = pos.latitude;
      _lastLng = pos.longitude;

      await startLocationService(doc.id, widget.company.id);

      if (mounted) {
        setState(() => _sosActive = true);
      }

      await _sendWhatsAppAlerts(profile, pos.latitude, pos.longitude);
    } catch (e) {
      debugPrint("SOS Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Failed to send SOS: $e")));
      }
    }
  }

  void _onSOSCancelled() {
    setState(() => _sosActive = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("SOS cancelled.")));
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
    _connectivityTimer?.cancel();
    _controller.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_sosActive && _activeAlertId != null) {
      return SOSActiveScreen(
        company: widget.company,
        alertId: _activeAlertId!,
        profile: _lastProfile,
        lat: _lastLat,
        lng: _lastLng,
        onCancel: _onSOSCancelled,
      );
    }

    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final buttonSize = keyboardOpen ? 150.0 : 200.0;
    final indicatorSize = keyboardOpen ? 185.0 : 250.0;
    final color = widget.company.primaryColor;

    return Column(
      children: [
        if (!_hasInternet)
          Container(
            width: double.infinity,
            color: Colors.red[900],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.wifi_off, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '⚠️ No internet — SOS will not work. Enable WiFi or mobile data.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(30.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: "Your Name",
                      border: const OutlineInputBorder(),
                      helperText: _nameController.text.isEmpty
                          ? "⚠️ Please enter your name before sending SOS"
                          : "Also editable in Profile",
                    ),
                    onChanged: (val) async {
                      final id = await getDeviceId();
                      await FirebaseFirestore.instance
                          .collection('profiles')
                          .doc(id)
                          .set({'name': val.trim()}, SetOptions(merge: true));
                    },
                  ),
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
                              color: _isHolding ? color.withOpacity(0.7) : color,
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
                    _isHolding
                        ? "Keep holding..."
                        : "Hold for 3 seconds to send SOS",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _isHolding ? color : Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// CONNECTIVITY BANNER WIDGET
// ─────────────────────────────────────────────
class _ConnectivityBanner extends StatefulWidget {
  @override
  State<_ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<_ConnectivityBanner> {
  bool _isConnected = true;
  Timer? _checkTimer;

  @override
  void initState() {
    super.initState();
    _checkNow();
    // Check every 5 seconds
    _checkTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkNow());
  }

  Future<void> _checkNow() async {
    final connected = await hasInternet();
    if (mounted) setState(() => _isConnected = connected);
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isConnected) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Colors.red[900],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '⚠️ No internet — SOS will not work. Enable WiFi or mobile data.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () => launchUrl(Uri.parse('app-settings:')),
            child: const Text('Settings',
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// OFFICER DASHBOARD
// ─────────────────────────────────────────────
class OfficerDashboard extends StatefulWidget {
  final CompanyConfig company;
  const OfficerDashboard({super.key, required this.company});
  @override
  State<OfficerDashboard> createState() => _OfficerDashboardState();
}

class _OfficerDashboardState extends State<OfficerDashboard> {
  final MapController _mapCtrl = MapController();
  Set<String> _knownAlertIds = {};
  bool _mapReady = false;
  bool _isMuted = false;
  Map<String, dynamic>? _selectedAlert;
  String? _selectedAlertId;
  bool _panelOpen = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _playSiren(List<QueryDocumentSnapshot> alerts) {
    final latestData =
        alerts.isNotEmpty ? alerts.last.data() as Map<String, dynamic> : null;
    // Always show notification regardless of mute
    showAlertNotification(
      latestData?['userName'] ?? 'Unknown',
      '${latestData?['lat']?.toStringAsFixed(4) ?? ''}, '
          '${latestData?['lng']?.toStringAsFixed(4) ?? ''}',
    );
    // Only play sound and vibrate if not muted
    if (!_isMuted) {
      SystemSound.play(SystemSoundType.alert);
      Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 500]);
    }
  }

  void _selectAlert(String id, Map<String, dynamic> data) {
    setState(() {
      _selectedAlertId = id;
      _selectedAlert = data;
      _panelOpen = false;
    });
    if (_mapReady) {
      _mapCtrl.move(LatLng(data['lat'], data['lng']), 17.0);
    }
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
                style:
                    TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Divider(height: 24),
            _profileSection("Personal Information", Icons.person, [
              _profileRow("Name", profile['name']),
              _profileRow("ID Number", profile['idNumber']),
              _profileRow("Age", profile['age']),
              _profileRow("Blood Type", profile['bloodType']),
            ]),
            _profileSection("Medical Information", Icons.medical_services, [
              _profileRow("Allergies", profile['allergies']),
              _profileRow("Conditions", profile['conditions']),
              _profileRow("Medications", profile['medications']),
            ]),
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
            _profileSection("Addresses", Icons.home, [
              _profileRow("Home", profile['homeAddress']),
              _profileRow("Work", profile['workAddress']),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _profileSection(
      String title, IconData icon, List<Widget> children) {
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
              child:
                  Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(
              child: Text(text, style: const TextStyle(fontSize: 15))),
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
              child:
                  Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(
              child: Text(text, style: const TextStyle(fontSize: 15))),
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

  void _zoomToAlerts(List<QueryDocumentSnapshot> alerts) {
    if (!_mapReady || alerts.isEmpty) return;
    if (alerts.length == 1) {
      final data = alerts.first.data() as Map<String, dynamic>;
      _mapCtrl.move(LatLng(data['lat'], data['lng']), 17.0);
    } else {
      final points = alerts.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return LatLng(data['lat'], data['lng']);
      }).toList();
      _mapCtrl.fitCamera(
        CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.all(80),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.company.primaryColor;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('alerts')
          .where('status', isEqualTo: 'ACTIVE')
          .where('companyId', isEqualTo: widget.company.id)
          .orderBy('timestamp', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final alerts = snapshot.data!.docs;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          final currentIds = alerts.map((d) => d.id).toSet();
          final newIds = currentIds.difference(_knownAlertIds);
          final isFirstLoad = _knownAlertIds.isEmpty && alerts.isNotEmpty;

          if (isFirstLoad) {
            if (_mapReady) _zoomToAlerts(alerts);
            _playSiren(alerts);
          } else if (newIds.isNotEmpty) {
            if (_mapReady) _zoomToAlerts(alerts);
            _playSiren(alerts);
          }

          _knownAlertIds = currentIds;
        });

        return Stack(
          children: [
            FlutterMap(
              key: const ValueKey('officer_map'),
              mapController: _mapCtrl,
              options: MapOptions(
                initialCenter: const LatLng(-26.107, 28.05),
                initialZoom: 13,
                onMapReady: () {
                  setState(() => _mapReady = true);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (alerts.isNotEmpty) _zoomToAlerts(alerts);
                  });
                },
              ),
              children: [
                TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.cyberwarriors.sos'),
                MarkerLayer(
                  markers: alerts.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
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
                                color: isSelected ? Colors.orange : color,
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
            if (alerts.isEmpty)
              const Center(
                child: Card(
                  color: Colors.black54,
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text("No active alerts",
                        style: TextStyle(
                            fontSize: 18, color: Colors.white)),
                  ),
                ),
              ),
            if (alerts.isNotEmpty)
              Positioned(
                top: 20,
                left: 20,
                right: 20,
                child: GestureDetector(
                  onTap: () =>
                      setState(() => _panelOpen = !_panelOpen),
                  child: Card(
                    color: color.withOpacity(0.85),
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
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => setState(() => _isMuted = !_isMuted),
                            child: Icon(
                              _isMuted ? Icons.volume_off : Icons.volume_up,
                              color: _isMuted ? Colors.orange : Colors.white,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
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
                                Icon(Icons.warning, color: color, size: 28),
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
                                  onPressed: () => setState(
                                      () => _selectedAlert = null),
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
                                        padding:
                                            const EdgeInsets.all(12)),
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
                                        backgroundColor: Colors.orange[800],
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
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
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
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
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
                        constraints:
                            const BoxConstraints(maxHeight: 300),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: alerts.length,
                          itemBuilder: (context, index) {
                            final doc = alerts[index];
                            final data =
                                doc.data() as Map<String, dynamic>;
                            final isSelected =
                                doc.id == _selectedAlertId;
                            return ListTile(
                              leading: Icon(Icons.warning,
                                  color: isSelected
                                      ? Colors.orange
                                      : color),
                              title: Text(
                                data['userName'] ?? 'User',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal),
                              ),
                              subtitle:
                                  Text(_lastSeen(data['timestamp'])),
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
                                    onPressed: () =>
                                        _resolveAlert(doc.id),
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