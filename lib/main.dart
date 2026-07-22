import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
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
import 'package:sensors_plus/sensors_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:device_info_plus/device_info_plus.dart';

Uint8List _generateBeepTone({int frequency = 900, int durationMs = 150, int sampleRate = 44100}) {
  final int numSamples = (sampleRate * durationMs / 1000).round();
  final ByteData byteData = ByteData(44 + numSamples * 2);
  int offset = 0;

  void writeString(String s) {
    for (int i = 0; i < s.length; i++) {
      byteData.setUint8(offset, s.codeUnitAt(i));
      offset += 1;
    }
  }

  void writeUint32(int v) {
    byteData.setUint32(offset, v, Endian.little);
    offset += 4;
  }

  void writeUint16(int v) {
    byteData.setUint16(offset, v, Endian.little);
    offset += 2;
  }

  final int byteRate = sampleRate * 2;
  final int dataSize = numSamples * 2;

  writeString('RIFF');
  writeUint32(36 + dataSize);
  writeString('WAVE');
  writeString('fmt ');
  writeUint32(16);
  writeUint16(1);
  writeUint16(1);
  writeUint32(sampleRate);
  writeUint32(byteRate);
  writeUint16(2);
  writeUint16(16);
  writeString('data');
  writeUint32(dataSize);

  for (int i = 0; i < numSamples; i++) {
    final double t = i / sampleRate;
    final double envelope = i < numSamples * 0.1
        ? i / (numSamples * 0.1)
        : (i > numSamples * 0.8
            ? (numSamples - i) / (numSamples * 0.2)
            : 1.0);
    final int sample =
        (math.sin(2 * math.pi * frequency * t) * 32000 * envelope).round();
    byteData.setInt16(offset, sample, Endian.little);
    offset += 2;
  }

  return byteData.buffer.asUint8List();
}

// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
// NOTIFICATIONS
// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
final FlutterLocalNotificationsPlugin _notifications =
    FlutterLocalNotificationsPlugin();

// Track snoozed alerts (alertId -> snooze until time)
final Map<String, DateTime> _snoozedAlerts = {};

@pragma('vm:entry-point')
void _onBackgroundNotificationResponse(NotificationResponse response) {
  _handleNotificationAction(response.actionId, response.payload);
}

void _onNotificationResponse(NotificationResponse response) {
  _handleNotificationAction(response.actionId, response.payload);
}

String? _pendingCallNumber;

void _handleNotificationAction(String? actionId, String? alertId) {
  if (actionId == null || alertId == null) return;
  if (actionId != null && actionId.startsWith('call_')) {
    final number = actionId.substring(5);
    // Launch dialer — needs to be handled in UI context
    // Store for AppShell to pick up
    _pendingCallNumber = number;
    return;
  }
}

Future<void> initNotifications() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings settings = InitializationSettings(
      android: androidSettings);
  await _notifications.initialize(
    settings,
    onDidReceiveNotificationResponse: _onNotificationResponse,
    onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationResponse,
  );

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

Future<void> showAlertNotification(String name, String location,
    {int notificationId = 0, String? alertId, String? phone}) async {
  final List<AndroidNotificationAction> actions = [
    if (phone != null && phone.isNotEmpty)
      AndroidNotificationAction(
        'call_$phone',
        'CALL RIDER',
        showsUserInterface: true,
        cancelNotification: false,
      ),

  ];

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
    actions: actions,
  );
  final NotificationDetails details =
      NotificationDetails(android: androidDetails);
  await _notifications.show(
    notificationId,
    'SOS ALERT  -  $name',
    ' $location',
    details,
    payload: alertId,
  );
}


// ════════════════════════════════════════════════════════════════════
// FAMILY TRACKING HELPERS

double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0; // Earth radius km
  final dLat = (lat2 - lat1) * (math.pi / 180);
  final dLng = (lng2 - lng1) * (math.pi / 180);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * (math.pi / 180)) *
          math.cos(lat2 * (math.pi / 180)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return r * c;
}

String _generateTrackingToken() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rand = math.Random.secure();
  return List.generate(12, (_) => chars[rand.nextInt(chars.length)]).join();
}

Future<String> _getOrCreateTrackingToken(String deviceId, String companyId, String riderName) async {
  final doc = await FirebaseFirestore.instance
      .collection('tracking')
      .where('deviceId', isEqualTo: deviceId)
      .where('active', isEqualTo: true)
      .limit(1)
      .get();
  if (doc.docs.isNotEmpty) {
    return doc.docs.first.id;
  }
  final token = _generateTrackingToken();
  await FirebaseFirestore.instance.collection('tracking').doc(token).set({
    'deviceId': deviceId,
    'companyId': companyId,
    'riderName': riderName,
    'status': 'IDLE',
    'lat': 0.0,
    'lng': 0.0,
    'lastSeen': FieldValue.serverTimestamp(),
    'active': true,
    'createdAt': FieldValue.serverTimestamp(),
  });
  return token;
}

Future<void> _updateTrackingStatus(String deviceId, String status, {double? lat, double? lng}) async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('tracking')
        .where('deviceId', isEqualTo: deviceId)
        .where('active', isEqualTo: true)
        .limit(1)
        .get();
    if (doc.docs.isNotEmpty) {
      final update = <String, dynamic>{
        'status': status,
        'lastSeen': FieldValue.serverTimestamp(),
      };
      if (lat != null) update['lat'] = lat;
      if (lng != null) update['lng'] = lng;
      await doc.docs.first.reference.update(update);
    }
  } catch (e) {
    debugPrint('Tracking update error: $e');
  }
}

// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
// ESCALATING NOTIFICATION MANAGER
// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
// This class manages escalating reminders for officers about unresolved SOS alerts.
// Schedule:
//   0  - ├à 60s      ├ó├é┬á remind every 10s
//   60s  - ├à 10min  ├ó├é┬á remind every 60s
//   10min  - ├à 60min├ó├é┬á remind every 10min
//   60min+       ├ó├é┬á remind every 60min
class SOSEscalationManager {
  // Map of alertId -> timer for that alert
  static final Map<String, Timer> _timers = {};
  // Map of alertId -> when that alert started (first seen by officer)
  static final Map<String, DateTime> _alertStartTimes = {};
  // Map of alertId -> last notification time
  static final Map<String, DateTime> _lastNotified = {};
  // Map of alertId -> alert data snapshot
  static final Map<String, Map<String, dynamic>> _alertData = {};

  /// Call this when a new SOS alert is detected by the officer dashboard.
  static void startEscalation(String alertId, Map<String, dynamic> data) {
    if (_timers.containsKey(alertId)) return; // Already tracking this alert
    _alertStartTimes[alertId] = DateTime.now();
    _lastNotified[alertId] = DateTime.now();
    _alertData[alertId] = data;

    // Fire first notification immediately
    _notify(alertId, data);

    // Start a timer that checks every second what interval we're in
    // and fires when appropriate
    _timers[alertId] = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkAndNotify(alertId);
    });
  }

  /// Call this when an alert is resolved or cancelled  -  stops the reminders.
  static void stopEscalation(String alertId) {
    _timers[alertId]?.cancel();
    _timers.remove(alertId);
    _alertStartTimes.remove(alertId);
    _lastNotified.remove(alertId);
    _alertData.remove(alertId);
  }

  /// Stop all escalations (e.g. when officer switches out of officer mode)
  static void stopAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _alertStartTimes.clear();
    _lastNotified.clear();
    _alertData.clear();
  }

  /// Update the stored data for an alert (e.g. location changed)
  static void updateAlertData(String alertId, Map<String, dynamic> data) {
    if (_alertData.containsKey(alertId)) {
      _alertData[alertId] = data;
    }
  }

  static void _checkAndNotify(String alertId) {
    final start = _alertStartTimes[alertId];
    final lastNotify = _lastNotified[alertId];
    final data = _alertData[alertId];
    if (start == null || lastNotify == null || data == null) return;

    final ageSeconds = DateTime.now().difference(start).inSeconds;
    final secondsSinceNotify = DateTime.now().difference(lastNotify).inSeconds;

    // Determine required interval based on SOS age
    const int requiredIntervalSeconds = 300; // Once every 5 minutes

    if (secondsSinceNotify >= requiredIntervalSeconds) {
      _notify(alertId, data);
      _lastNotified[alertId] = DateTime.now();
    }
  }

  static Future<void> _notify(
      String alertId, Map<String, dynamic> data) async {
    final name = data['userName'] ?? 'Unknown';
    final lat = (data['lat'] as num?)?.toStringAsFixed(4) ?? '';
    final lng = (data['lng'] as num?)?.toStringAsFixed(4) ?? '';

    final start = _alertStartTimes[alertId];
    String ageLabel = '';
    if (start != null) {
      final age = DateTime.now().difference(start);
      if (age.inMinutes < 1) {
        ageLabel = '${age.inSeconds}s ago';
      } else if (age.inHours < 1) {
        ageLabel = '${age.inMinutes}m ago';
      } else {
        ageLabel = '${age.inHours}h ${age.inMinutes.remainder(60)}m ago';
      }
    }

    // Use alertId hashCode as notification ID so each alert has its own notification
    final notificationId = alertId.hashCode.abs() % 10000;
    final helpType = data['helpType'] as String?;
    final alertPrefix = helpType != null && helpType.isNotEmpty ? '[' + helpType + '] ' : '[SOS] ';
    final profile = data['profile'] as Map<String, dynamic>?;
    final phone = profile?['mobilePhone'] as String? ?? '';
    await showAlertNotification(
      alertPrefix + name,
      '$lat, $lng - Started $ageLabel',
      notificationId: notificationId,
      alertId: alertId,
      phone: phone,
    );
  }

  /// Snooze escalation for a given duration then restart
  static void snoozeEscalation(String alertId, Duration duration) {
    _timers[alertId]?.cancel();
    _timers.remove(alertId);
    // Restart after snooze duration
    Timer(duration, () {
      final data = _alertData[alertId];
      if (data != null) {
        _lastNotified[alertId] = DateTime.now();
        _notify(alertId, data);
        _timers[alertId] = Timer.periodic(const Duration(seconds: 1), (_) {
          _checkAndNotify(alertId);
        });
      }
    });
  }

  /// Returns list of currently tracked alert IDs
  static Set<String> get trackedAlertIds => _timers.keys.toSet();
}

// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
// FOREGROUND TASK HANDLER
// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
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
    try {
      // Always re-read the latest alertId/companyId, in case the service was
      // restarted for a new alert rather than freshly started (onStart may not
      // re-run on restartService, which previously left this pointing at a
      // stale/already-resolved alert).
      final latestAlertId =
          await FlutterForegroundTask.getData<String>(key: 'alertId');
      if (latestAlertId != null) _alertId = latestAlertId;
      final latestCompanyId =
          await FlutterForegroundTask.getData<String>(key: 'companyId');
      if (latestCompanyId != null) _companyId = latestCompanyId;
      if (_alertId == null) return;
      // Check if alert is still active  -  stop service if resolved or cancelled
      final alertSnap = await FirebaseFirestore.instance
          .collection('alerts')
          .doc(_alertId)
          .get();
      if (alertSnap.exists) {
        final status = alertSnap.data()?['status'] as String?;
        if (status == 'RESOLVED' || status == 'CANCELLED') {
          debugPrint('Alert no longer active ($status)  -  stopping foreground service');
          await FlutterForegroundTask.stopService();
          return;
        }
      } else {
        // Alert document doesn't exist  -  stop service
        await FlutterForegroundTask.stopService();
        return;
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) return;

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 15));
      } on TimeoutException {
        debugPrint('Location fix timed out after 15s');
        await FirebaseFirestore.instance
            .collection('alerts')
            .doc(_alertId)
            .update({
          'lastTrackingAttempt': FieldValue.serverTimestamp(),
          'lastTrackingError': 'GPS timeout (15s)',
        }).catchError((_) {});
        return;
      }

      await FirebaseFirestore.instance
          .collection('alerts')
          .doc(_alertId)
          .update({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'lastTrackingAttempt': FieldValue.serverTimestamp(),
        'lastTrackingError': null,
      });

      FlutterForegroundTask.updateService(
        notificationTitle: 'SOS Active',
        notificationText: 'SOS Active  -  Sharing your location with officers',
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

// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
// FOREGROUND SERVICE HELPERS
// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
void initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'sos_tracking',
      channelName: 'SOS Tracking',
      channelDescription: 'Tracks your location during an active SOS',
      channelImportance: NotificationChannelImportance.HIGH,
      priority: NotificationPriority.HIGH,
      onlyAlertOnce: true,
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

  // Always do a clean stop+start rather than restartService(), which does
  // not reliably re-establish the repeating location-update timer - it was
  // only firing once for any alert after the first one in a session.
  if (await FlutterForegroundTask.isRunningService) {
    await FlutterForegroundTask.stopService();
  }
  await FlutterForegroundTask.startService(
    notificationTitle: 'SOS Active',
    notificationText: 'Sharing your location with officers...',
    callback: startCallback,
  );
}

Future<void> stopLocationService() async {
  await FlutterForegroundTask.stopService();
}

// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
// COMPANY CONFIG MODEL
// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
class CompanyConfig {
  final String id;
  final String name;
  final String logoUrl;
  final Color primaryColor;
  final bool isActive;
  final int maxDevices;
  final String emergencyPhone;
  final bool isTrial;
  final String trialEnds;
  final String companyType;
  final bool allowDependents;
  final int maxDependentsPerMember;

  bool get isAdventure => companyType == 'adventure';

  CompanyConfig({
    required this.id,
    required this.name,
    required this.logoUrl,
    required this.primaryColor,
    required this.isActive,
    required this.maxDevices,
    required this.emergencyPhone,
    this.isTrial = false,
    this.trialEnds = '',
    this.companyType = 'standard',
    this.allowDependents = false,
    this.maxDependentsPerMember = 4,
  });

  bool get isTrialExpired {
    if (!isTrial || trialEnds.isEmpty) return false;
    try {
      final end = DateTime.parse(trialEnds);
      return DateTime.now().isAfter(end);
    } catch (_) {
      return false;
    }
  }

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
      isTrial: data['isTrial'] ?? false,
      trialEnds: data['trialEnds'] ?? '',
      companyType: data['companyType'] ?? 'standard',
      allowDependents: data['allowDependents'] ?? false,
      maxDependentsPerMember: data['maxDependentsPerMember'] ?? 4,
    );
  }
}

CompanyConfig? currentCompany;
String currentRole = 'client';

// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
// HELPERS
// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
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

// ├ó├ó Radius helpers ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
const double kDefaultRadiusKm = 50.0;

Future<double> getSavedRadius() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getDouble('response_radius_km') ?? kDefaultRadiusKm;
}

Future<void> saveRadius(double km) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble('response_radius_km', km);
  // Also persist to Firestore device record so admin can see it
  try {
    final deviceId = await getDeviceId();
    FirebaseFirestore.instance
        .collection('devices')
        .doc(deviceId)
        .update({'responseRadiusKm': km}).catchError((_) {});
  } catch (_) {}
}

/// Haversine formula  -  returns distance in km between two GPS points
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = _deg2rad(lat2 - lat1);
  final dLng = _deg2rad(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) *
          sin(dLng / 2) * sin(dLng / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

double _deg2rad(double deg) => deg * pi / 180;

Future<void> saveCompanyData(CompanyConfig company) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('company_name', company.name);
  await prefs.setString('company_logo', company.logoUrl);
  await prefs.setString('company_color',
      company.primaryColor.value.toRadixString(16));
  await prefs.setBool('company_active', company.isActive);
  await prefs.setInt('company_max_devices', company.maxDevices);
  await prefs.setString('company_phone', company.emergencyPhone);
  await prefs.setBool('company_is_trial', company.isTrial);
  await prefs.setString('company_trial_ends', company.trialEnds);
  await prefs.setString('company_type', company.companyType);
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
    isTrial: prefs.getBool('company_is_trial') ?? false,
    trialEnds: prefs.getString('company_trial_ends') ?? '',
    companyType: prefs.getString('company_type') ?? 'standard',
  );
}

Future<void> sendWhatsAppAlert({
  required String phone,
  required String userName,
  required double lat,
  required double lng,
  String countryCode = '27',
  String alertType = 'SOS',
  String? riderPhone,
  String? customMessage,
}) async {
  try {
    final whatsappCheck = Uri.parse('whatsapp://send');
    if (!await canLaunchUrl(whatsappCheck)) {
      debugPrint('WhatsApp not installed, skipping alert');
      return;
    }
    String cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    if (cleaned.startsWith('00')) cleaned = cleaned.substring(2);
    if (cleaned.startsWith('0')) cleaned = countryCode + cleaned.substring(1);
    if (!cleaned.startsWith(countryCode)) cleaned = countryCode + cleaned;
    final mapsLink = 'https://www.google.com/maps?q=$lat,$lng';
    String alertTitle;
    switch (alertType) {
      case 'CRASH': alertTitle = 'CRASH DETECTED - $userName may be injured!'; break;
      case 'LOST': alertTitle = 'RIDER LOST - $userName needs directions'; break;
      case 'FUEL': alertTitle = 'FUEL REQUEST - $userName has run out of fuel'; break;
      case 'BREAKDOWN': alertTitle = 'BREAKDOWN - $userName needs mechanical help'; break;
      case 'OTHER': alertTitle = 'HELP NEEDED - $userName needs assistance'; break;
      default: alertTitle = 'EMERGENCY SOS - $userName needs urgent help!';
    }
    final phoneInfo = riderPhone != null && riderPhone.isNotEmpty
        ? 'Call $userName: $riderPhone\n\n' : '';
    final customInfo = customMessage != null && customMessage.isNotEmpty
        ? '"$customMessage"\n\n' : '';
    final message = Uri.encodeComponent(
        '$alertTitle\n\n'
        '${customInfo}Location: $mapsLink\n\n'
        '${phoneInfo}Please respond immediately or call emergency services.');
    final url = 'whatsapp://send?phone=$cleaned&text=$message';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      await Future.delayed(const Duration(milliseconds: 1500));
    }
  } catch (e) {
    debugPrint('WhatsApp alert error: $e');
  }
}

// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
// CONNECTIVITY
// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
Future<void> saveFcmToken(String deviceId, String companyId, String role) async {
  try {
    final token = await FirebaseMessaging.instance.getToken();
    final data = <String, dynamic>{
      'companyId': companyId,
      'role': role,
      'isActive': true,
      'lastSeen': FieldValue.serverTimestamp(),
    };
    if (token != null) {
      data['fcmToken'] = token;
    }
    await FirebaseFirestore.instance
        .collection('devices')
        .doc(deviceId)
        .set(data, SetOptions(merge: true));
    debugPrint('FCM token saved: $token');
  } catch (e) {
    debugPrint('FCM token error: $e');
  }
}

Future<void> sendFcmToDevice(String token, String title, String body) async {
  // Direct FCM send via Firestore trigger — store notification request
  // Firebase will deliver via FCM token
  try {
    await FirebaseFirestore.instance.collection('notifications').add({
      'token': token,
      'title': title,
      'body': body,
      'createdAt': FieldValue.serverTimestamp(),
      'delivered': false,
    });
  } catch (e) {
    debugPrint('FCM send error: \$e');
  }
}

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

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('Background FCM message: ${message.notification?.title}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
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

// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
// APP ENTRY
// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
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
      String? companyId = await getSavedCompanyId();

      // On web, fall back to localStorage if SharedPreferences is empty
      // On web, SharedPreferences already uses localStorage internally
      // so no extra handling needed here

      if (companyId == null) {
        setState(() => _loading = false);
        return;
      }

      currentRole = await getSavedRole();
      currentCompany = await getCompanyData(companyId);
      setState(() => _loading = false);

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
    if (currentCompany == null) return const CompanyRegistrationScreen();
    if (!currentCompany!.isActive) {
      return SubscriptionSuspendedScreen(company: currentCompany!);
    }
    if (currentCompany!.isTrialExpired) {
      return TrialExpiredScreen(company: currentCompany!);
    }
    return AppShell(company: currentCompany!);
  }
}

// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
// COMPANY REGISTRATION SCREEN
// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
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

  Future<void> _registerAsDependent(
      QueryDocumentSnapshot<Map<String, dynamic>> linkedProfileDoc) async {
    try {
      final linkedData = linkedProfileDoc.data();
      final linkedMemberId = linkedProfileDoc.id;
      final linkedCompanyId = (linkedData['companyId'] ?? '').toString();
      final linkedMemberName = (linkedData['name'] ?? 'this member').toString();

      if (linkedCompanyId.isEmpty) {
        setState(() {
          _error =
              "This family code isn't linked to a company. Please contact your administrator.";
          _loading = false;
        });
        return;
      }

      final companyDoc = await FirebaseFirestore.instance
          .collection('companies')
          .doc(linkedCompanyId)
          .get();

      if (!companyDoc.exists) {
        setState(() {
          _error =
              "Could not find the linked company. Please contact your administrator.";
          _loading = false;
        });
        return;
      }

      final company =
          CompanyConfig.fromFirestore(companyDoc.id, companyDoc.data()!);

      if (!company.allowDependents) {
        setState(() {
          _error = "Family accounts are not currently available for this company.";
          _loading = false;
        });
        return;
      }

      final existingDependents = await FirebaseFirestore.instance
          .collection('devices')
          .where('linkedMemberId', isEqualTo: linkedMemberId)
          .where('role', isEqualTo: 'dependent')
          .get();
      final existingActiveDependents = existingDependents.docs
          .where((d) => d.data()['removedByMember'] != true)
          .toList();

      final deviceId = await getDeviceId();
      final alreadyRegistered =
          existingActiveDependents.any((d) => d.id == deviceId);

      if (!alreadyRegistered &&
          existingActiveDependents.length >= company.maxDependentsPerMember) {
        setState(() {
          _error =
              "Maximum family members reached (${company.maxDependentsPerMember}). Please contact $linkedMemberName.";
          _loading = false;
        });
        return;
      }

      if (!mounted) return;
      final relationship = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => SimpleDialog(
          backgroundColor: Colors.grey[900],
          title: Text('Your relationship to $linkedMemberName'),
          children: [
            for (final rel in ['Wife', 'Husband', 'Son', 'Daughter', 'Other'])
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(rel),
                child: Text(rel, style: const TextStyle(color: Colors.white)),
              ),
          ],
        ),
      );

      if (relationship == null) {
        setState(() => _loading = false);
        return;
      }

      await FirebaseFirestore.instance.collection('devices').doc(deviceId).set({
        'companyId': companyDoc.id,
        'role': 'dependent',
        'linkedMemberId': linkedMemberId,
        'linkedMemberName': linkedMemberName,
        'relationship': relationship,
        'registeredAt': FieldValue.serverTimestamp(),
        'lastSeen': FieldValue.serverTimestamp(),
        'isActive': true,
      });

      await saveCompanyId(companyDoc.id);
      await saveRole('dependent');
      await saveCompanyData(company);
      currentCompany = company;
      currentRole = 'dependent';
      await saveFcmToken(deviceId, companyDoc.id, 'dependent');

      if (mounted) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => AppShell(company: company)));
      }
    } catch (e) {
      setState(() {
        _error = "Failed to register as family member: $e";
        _loading = false;
      });
    }
  }

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
      final familyQuery = await FirebaseFirestore.instance
          .collection('profiles')
          .where('familyCode', isEqualTo: code)
          .limit(1)
          .get();
      if (familyQuery.docs.isNotEmpty) {
        await _registerAsDependent(familyQuery.docs.first);
        return;
      }

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
      // Save FCM token for push notifications
      await saveFcmToken(deviceId, companyDoc.id, role);

      // Generate tracking token for riders
      if (role == 'client') {
        try {
          final name = 'Rider';
          await _getOrCreateTrackingToken(deviceId, companyDoc.id, name);
        } catch (e) {
          debugPrint('Tracking token error: $e');
        }
      }

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
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield, size: 80, color: Colors.red),
              const SizedBox(height: 16),
              const Text("Welcome",
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
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
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: _loading ? null : _register,
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
// TRIAL EXPIRED SCREEN
// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
class TrialExpiredScreen extends StatelessWidget {
  final CompanyConfig company;
  const TrialExpiredScreen({super.key, required this.company});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer_off, size: 80, color: Colors.orange),
              const SizedBox(height: 24),
              Text(company.name,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              const Text('Your 14-day free trial has expired.',
                  style: TextStyle(fontSize: 18, color: Colors.orange),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              const Text(
                'To continue using the service, please subscribe at cyberwarriors.co.za or contact us directly.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: Colors.grey, fontSize: 15, height: 1.5),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.language),
                  label: const Text('Subscribe Now',
                      style: TextStyle(fontSize: 16)),
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => launchUrl(
                    Uri.parse(
                        'https://c42die4.github.io/guardian-sos-signup/signup.html'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.call),
                  label: const Text('Call Cyber Warriors',
                      style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[800]),
                  onPressed: () =>
                      launchUrl(Uri.parse('tel:+27000000000')),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => launchUrl(Uri.parse(
                    'mailto:info@cyberwarriors.co.za?subject=Trial%20Expired%20-%20${Uri.encodeComponent(company.name)}')),
                child: const Text('Email Us',
                    style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
// SUBSCRIPTION SUSPENDED SCREEN
// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
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
              const Text("Please contact support to restore access.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 15)),
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
                  onPressed: () =>
                      launchUrl(Uri.parse('tel:+27000000000')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
// APP SHELL
// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
class AppShell extends StatefulWidget {
  final CompanyConfig company;
  const AppShell({super.key, required this.company});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool isOfficerMode = false;
  bool _checkingProfile = true;
  double _radiusKm = kDefaultRadiusKm;
  bool _toggleFlash = false;
  Timer? _toggleFlashTimer;
  int _activeAlertCount = 0;

  @override
  void initState() {
    super.initState();
    _checkProfile();
    _requestPermissions();
    _loadRadius();
    _stopOrphanedService();
    _startToggleFlashTimer();
    _listenForAlerts();

  }

  Future<void> _stopOrphanedService() async {
    // Stop any foreground service that survived from a previous session
    // without an active SOS  -  this prevents the phantom notification
    try {
      if (await FlutterForegroundTask.isRunningService) {
        // Check if there is actually an active SOS for this device
        final deviceId = await getDeviceId();
        final activeAlerts = await FirebaseFirestore.instance
            .collection('alerts')
            .where('deviceId', isEqualTo: deviceId)
            .where('status', isEqualTo: 'ACTIVE')
            .get();
        if (activeAlerts.docs.isEmpty) {
          // No active SOS  -  stop the orphaned service
          await FlutterForegroundTask.stopService();
          debugPrint('Stopped orphaned foreground service on startup');
        }
      }
    } catch (e) {
      debugPrint('Error checking orphaned service: $e');
    }
  }


  void _startToggleFlashTimer() {
    _toggleFlashTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (mounted && !isOfficerMode && _activeAlertCount > 0) {
        setState(() => _toggleFlash = !_toggleFlash);
      } else if (mounted && _toggleFlash) {
        setState(() => _toggleFlash = false);
      }
    });
  }

  void _listenForAlerts() {
    FirebaseFirestore.instance
        .collection('alerts')
        .where('status', isEqualTo: 'ACTIVE')
        .where('companyId', isEqualTo: widget.company.id)
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _activeAlertCount = snap.docs.length);
    });
  }

  @override
  void dispose() {
    _toggleFlashTimer?.cancel();
    super.dispose();
  }

  @override
  Future<void> _loadRadius() async {
    final r = await getSavedRadius();
    if (mounted) setState(() => _radiusKm = r);
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
    // On web, officers skip profile setup and go straight to map
    if (kIsWeb) {
      final urlCode = Uri.base.queryParameters['code'];
      if (urlCode != null && urlCode.trim().isNotEmpty) {
        final urlQuery = await FirebaseFirestore.instance
            .collection('companies')
            .where('officerCode', isEqualTo: urlCode.trim().toUpperCase())
            .limit(1)
            .get();
        if (urlQuery.docs.isNotEmpty) {
          final companyDoc = urlQuery.docs.first;
          final company = CompanyConfig.fromFirestore(
              companyDoc.id, companyDoc.data());
          final deviceId = await getDeviceId();
          await saveCompanyId(companyDoc.id);
          await saveRole('officer');
          await saveCompanyData(company);
          currentCompany = company;
          currentRole = 'officer';
          await saveFcmToken(deviceId, companyDoc.id, 'officer');
          setState(() {
            _checkingProfile = false;
            isOfficerMode = true;
          });
          return;
        }
      }
      final savedRole = await getSavedRole();
      if (savedRole == 'officer') {
        setState(() {
          _checkingProfile = false;
          isOfficerMode = true;
        });
        return;
      }
    }
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

  void _showRadiusDialog() {
    double tempRadius = _radiusKm;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Row(
            children: [
              Icon(Icons.radar, color: Colors.blue),
              SizedBox(width: 8),
              Text('Response Radius', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'You will only receive alerts within ${tempRadius.toStringAsFixed(0)} km of your current location.',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Text(
                '${tempRadius.toStringAsFixed(0)} km',
                style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue),
              ),
              Slider(
                value: tempRadius,
                min: 10,
                max: 500,
                divisions: 49,
                activeColor: Colors.blue,
                label: '${tempRadius.toStringAsFixed(0)} km',
                onChanged: (v) => setDlg(() => tempRadius = v),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _radiusChip('10 km', 10, tempRadius, setDlg, (v) => tempRadius = v),
                  _radiusChip('50 km', 50, tempRadius, setDlg, (v) => tempRadius = v),
                  _radiusChip('100 km', 100, tempRadius, setDlg, (v) => tempRadius = v),
                  _radiusChip('All', 9999, tempRadius, setDlg, (v) => tempRadius = v),
                ],
              ),
            ],
              ),
            ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () async {
                await saveRadius(tempRadius);
                setState(() => _radiusKm = tempRadius);
                if (mounted) Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _radiusChip(String label, double value, double current,
      StateSetter setDlg, Function(double) onTap) {
    final selected = (current - value).abs() < 1;
    return GestureDetector(
      onTap: () => setDlg(() => onTap(value)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.blue : Colors.grey[800],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : Colors.grey,
                fontSize: 12,
                fontWeight:
                    selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOfficer = currentRole == 'officer';

    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        primaryColor: widget.company.primaryColor,
        colorScheme:
            ColorScheme.dark(primary: widget.company.primaryColor),
        appBarTheme: AppBarTheme(
          backgroundColor:
              widget.company.primaryColor.withOpacity(0.2),
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
                      ? "${widget.company.name}  -  OFFICER"
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
                          builder: (_) => const ProfileScreen(
                              isFirstTime: false)));
                  setState(() {});
                },
              ),
            if (currentCompany?.allowDependents == true &&
                currentRole != 'dependent')
              IconButton(
                icon: const Icon(Icons.family_restroom),
                tooltip: 'Family',
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            FamilyScreen(company: currentCompany!))),
              ),
            if (currentRole != 'dependent') ...[
              // Radius button  -  only show in officer mode
              if (isOfficerMode)
                IconButton(
                  icon: const Icon(Icons.radar),
                  tooltip: 'Response Radius',
                  onPressed: () => _showRadiusDialog(),
                ),
              if (isOfficerMode)
                IconButton(
                  icon: const Icon(Icons.history),
                  tooltip: 'Alert History',
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => AlertHistoryScreen(company: widget.company))),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: (!isOfficerMode && _activeAlertCount > 0 && _toggleFlash)
                      ? [BoxShadow(color: Colors.orange.withOpacity(0.8), blurRadius: 12, spreadRadius: 2)]
                      : [],
                ),
                child: Switch(
                  value: isOfficerMode,
                  activeThumbColor: Colors.blueAccent,
                  inactiveThumbColor: (!isOfficerMode && _activeAlertCount > 0 && _toggleFlash)
                      ? Colors.orange
                      : null,
                  onChanged: (v) {
                    if (!v) SOSEscalationManager.stopAll();
                    setState(() => isOfficerMode = v);
                  }),
              ),
              const Icon(Icons.security),
              const SizedBox(width: 10),
            ],
          ],
        ),
        body: _checkingProfile
            ? const Center(child: CircularProgressIndicator())
            : isOfficerMode
                ? OfficerDashboard(company: widget.company, responseRadiusKm: _radiusKm)
                : SOSScreen(company: widget.company),
      ),
    );
  }
}

// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
// PROFILE SCREEN
// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
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
  final _mobilePhoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  int _notifyRadiusKm = 0; // 0 = everyone/unlimited
  String _familyCode = '';

  String _generateFamilyCode() {
    final rand = math.Random();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final code = List.generate(5, (_) => chars[rand.nextInt(chars.length)]).join();
    return 'FAM-$code';
  }

  Future<void> _inviteFamilyMember() async {
    try {
      final granted =
          await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Contacts permission denied')));
        }
        return;
      }
      final contact = await FlutterContacts.openExternalPick();
      if (contact == null || contact.phones.isEmpty) return;
      String cleaned = contact.phones.first.number
          .replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
      if (cleaned.startsWith('00')) cleaned = cleaned.substring(2);
      if (cleaned.startsWith('0')) cleaned = '27' + cleaned.substring(1);
      if (!cleaned.startsWith('27')) cleaned = '27' + cleaned;
      final message = Uri.encodeComponent(
          "Hi ${contact.displayName}! Join our club safety app so we can help "
          "if you're ever in trouble.\n\n"
          "Download: https://sos.cyberwarriors.co.za/join/highway-devils.html\n\n"
          "Your family code: $_familyCode");
      final uri = Uri.parse('whatsapp://send?phone=$cleaned&text=$message');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not send invite: $e')));
      }
    }
  }

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
      _mobilePhoneCtrl.text = d['mobilePhone'] ?? '';
      _emailCtrl.text = d['email'] ?? '';
      _notifyRadiusKm = (d['notifyRadiusKm'] is int) ? d['notifyRadiusKm'] : 0;
      _familyCode = d['familyCode'] ?? '';
    }
    if (_familyCode.isEmpty &&
        currentCompany?.allowDependents == true &&
        currentRole != 'dependent') {
      _familyCode = _generateFamilyCode();
      await FirebaseFirestore.instance.collection('profiles').doc(id).set(
          {'familyCode': _familyCode}, SetOptions(merge: true));
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
      'mobilePhone': _mobilePhoneCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'notifyRadiusKm': _notifyRadiusKm,
      'companyId': currentCompany?.id ?? '',
      'familyCode': _familyCode,
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
          Row(children: [
            Icon(icon, color: Colors.red, size: 20),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red)),
          ]),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(subtitle,
                  style:
                      const TextStyle(color: Colors.grey, fontSize: 12)),
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

  Future<void> _pickContactInto(
      TextEditingController nameCtrl, TextEditingController phoneCtrl) async {
    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Contacts permission denied')));
        }
        return;
      }
      final contact = await FlutterContacts.openExternalPick();
      if (contact == null) return;
      if (mounted) {
        setState(() {
          nameCtrl.text = contact.displayName;
          if (contact.phones.isNotEmpty) {
            phoneCtrl.text = contact.phones.first.number;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open contacts: $e')));
      }
    }
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
          Row(children: [
            const Icon(Icons.person, color: Colors.green, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.green, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              icon: const Icon(Icons.contact_page, color: Colors.green, size: 20),
              tooltip: 'Pick from contacts',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => _pickContactInto(nameCtrl, phoneCtrl),
            ),
          ]),
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
    _mobilePhoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.isFirstTime ? "Setup Your Profile" : "Edit Profile"),
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
                  _sectionHeader(
                      "Personal Information", Icons.person),
                  _field("Full Name", _nameCtrl, required: true),
                  _field("Your Mobile Number", _mobilePhoneCtrl,
                      keyboardType: TextInputType.phone),
                  _field("Email Address", _emailCtrl,
                      keyboardType: TextInputType.emailAddress),
                  _field("ID Number", _idCtrl,
                      keyboardType: TextInputType.number),
                  _field("Age", _ageCtrl,
                      keyboardType: TextInputType.number),
                  _field("Blood Type (e.g. O+)", _bloodTypeCtrl),
                  _sectionHeader(
                      "Medical Information", Icons.medical_services),
                  _field("Allergies", _allergiesCtrl, maxLines: 2),
                  _field("Medical Conditions", _conditionsCtrl,
                      maxLines: 2),
                  _field("Current Medications", _medicationsCtrl,
                      maxLines: 2),
                  _sectionHeader(
                      "Emergency Contact 1", Icons.contact_phone),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () =>
                          _pickContactInto(_contact1NameCtrl, _contact1PhoneCtrl),
                      icon: const Icon(Icons.contact_page, size: 18, color: Colors.orange),
                      label: const Text('Pick from Contacts',
                          style: TextStyle(color: Colors.orange, fontSize: 12)),
                    ),
                  ),
                  _field("Contact Name", _contact1NameCtrl),
                  _field("Phone Number", _contact1PhoneCtrl,
                      keyboardType: TextInputType.phone),
                  _field("Relationship", _contact1RelCtrl),
                  _sectionHeader(
                      "Emergency Contact 2", Icons.contact_phone),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () =>
                          _pickContactInto(_contact2NameCtrl, _contact2PhoneCtrl),
                      icon: const Icon(Icons.contact_page, size: 18, color: Colors.orange),
                      label: const Text('Pick from Contacts',
                          style: TextStyle(color: Colors.orange, fontSize: 12)),
                    ),
                  ),
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
                  _waContactBlock(
                      "Contact 1", _wa1NameCtrl, _wa1PhoneCtrl),
                  _waContactBlock(
                      "Contact 2", _wa2NameCtrl, _wa2PhoneCtrl),
                  _waContactBlock(
                      "Contact 3", _wa3NameCtrl, _wa3PhoneCtrl),
                  if (currentCompany?.allowDependents == true &&
                      currentRole != 'dependent')
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.blue[700]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.family_restroom,
                                color: Colors.blue, size: 18),
                            const SizedBox(width: 6),
                            const Text('Family Members',
                                style: TextStyle(
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold)),
                          ]),
                          const SizedBox(height: 6),
                          const Text(
                            'Share this code with your spouse or children so they can install the app and get help too.',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.black26,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                      _familyCode.isEmpty
                                          ? 'Generating...'
                                          : _familyCode,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          letterSpacing: 1.5)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.copy, color: Colors.blue),
                                tooltip: 'Copy code',
                                onPressed: _familyCode.isEmpty
                                    ? null
                                    : () {
                                        Clipboard.setData(
                                            ClipboardData(text: _familyCode));
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text('Code copied')));
                                      },
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.person_add_alt,
                                    color: Colors.green),
                                tooltip: 'Invite via WhatsApp',
                                onPressed: _familyCode.isEmpty
                                    ? null
                                    : _inviteFamilyMember,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  _sectionHeader(
                    "Notification Range",
                    Icons.notifications_active,
                    subtitle:
                        "Get a WhatsApp when someone else in the club sends an alert, "
                        "if they're within this distance of you. Choose Everyone to "
                        "always be notified regardless of distance.",
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ['Everyone', 0],
                          ['10km', 10],
                          ['25km', 25],
                          ['50km', 50],
                          ['100km', 100],
                        ].map<Widget>((opt) {
                          final selected = _notifyRadiusKm == opt[1];
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () => setState(() => _notifyRadiusKm = opt[1] as int),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: selected ? Colors.orange : Colors.white10,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: selected ? Colors.orange : Colors.white24),
                                ),
                                child: Text(opt[0] as String,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: selected ? Colors.black : Colors.white70,
                                        fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
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
                                  strokeWidth: 2,
                                  color: Colors.white))
                          : const Icon(Icons.save),
                      label: Text(
                          _saving ? "Saving..." : "SAVE PROFILE",
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

// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
// SOS ACTIVE SCREEN
// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
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
  List<String> _responders = [];
  StreamSubscription? _alertListener;

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
    _alertListener = FirebaseFirestore.instance
        .collection('alerts')
        .doc(widget.alertId)
        .snapshots()
        .listen((snap) async {
      if (!snap.exists) return;
      final data = snap.data()!;
      final status = data['status'] as String?;
      final respondersRaw = data['responders'] as List<dynamic>?;
      final responderNames = respondersRaw
              ?.whereType<Map>()
              .map((r) => (r['name'] ?? 'Someone').toString())
              .toList() ??
          <String>[];
      if (mounted) setState(() => _responders = responderNames);
      if (status == 'RESOLVED' || status == 'CANCELLED') {
        await stopLocationService();
        if (mounted) widget.onCancel();
      }
    });

  }

  @override
  void dispose() {
    _alertListener?.cancel();
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
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
          .update({
        'status': 'CANCELLED',
        'cancelledAt': FieldValue.serverTimestamp(),
      });
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
              Row(children: [
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
              ]),
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
                          spreadRadius: 10)
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
              Text(
                _responders.isNotEmpty ? "Help is on the way!" : "SOS Sent - Waiting for response...",
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _responders.isNotEmpty ? Colors.white : Colors.orange),
              ),
              const SizedBox(height: 8),
              Text(
                _responders.isNotEmpty
                    ? "${_responders.join(', ')} ${_responders.length == 1 ? 'is' : 'are'} on the way to you."
                    : "Your SOS has been sent. Stay calm and keep your phone with you.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
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
                      const Row(children: [
                        Icon(Icons.chat, color: Colors.green, size: 16),
                        SizedBox(width: 6),
                        Text("WhatsApp alerts sent to:",
                            style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ]),
                      const SizedBox(height: 6),
                      ...contacts.map((c) => Text(" $c",
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
                    label: Text(
                        "CALL ${widget.company.name.toUpperCase()}",
                        style: const TextStyle(fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        padding: const EdgeInsets.all(14)),
                    onPressed: () => launchUrl(Uri.parse(
                        'tel:${widget.company.emergencyPhone}')),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.cancel, color: Colors.white),
                  label: const Text("CANCEL SOS",
                      style: TextStyle(fontSize: 15, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[800],
                      foregroundColor: Colors.white,
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

// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
// SOS SCREEN
// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
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
  String _dependentRelationship = '';
  String _dependentLinkedMemberName = '';
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
  // Live tracking
  bool _isSharing = false;
  Timer? _shareTimer;
  int _shareIntervalMinutes = 2;
  bool _shareFlash = false;
  Timer? _shareFlashTimer;
  bool _hasShared = false;
  // FCM notification listener
  StreamSubscription? _notificationSubscription;

  // Crash detection
  bool _crashDetectionEnabled = false;
  StreamSubscription? _accelSubscription;
  Timer? _crashCountdownTimer;
  bool _crashCountdownActive = false;
  int _crashCountdownSeconds = 60;
  DateTime? _lastHighGEvent;
  final AudioPlayer _crashBeepPlayer = AudioPlayer();
  static const double _crashThresholdG = 12.0;
  static const double _gravity = 9.8;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _checkConnectivity();
    _connectivityTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => _checkConnectivity());
    _controller = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..addListener(() => setState(() => _progress = _controller.value));
    // Request FCM permissions and refresh token
    _initFcm();
    // Start listening for incoming notifications
    _startNotificationListener();
    _checkForActiveAlert();
    _checkHuaweiWarning();
  }

  Future<void> _checkForActiveAlert() async {
    try {
      final deviceId = await getDeviceId();
      final snap = await FirebaseFirestore.instance
          .collection('alerts')
          .where('deviceId', isEqualTo: deviceId)
          .where('status', isEqualTo: 'ACTIVE')
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return;
      final doc = snap.docs.first;
      final data = doc.data();
      final lat = (data['lat'] is num) ? (data['lat'] as num).toDouble() : 0.0;
      final lng = (data['lng'] is num) ? (data['lng'] as num).toDouble() : 0.0;
      final profile =
          (data['profile'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      if (mounted) {
        setState(() {
          _sosActive = true;
          _activeAlertId = doc.id;
          _lastProfile = profile;
          _lastLat = lat;
          _lastLng = lng;
        });
        await startLocationService(doc.id, widget.company.id);
      }
    } catch (e) {
      debugPrint('Check active alert error: $e');
    }
  }

  Future<void> _checkHuaweiWarning() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('huaweiWarningDismissed') == true) return;
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final manufacturer = androidInfo.manufacturer.toLowerCase();
      if (!manufacturer.contains('huawei') && !manufacturer.contains('honor')) {
        return;
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Row(children: [
            Icon(Icons.battery_alert, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(
                child: Text('Important Battery Setting',
                    style: TextStyle(color: Colors.white, fontSize: 16))),
          ]),
          content: const Text(
            'Huawei/Honor phones can block live location sharing unless a setting is changed.\n\n'
            'To fix this:\n'
            'Settings \u2192 Battery \u2192 App launch \u2192 find Guardian SOS \u2192 switch to '
            '"Manage manually" \u2192 enable all three toggles.\n\n'
            'Without this, your location may stop updating during an emergency.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final p = await SharedPreferences.getInstance();
                await p.setBool('huaweiWarningDismissed', true);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text("Got it, don't show again",
                  style: TextStyle(color: Colors.orange)),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Huawei check error: $e');
    }
  }

  Future<void> _initFcm() async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      // Refresh token in case it changed
      final deviceId = await getDeviceId();
      final companyId = await getSavedCompanyId() ?? '';
      final role = await getSavedRole();
      if (companyId.isNotEmpty) {
        await saveFcmToken(deviceId, companyId, role);
      }
      // Handle foreground notifications
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (message.notification != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${message.notification!.title ?? "Alert"}: '
                  '${message.notification!.body ?? ""}'),
              backgroundColor: Colors.red[800],
              duration: const Duration(seconds: 6),
            ),
          );
        }
      });
    } catch (e) {
      debugPrint('FCM init error: \$e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadProfile();
  }

  void _startCrashDetection() {
    _accelSubscription?.cancel();
    _accelSubscription = accelerometerEventStream(
            samplingPeriod: SensorInterval.normalInterval)
        .listen((AccelerometerEvent e) {
      final totalG =
          (e.x * e.x + e.y * e.y + e.z * e.z) / (_gravity * _gravity);
      final gForce = totalG.abs();
      if (gForce >= _crashThresholdG) {
        if (!_crashCountdownActive && !_sosActive && mounted) {
          _triggerCrashCountdown();
        }
      }
    });
  }
  Future<void> _playCrashBeep() async {
    try {
      final int remaining = _crashCountdownSeconds.clamp(0, 30);
      final double progress = 1 - (remaining / 30);
      final double volume = (0.4 + progress * 0.6).clamp(0.4, 1.0);
      final int freq = (900 + progress * 300).round();
      final bytes = _generateBeepTone(frequency: freq);
      await _crashBeepPlayer.play(BytesSource(bytes), volume: volume);
    } catch (e) {
      debugPrint('Crash beep error: $e');
    }
  }

  void _stopCrashDetection() {
    _accelSubscription?.cancel();
    _accelSubscription = null;
    _crashCountdownTimer?.cancel();
    _crashBeepPlayer.stop();
    if (mounted) {
      setState(() {
        _crashCountdownActive = false;
        _crashCountdownSeconds = 30;
      });
    }
  }

  void _triggerCrashCountdown() {
    if (_crashCountdownActive || _sosActive) return;
    Vibration.vibrate(pattern: [0, 500, 200, 500]);
    setState(() {
      _crashCountdownActive = true;
      _crashCountdownSeconds = 30;
    });
    _playCrashBeep();
    _crashCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (!mounted) { t.cancel(); return; }
      if (!mounted) { t.cancel(); return; }
      setState(() => _crashCountdownSeconds--);
      // Vibrate every 5 seconds
      if (_crashCountdownSeconds % 5 == 0) {
        Vibration.vibrate(duration: 300);
      }
      _playCrashBeep();
      if (_crashCountdownSeconds <= 10 && _crashCountdownSeconds > 0) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_crashCountdownActive) _playCrashBeep();
        });
      }
      if (_crashCountdownSeconds <= 0) {
        t.cancel();
        setState(() => _crashCountdownActive = false);
        // Auto-fire SOS
        _triggerSOS(isCrash: true);
      }
    });
  }

  void _cancelCrashCountdown() {
    _crashCountdownTimer?.cancel();
    _crashBeepPlayer.stop();
    Vibration.vibrate(duration: 200);
    if (mounted) {
      setState(() {
        _crashCountdownActive = false;
        _crashCountdownSeconds = 30;
      });
    }
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

  Future<void> _notifyCompany(
      String companyId, String riderName, double lat, double lng,
      {String alertType = 'SOS', String? customMessage}) async {
    try {
      final currentId = await getDeviceId();
      // Get ALL devices in this company - members and officers alike
      final devicesSnap = await FirebaseFirestore.instance
          .collection('devices')
          .where('companyId', isEqualTo: companyId)
          .get();

      for (final device in devicesSnap.docs) {
        final recipientDeviceId = device.id;
        // Don't alert the sender themselves
        if (recipientDeviceId == currentId) continue;

        final profileSnap = await FirebaseFirestore.instance
            .collection('profiles')
            .doc(recipientDeviceId)
            .get();
        if (!profileSnap.exists) continue;
        final data = profileSnap.data() ?? {};

        String phone = (data['mobilePhone'] ?? '').toString().trim();
        if (phone.isEmpty) phone = (data['contact1Phone'] ?? '').toString().trim();
        if (phone.isEmpty) continue;

        // Check radius preference (0 = everyone/unlimited)
        final radiusKm = (data['notifyRadiusKm'] is int) ? data['notifyRadiusKm'] as int : 0;
        if (radiusKm > 0) {
          // Try to get recipient's last known location from tracking collection
          final trackingSnap = await FirebaseFirestore.instance
              .collection('tracking')
              .where('deviceId', isEqualTo: recipientDeviceId)
              .where('active', isEqualTo: true)
              .limit(1)
              .get();
          if (trackingSnap.docs.isNotEmpty) {
            final tData = trackingSnap.docs.first.data();
            final tLat = (tData['lat'] is num) ? (tData['lat'] as num).toDouble() : 0.0;
            final tLng = (tData['lng'] is num) ? (tData['lng'] as num).toDouble() : 0.0;
            if (tLat != 0.0 && tLng != 0.0) {
              final dist = _distanceKm(lat, lng, tLat, tLng);
              if (dist > radiusKm) continue; // outside their chosen radius, skip
            }
            // if no valid last-known location, fall through and notify anyway
          }
          // if no tracking doc at all, fall through and notify anyway (safety net)
        }

        final countryCode = (data['countryCode'] ?? '27').toString();
        // SOS/Crash are urgent - skip WhatsApp here too, rely on guaranteed FCM push
        if (alertType != 'SOS' && alertType != 'CRASH') {
          await sendWhatsAppAlert(
            phone: phone,
            userName: riderName,
            lat: lat,
            lng: lng,
            countryCode: countryCode,
            alertType: alertType,
            customMessage: customMessage,
          );
        }
        // Send FCM push notification
        final fcmToken = (data['fcmToken'] ?? '').toString().trim();
        if (fcmToken.isNotEmpty) {
          final alertTitle = alertType == 'SOS'
              ? 'EMERGENCY SOS'
              : alertType == 'CRASH'
              ? 'CRASH DETECTED'
              : alertType == 'LOST'
              ? 'RIDER LOST'
              : alertType == 'FUEL'
              ? 'FUEL REQUEST'
              : alertType == 'BREAKDOWN'
              ? 'BREAKDOWN'
              : alertType == 'MEDICAL'
              ? 'MEDICAL EMERGENCY'
              : 'ALERT';
          await sendFcmToDevice(
            fcmToken,
            '\$alertTitle — \$riderName',
            'Tap to open the app and respond.',
          );
        }
      }
    } catch (e) {
      debugPrint('Company notify error: \$e');
    }
  }

  Future<void> _sendWhatsAppAlerts(
      Map<String, dynamic> profile, double lat, double lng,
      {String alertType = 'SOS', String? customMessage}) async {
    final userName = profile['name'] ?? 'User';
    final countryCode = (profile['countryCode'] ?? '27').toString();
    final riderPhone = (profile['mobilePhone'] ?? '').toString().trim();
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
          countryCode: countryCode,
          alertType: alertType,
          riderPhone: riderPhone,
          customMessage: customMessage,
        );
      }
    }
  }

  void _triggerSOS({bool isCrash = false}) async {
    _stopHolding();

    final connected = await hasInternet();
    if (!connected) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Row(children: [
              Icon(Icons.wifi_off, color: Colors.red, size: 24),
              SizedBox(width: 8),
              Text('No Internet Connection'),
            ]),
            content: const Text(
              'Cannot send SOS  -  your phone has no internet connection.\n\n'
              'Please enable WiFi or mobile data, then try again.\n\n'
              'You can still call emergency services directly.',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close',
                    style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.call),
                label: const Text('Call 112'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red),
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
      final deviceId = await getDeviceId();
      if (currentRole == 'dependent' &&
          (_dependentRelationship.isEmpty || _dependentLinkedMemberName.isEmpty)) {
        final deviceDoc = await FirebaseFirestore.instance
            .collection('devices')
            .doc(deviceId)
            .get();
        _dependentRelationship = (deviceDoc.data()?['relationship'] ?? '').toString();
        _dependentLinkedMemberName =
            (deviceDoc.data()?['linkedMemberName'] ?? '').toString();
      }

      DocumentReference doc =
          await FirebaseFirestore.instance.collection('alerts').add({
        'userName': profile['name'] ?? 'User',
        'mobilePhone': profile['mobilePhone'] ?? '',
        'lat': pos.latitude,
        'lng': pos.longitude,
        'status': 'ACTIVE',
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'profile': profile,
        'companyId': widget.company.id,
        'deviceId': deviceId,
        'helpType': isCrash ? 'CRASH' : 'SOS',
        'isDependent': currentRole == 'dependent',
        'relationship': _dependentRelationship,
        'linkedMemberName': _dependentLinkedMemberName,
      });

      _activeAlertId = doc.id;
      _lastProfile = profile;
      _lastLat = pos.latitude;
      _lastLng = pos.longitude;

      await startLocationService(doc.id, widget.company.id);

      if (mounted) setState(() => _sosActive = true);

      // Update family tracking status
      await _updateTrackingStatus(deviceId, 'SOS', lat: pos.latitude, lng: pos.longitude);

      // SOS/Crash are urgent - rely on guaranteed FCM push, not WhatsApp (requires a manual tap to send)
      // Notify the whole company, respecting radius preferences
      await _notifyCompany(
        widget.company.id,
        profile['name'] ?? 'Rider',
        pos.latitude,
        pos.longitude,
        alertType: isCrash ? 'CRASH' : 'SOS',
      );
    } catch (e) {
      debugPrint("SOS Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to send SOS: $e")));
      }
    }
  }

  Widget _helpButton(String label, IconData icon, Color color, String type) {
    return GestureDetector(
      onTap: () => _sendHelpAlert(type, label),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          border: Border.all(color: color.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
  Future<String?> _showOtherAlertDialog() async {
    final textController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Describe the issue'),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'What do you need help with?',
            hintStyle: TextStyle(color: Colors.grey),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.of(ctx).pop(
                textController.text.trim().isEmpty ? 'Other assistance needed' : textController.text.trim()),
            child: const Text('Send Alert'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _sendHelpAlert(String type, String label) async {
    String customMessage = '';
    if (type == 'OTHER') {
      final message = await _showOtherAlertDialog();
      if (message == null) return;
      customMessage = message;
    } else {
      // Confirm before sending
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text('Send $label Alert?'),
          content: Text('This will notify your guide that you need $label assistance. Are you sure?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Yes, Send Alert'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    final connected = await hasInternet();
    if (!connected) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No internet connection')));
      return;
    }
    try {
      Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final profile = await _getProfileSnapshot();
      final deviceId = await getDeviceId();
      final doc = await FirebaseFirestore.instance.collection('alerts').add({
        'userName': profile['name'] ?? 'Rider',
        'mobilePhone': profile['mobilePhone'] ?? '',
        'lat': pos.latitude,
        'lng': pos.longitude,
        'status': 'ACTIVE',
        'helpType': type,
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'profile': profile,
        'companyId': widget.company.id,
        'deviceId': deviceId,
        'customMessage': customMessage,
      });
      await startLocationService(doc.id, widget.company.id);
      Vibration.vibrate(duration: 500);
      await _sendWhatsAppAlerts(profile, pos.latitude, pos.longitude,
          alertType: type, customMessage: customMessage.isNotEmpty ? customMessage : null);
      // Notify the whole company, respecting radius preferences
      await _notifyCompany(
        widget.company.id,
        profile['name'] ?? 'Rider',
        pos.latitude,
        pos.longitude,
        alertType: type,
        customMessage: customMessage.isNotEmpty ? customMessage : null,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(label + ' alert sent - organiser notified!'),
            backgroundColor: Colors.green[800],
          ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send alert: ' + e.toString())));
    }
  }
  Future<void> _startNotificationListener() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      // Listen for new notifications addressed to this device
      _notificationSubscription = FirebaseFirestore.instance
          .collection('notifications')
          .where('token', isEqualTo: token)
          .where('delivered', isEqualTo: false)
          .snapshots()
          .listen((snap) async {
        for (final doc in snap.docs) {
          final data = doc.data();
          final title = data['title'] ?? 'Alert';
          final body = data['body'] ?? '';
          // Show local notification
          await showAlertNotification(
            title,
            body,
            notificationId: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          );
          // Mark as delivered
          await doc.reference.update({'delivered': true});
        }
      });
    } catch (e) {
      debugPrint('Notification listener error: \$e');
    }
  }

  Future<void> _startSharing() async {
    final deviceId = await getDeviceId();
    final name = _nameController.text.isNotEmpty ? _nameController.text : 'Rider';
    await _getOrCreateTrackingToken(deviceId, widget.company.id, name);
    // Get immediate position on start
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _updateTrackingStatus(deviceId, 'RIDING', lat: pos.latitude, lng: pos.longitude);
    } catch (e) {
      await _updateTrackingStatus(deviceId, 'RIDING');
    }
    setState(() {
      _isSharing = true;
      _hasShared = false;
      _shareFlash = false;
    });

    // Start flashing share icon
    _shareFlashTimer?.cancel();
    _shareFlashTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (mounted && _isSharing && !_hasShared) {
        setState(() => _shareFlash = !_shareFlash);
      } else if (mounted && _shareFlash) {
        setState(() => _shareFlash = false);
      }
    });

    // Auto-open WhatsApp with tracking link
    try {
      final token = await _getOrCreateTrackingToken(deviceId, widget.company.id, name);
      final trackLink = 'https://sos.cyberwarriors.co.za/track/?t=$token';
      final msg = Uri.encodeComponent('Track my ride live: $trackLink');
      final wa = Uri.parse('whatsapp://send?text=$msg');
      if (await canLaunchUrl(wa)) {
        await launchUrl(wa, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Auto share error: $e');
    }

    _shareTimer = Timer.periodic(
      Duration(minutes: _shareIntervalMinutes),
      (_) async {
        if (!_isSharing || _sosActive) return;
        try {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          final id = await getDeviceId();
          await _updateTrackingStatus(id, 'RIDING', lat: pos.latitude, lng: pos.longitude);
        } catch (e) {
          debugPrint('Share location error: \$e');
        }
      },
    );
  }

  Future<void> _stopSharing() async {
    _shareTimer?.cancel();
    _shareTimer = null;
    _shareFlashTimer?.cancel();
    _shareFlashTimer = null;
    setState(() {
      _isSharing = false;
      _shareFlash = false;
      _hasShared = false;
    });
    final deviceId = await getDeviceId();
    await _updateTrackingStatus(deviceId, 'IDLE');
  }

  void _onSOSCancelled() {
    setState(() => _sosActive = false);
    // Always stop service when SOS ends
    stopLocationService();
    // Update family tracking
    getDeviceId().then((id) => _updateTrackingStatus(id, 'IDLE'));
    if (_crashDetectionEnabled) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _crashDetectionEnabled) _startCrashDetection();
      });
    }
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
    _accelSubscription?.cancel();
    _crashCountdownTimer?.cancel();
    _shareTimer?.cancel();
    _shareFlashTimer?.cancel();
    _notificationSubscription?.cancel();
    _controller.dispose();
    _nameController.dispose();
    // Stop foreground service if no active SOS when screen is disposed
    if (!_sosActive) {
      stopLocationService();
    }
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

    return Stack(
      children: [
        Column(
          children: [
        if (!_hasInternet)
          Container(
            width: double.infinity,
            color: Colors.red[900],
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: const Row(children: [
              Icon(Icons.wifi_off, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No internet — SOS will not work. Enable WiFi or mobile data.',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ]),
          ),
        Expanded(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(30.0, 30.0, 30.0, 100.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: "Your Name",
                      border: const OutlineInputBorder(),
                      helperText: _nameController.text.isEmpty
                          ? "Please enter your name before sending SOS"
                          : "Also editable in Profile",
                    ),
                    onChanged: (val) async {
                      final id = await getDeviceId();
                      await FirebaseFirestore.instance
                          .collection('profiles')
                          .doc(id)
                          .set({'name': val.trim()},
                              SetOptions(merge: true));
                    },
                  ),
                  const SizedBox(height: 12),
                  // Live tracking controls
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: _isSharing ? Colors.green.withOpacity(0.5) : Colors.white12),
                      borderRadius: BorderRadius.circular(12),
                      color: _isSharing ? Colors.green.withOpacity(0.08) : Colors.transparent,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: Icon(_isSharing ? Icons.location_off : Icons.share_location, size: 18),
                                label: Text(_isSharing ? 'Stop sharing location' : 'Share live location',
                                    style: const TextStyle(fontSize: 13)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isSharing ? Colors.red[800] : Colors.green[800],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                                onPressed: _isSharing ? _stopSharing : _startSharing,
                              ),
                            ),
                            if (_isSharing) ...[
                              const SizedBox(width: 8),
                              FutureBuilder<String>(
                                future: getDeviceId().then((id) => _getOrCreateTrackingToken(
                                  id, widget.company.id,
                                  _nameController.text.isNotEmpty ? _nameController.text : 'Rider',
                                )),
                                builder: (context, snap) {
                                  if (!snap.hasData) return const SizedBox.shrink();
                                  final link = 'https://sos.cyberwarriors.co.za/track/?t=\${snap.data}';
                                   return AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _shareFlash ? Colors.orange.withOpacity(0.3) : Colors.transparent,
                                      boxShadow: _shareFlash ? [BoxShadow(color: Colors.orange.withOpacity(0.6), blurRadius: 12, spreadRadius: 2)] : [],
                                    ),
                                    child: IconButton(
                                      icon: Icon(Icons.share,
                                        color: _shareFlash ? Colors.orange : Colors.white70,
                                        size: _shareFlash ? 26 : 24,
                                      ),
                                      tooltip: 'Share tracking link',
                                      onPressed: () async {
                                        setState(() => _hasShared = true);
                                        final trackLink = 'https://sos.cyberwarriors.co.za/track/?t=${snap.data}';
                                        final msg = Uri.encodeComponent('Track my ride live: $trackLink');
                                        final wa = Uri.parse('whatsapp://send?text=$msg');
                                        if (await canLaunchUrl(wa)) {
                                          await launchUrl(wa, mode: LaunchMode.externalApplication);
                                        } else {
                                          await launchUrl(wa, mode: LaunchMode.platformDefault);
                                        }
                                      },
                                    ));
                                },
                              ),
                            ],
                          ],
                        ),
                        if (!_isSharing) ...[
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                const Text('Update: ', style: TextStyle(color: Colors.white54, fontSize: 12)),
                                const SizedBox(width: 6),
                                ...[
                                  ['🔴 30s', 0],
                                  ['🟡 2min', 2],
                                  ['🟢 5min', 5],
                                  ['🔵 15min', 15],
                                ].map((opt) => Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: GestureDetector(
                                    onTap: () => setState(() => _shareIntervalMinutes = opt[1] as int),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _shareIntervalMinutes == opt[1]
                                            ? Colors.white24 : Colors.transparent,
                                        border: Border.all(color: Colors.white24),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(opt[0] as String,
                                          style: const TextStyle(fontSize: 11, color: Colors.white70)),
                                    ),
                                  ),
                                )).toList(),
                              ],
                            ),
                          ),
                        ],
                        if (_isSharing)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '🟢 Family can see your location · Updates every ' + (_shareIntervalMinutes == 0 ? '30s' : '\$_shareIntervalMinutes min'),
                              style: const TextStyle(fontSize: 11, color: Colors.green),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: keyboardOpen ? 12 : 40),
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
                                color: color)),
                        Container(
                          width: buttonSize,
                          height: buttonSize,
                          decoration: BoxDecoration(
                              color: _isHolding
                                  ? color.withOpacity(0.7)
                                  : color,
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
                        color: _isHolding ? color : Colors.grey,
                        fontSize: 16),
                  ),
                  const SizedBox(height: 30),
                  // Crash Detection toggle
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: _crashDetectionEnabled
                              ? Colors.orange.withOpacity(0.6)
                              : Colors.grey.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(children: [
                          Icon(Icons.two_wheeler,
                              color: _crashDetectionEnabled
                                  ? Colors.orange
                                  : Colors.grey,
                              size: 22),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Crash Detection',
                                  style: TextStyle(
                                      color: _crashDetectionEnabled
                                          ? Colors.white
                                          : Colors.grey,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                              Text(
                                  _crashDetectionEnabled
                                      ? 'Active  -  watching for impact'
                                      : 'Turn on when riding',
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 11)),
                            ],
                          ),
                        ]),
                        Switch(
                          value: _crashDetectionEnabled,
                          activeColor: Colors.orange,
                          onChanged: (v) {
                            setState(() => _crashDetectionEnabled = v);
                            if (v) {
                              _startCrashDetection();
                            } else {
                              _stopCrashDetection();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  // Help buttons — available for all company types
                  ...[
                    const SizedBox(height: 20),
                    const Text('Need help?',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _helpButton('Lost', Icons.explore_off, Colors.blue, 'LOST')),
                      const SizedBox(width: 8),
                      Expanded(child: _helpButton('Fuel', Icons.local_gas_station, Colors.orange, 'FUEL')),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: _helpButton('Breakdown', Icons.build, Colors.purple, 'BREAKDOWN')),
                      const SizedBox(width: 8),
                      Expanded(child: _helpButton('Other', Icons.more_horiz, Colors.grey, 'OTHER')),
                    ]),
                  ],
                  // Hidden test button  -  long press the toggle container label
                  const SizedBox(height: 8),
                  if (_crashDetectionEnabled)
                    GestureDetector(
                      onLongPress: () {
                        // Long press for 2 seconds to trigger test
                        _triggerCrashCountdown();
                      },
                      child: const Text(
                        'Hold here 2 seconds to test',
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
          ],
        ),
        // Crash countdown overlay
        if (_crashCountdownActive)
          Positioned.fill(
            child: Material(
              color: Colors.black.withOpacity(0.92),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 80),
                  const SizedBox(height: 20),
                  const Text('CRASH DETECTED',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2)),
                  const SizedBox(height: 12),
                  const Text('Sending SOS in... tap CANCEL if you are OK',
                      style: TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 20),
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.orange, width: 6),
                    ),
                    child: Center(
                      child: Text('$_crashCountdownSeconds',
                          style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 72,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 32),
                  GestureDetector(
                    onTap: _cancelCrashCountdown,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 40, vertical: 18),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(40),
                      ),
                      child: const Text("I'M OK  -  CANCEL",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Tap to cancel if you are not injured',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
// HUD SCREEN
// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
class HUDScreen extends StatefulWidget {
  final double targetLat;
  final double targetLng;
  final String clientName;
  final CompanyConfig company;

  const HUDScreen({
    super.key,
    required this.targetLat,
    required this.targetLng,
    required this.clientName,
    required this.company,
  });

  @override
  State<HUDScreen> createState() => _HUDScreenState();
}

class _HUDScreenState extends State<HUDScreen>
    with SingleTickerProviderStateMixin {
  bool _hudMode = true;
  double _bearing = 0;
  double _distance = 0;
  Position? _myPosition;
  StreamSubscription<Position>? _positionStream;
  late AnimationController _arrowController;
  late Animation<double> _arrowAnimation;

  List<String> _steps = [];
  String _currentStep = '';
  String _nextStep = '';
  double _stepDistance = 0;
  bool _loadingRoute = false;
  String _routeError = '';
  static const _orsKey =
      '5b3ce3597851110001cf62480c1176b45bc84daca07549bef1cc40b6';

  @override
  void initState() {
    super.initState();
    _arrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _arrowAnimation =
        Tween<double>(begin: 0, end: 0).animate(_arrowController);
    _startTracking();
  }

  void _startTracking() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      _updatePosition(pos);
      _fetchRoute(pos);
    } catch (_) {}

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      ),
    ).listen((pos) {
      _updatePosition(pos);
      if (_steps.isEmpty || _distance.remainder(200) < 20) {
        _fetchRoute(pos);
      }
    });
  }

  Future<void> _fetchRoute(Position pos) async {
    if (_loadingRoute) return;
    setState(() {
      _loadingRoute = true;
      _routeError = '';
    });
    try {
      final url = Uri.parse(
        'https://api.openrouteservice.org/v2/directions/driving-car'
        '?api_key=$_orsKey'
        '&start=${pos.longitude},${pos.latitude}'
        '&end=${widget.targetLng},${widget.targetLat}',
      );
      final client = HttpClient();
      final request = await client.getUrl(url);
      request.headers.set('Accept', 'application/json, application/geo+json');
      final response = await request.close();
      final body =
          await response.transform(const Utf8Decoder()).join();
      client.close();

      if (response.statusCode == 200) {
        final data = jsonDecode(body);
        final segments =
            data['features'][0]['properties']['segments'];
        if (segments != null && segments.isNotEmpty) {
          final steps = segments[0]['steps'] as List;
          final instructions = steps
              .map<String>((s) => s['instruction']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
          final distances = steps
              .map<double>(
                  (s) => (s['distance'] as num?)?.toDouble() ?? 0)
              .toList();

          setState(() {
            _steps = instructions;
            _currentStep =
                instructions.isNotEmpty ? instructions[0] : '';
            _nextStep =
                instructions.length > 1 ? instructions[1] : '';
            _stepDistance =
                distances.isNotEmpty ? distances[0] : 0;
            _loadingRoute = false;
          });
        }
      } else {
        setState(() {
          _routeError = 'Route unavailable';
          _loadingRoute = false;
        });
      }
    } catch (e) {
      setState(() {
        _routeError = 'No route data';
        _loadingRoute = false;
      });
    }
  }

  void _updatePosition(Position pos) {
    if (!mounted) return;
    final bearing = Geolocator.bearingBetween(
      pos.latitude,
      pos.longitude,
      widget.targetLat,
      widget.targetLng,
    );
    final distance = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      widget.targetLat,
      widget.targetLng,
    );

    _arrowAnimation = Tween<double>(
      begin: _arrowAnimation.value,
      end: bearing * (pi / 180),
    ).animate(CurvedAnimation(
      parent: _arrowController,
      curve: Curves.easeInOut,
    ));
    _arrowController.forward(from: 0);

    setState(() {
      _myPosition = pos;
      _bearing = bearing;
      _distance = distance;
    });
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _formatStepDistance(double meters) {
    if (meters < 1000) return 'in ${meters.toStringAsFixed(0)}m';
    return 'in ${(meters / 1000).toStringAsFixed(1)}km';
  }

  IconData _stepIcon(String instruction) {
    final lower = instruction.toLowerCase();
    if (lower.contains('left')) return Icons.turn_left;
    if (lower.contains('right')) return Icons.turn_right;
    if (lower.contains('straight') || lower.contains('continue'))
      return Icons.straight;
    if (lower.contains('roundabout')) return Icons.roundabout_left;
    if (lower.contains('arrive') || lower.contains('destination'))
      return Icons.location_on;
    if (lower.contains('u-turn')) return Icons.u_turn_left;
    return Icons.navigation;
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _arrowController.dispose();
    super.dispose();
  }

  Widget _buildContent() {
    final color = widget.company.primaryColor;
    final hasRoute = _currentStep.isNotEmpty;

    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: Colors.white, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Text(widget.clientName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: Icon(
                      _hudMode
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: Colors.red,
                      size: 28,
                    ),
                    onPressed: () =>
                        setState(() => _hudMode = !_hudMode),
                  ),
                ],
              ),
            ),
            Text(
              _myPosition == null
                  ? 'Locating...'
                  : _formatDistance(_distance),
              style: TextStyle(
                  color:
                      _distance < 200 ? Colors.green : Colors.red,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2),
            ),
            Text(
              _distance < 200 ? 'ARRIVING' : 'TO CLIENT',
              style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                  letterSpacing: 4),
            ),
            const SizedBox(height: 12),
            if (_loadingRoute)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white38)),
                    SizedBox(width: 8),
                    Text('Getting directions...',
                        style: TextStyle(
                            color: Colors.white38, fontSize: 13)),
                  ],
                ),
              )
            else if (_routeError.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_routeError,
                    style: const TextStyle(
                        color: Colors.orange, fontSize: 13)),
              )
            else if (hasRoute) ...[
              Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: color.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    Icon(_stepIcon(_currentStep),
                        color: color, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatStepDistance(_stepDistance),
                            style: TextStyle(
                                color: color,
                                fontSize: 14,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _currentStep,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_nextStep.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      Icon(_stepIcon(_nextStep),
                          color: Colors.white38, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Then: $_nextStep',
                          style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            Expanded(
              child: Center(
                child: AnimatedBuilder(
                  animation: _arrowAnimation,
                  builder: (_, __) => Transform.rotate(
                    angle: _arrowAnimation.value,
                    child: Icon(Icons.navigation,
                        color: color, size: 120),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _hudMode
                    ? 'HUD MODE  -  Place phone on dashboard'
                    : 'NORMAL MODE  -  Tap ├░┬ü to flip for windscreen',
                style: const TextStyle(
                    color: Colors.white24,
                    fontSize: 11,
                    letterSpacing: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _hudMode
          ? Transform(
              alignment: Alignment.center,
              transform: Matrix4.rotationX(pi),
              child: _buildContent(),
            )
          : _buildContent(),
    );
  }
}

// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
// OFFICER DASHBOARD
// ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
class AlertHistoryScreen extends StatefulWidget {
  final CompanyConfig company;
  const AlertHistoryScreen({super.key, required this.company});
  @override
  State<AlertHistoryScreen> createState() => _AlertHistoryScreenState();
}

class _AlertHistoryScreenState extends State<AlertHistoryScreen> {
  String _formatTimestamp(dynamic ts) {
    if (ts == null || ts is! Timestamp) return '';
    final dt = ts.toDate();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, $h:$m';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'RESOLVED':
        return Colors.green;
      case 'CANCELLED':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Alert History')),
      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance
            .collection('alerts')
            .where('companyId', isEqualTo: widget.company.id)
            .orderBy('createdAt', descending: true)
            .limit(100)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Error loading history: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red)),
              ),
            );
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
                child: Text('No alerts yet', style: TextStyle(color: Colors.grey)));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final userName = data['userName'] ?? 'Rider';
              final helpType = data['helpType'] ?? 'SOS';
              final status = data['status'] ?? 'ACTIVE';
              final timeStr = _formatTimestamp(data['createdAt']);
              final responders = (data['responders'] as List?)
                      ?.whereType<Map>()
                      .map((r) => (r['name'] ?? '').toString())
                      .where((n) => n.isNotEmpty)
                      .toList() ??
                  <String>[];
              final resolvedBy = (data['resolvedBy'] ?? '').toString();
              final isDependent = data['isDependent'] == true;
              final relationship = (data['relationship'] ?? '').toString();
              final linkedMemberName = (data['linkedMemberName'] ?? '').toString();
              return Card(
                color: Colors.grey[900],
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                          child: Text(
                              isDependent &&
                                      relationship.isNotEmpty &&
                                      linkedMemberName.isNotEmpty
                                  ? '$helpType \u2014 $userName ($relationship of $linkedMemberName)'
                                  : '$helpType \u2014 $userName',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: _statusColor(status).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(status,
                                style: TextStyle(
                                    color: _statusColor(status),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(timeStr, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      if (responders.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('Responded: ${responders.join(', ')}',
                              style: const TextStyle(color: Colors.orange, fontSize: 12)),
                        ),
                      if (resolvedBy.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Resolved by: $resolvedBy',
                              style: const TextStyle(color: Colors.green, fontSize: 12)),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// OFFICER DASHBOARD
// ────────────────────────────────────────────────────────────────────────────
class FamilyScreen extends StatefulWidget {
  final CompanyConfig company;
  const FamilyScreen({super.key, required this.company});
  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  String _familyCode = '';
  bool _loading = true;
  List<Map<String, dynamic>> _dependents = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final deviceId = await getDeviceId();
    final profileDoc = await FirebaseFirestore.instance
        .collection('profiles')
        .doc(deviceId)
        .get();
    _familyCode = (profileDoc.data()?['familyCode'] ?? '').toString();
    if (_familyCode.isEmpty) {
      final rand = math.Random();
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      final code =
          List.generate(5, (_) => chars[rand.nextInt(chars.length)]).join();
      _familyCode = 'FAM-$code';
      await FirebaseFirestore.instance
          .collection('profiles')
          .doc(deviceId)
          .set({'familyCode': _familyCode}, SetOptions(merge: true));
    }
    final depSnap = await FirebaseFirestore.instance
        .collection('devices')
        .where('linkedMemberId', isEqualTo: deviceId)
        .where('role', isEqualTo: 'dependent')
        .get();
    _dependents = depSnap.docs
        .where((d) => d.data()['removedByMember'] != true)
        .map((d) => {'id': d.id, ...d.data()})
        .toList();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _inviteFamilyMember() async {
    try {
      final granted =
          await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Contacts permission denied')));
        }
        return;
      }
      final contact = await FlutterContacts.openExternalPick();
      if (contact == null || contact.phones.isEmpty) return;
      String cleaned = contact.phones.first.number
          .replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
      if (cleaned.startsWith('00')) cleaned = cleaned.substring(2);
      if (cleaned.startsWith('0')) cleaned = '27' + cleaned.substring(1);
      if (!cleaned.startsWith('27')) cleaned = '27' + cleaned;
      final message = Uri.encodeComponent(
          "Hi ${contact.displayName}! Join our club safety app so we can help "
          "if you're ever in trouble.\n\n"
          "Download: https://sos.cyberwarriors.co.za/join/highway-devils.html\n\n"
          "Your family code: $_familyCode");
      final uri = Uri.parse('whatsapp://send?phone=$cleaned&text=$message');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not send invite: $e')));
      }
    }
  }

  Future<void> _removeDependent(String deviceId, String relationship) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Remove family member?'),
        content: Text(
            '$relationship will no longer be able to use the app under your account. This frees up a slot.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await FirebaseFirestore.instance
        .collection('devices')
        .doc(deviceId)
        .update({'removedByMember': true, 'isActive': false});
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final maxSlots = widget.company.maxDependentsPerMember;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Family Members')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blue[700]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Your family code',
                          style: TextStyle(
                              color: Colors.blue, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                  _familyCode.isEmpty ? '...' : _familyCode,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      letterSpacing: 1.5)),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, color: Colors.blue),
                            onPressed: _familyCode.isEmpty
                                ? null
                                : () {
                                    Clipboard.setData(
                                        ClipboardData(text: _familyCode));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text('Code copied')));
                                  },
                          ),
                          IconButton(
                            icon: const Icon(Icons.person_add_alt,
                                color: Colors.green),
                            onPressed: _familyCode.isEmpty
                                ? null
                                : _inviteFamilyMember,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('${_dependents.length} of $maxSlots family members added',
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 8),
                if (_dependents.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                        child: Text('No family members yet',
                            style: TextStyle(color: Colors.grey))),
                  ),
                for (final dep in _dependents)
                  Card(
                    color: Colors.grey[900],
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.person, color: Colors.orange),
                      title: Text(
                          (dep['relationship'] ?? 'Family member').toString(),
                          style: const TextStyle(color: Colors.white)),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            color: Colors.red),
                        onPressed: () => _removeDependent(
                            dep['id'],
                            (dep['relationship'] ?? 'this family member')
                                .toString()),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// OFFICER DASHBOARD
// ────────────────────────────────────────────────────────────────────────────
class _PulsingRespondButton extends StatefulWidget {
  final bool amResponding;
  final bool pulse;
  final VoidCallback onPressed;
  const _PulsingRespondButton({
    required this.amResponding,
    required this.pulse,
    required this.onPressed,
  });
  @override
  State<_PulsingRespondButton> createState() => _PulsingRespondButtonState();
}

class _PulsingRespondButtonState extends State<_PulsingRespondButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton.icon(
      icon: Icon(widget.amResponding ? Icons.close : Icons.directions_run,
          color: Colors.black),
      label: Text(widget.amResponding ? "UN-RESPOND" : "RESPOND",
          style: const TextStyle(
              color: Colors.black, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
          backgroundColor: widget.amResponding ? Colors.grey : Colors.green,
          padding: const EdgeInsets.all(12)),
      onPressed: widget.onPressed,
    );
    if (!widget.pulse) return button;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: 0.6 + (_controller.value * 0.4),
        child: child,
      ),
      child: button,
    );
  }
}

class OfficerDashboard extends StatefulWidget {
  final CompanyConfig company;
  final double responseRadiusKm;
  const OfficerDashboard({
    super.key,
    required this.company,
    this.responseRadiusKm = 9999,
  });
  @override
  State<OfficerDashboard> createState() => _OfficerDashboardState();
}

class _OfficerDashboardState extends State<OfficerDashboard> {
  Future<void> _notifyCompanyOfUpdate(
      String companyId, String excludeDeviceId, String message) async {
    try {
      final devicesSnap = await FirebaseFirestore.instance
          .collection('devices')
          .where('companyId', isEqualTo: companyId)
          .get();
      for (final device in devicesSnap.docs) {
        if (device.id == excludeDeviceId) continue;
        final token = (device.data()['fcmToken'] ?? '').toString().trim();
        if (token.isEmpty) continue;
        await sendFcmToDevice(token, 'Alert Update', message);
      }
    } catch (e) {
      debugPrint('Notify company update error: $e');
    }
  }
  String? _myDeviceId;
  final MapController _mapCtrl = MapController();
  Set<String> _knownAlertIds = {};
  bool _mapReady = false;
  bool _isMuted = false;
  bool _tilesLoaded = false;
  Map<String, dynamic>? _selectedAlert;
  String? _selectedAlertId;
  bool _panelOpen = false;
  Position? _officerPosition;
  bool _crashFlash = false;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    getDeviceId().then((id) {
      if (mounted) setState(() => _myDeviceId = id);
    });
    _getOfficerPosition();
    _flashTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _crashFlash = !_crashFlash);
    });
  }

  Future<void> _getOfficerPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium);
      if (mounted) setState(() => _officerPosition = pos);
    } catch (_) {}
  }

  /// Returns true if the alert is within the officer's response radius.
  /// If officer position unknown or radius is very large, show all alerts.
  bool _withinRadius(Map<String, dynamic> data) {
    if (_officerPosition == null) return true;
    final radius = widget.responseRadiusKm;
    if (radius >= 9000) return true; // "All" option
    final alertLat = (data['lat'] as num?)?.toDouble();
    final alertLng = (data['lng'] as num?)?.toDouble();
    if (alertLat == null || alertLng == null) return true;
    final dist = distanceKm(
        _officerPosition!.latitude,
        _officerPosition!.longitude,
        alertLat,
        alertLng);
    return dist <= radius;
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    // Stop all escalation timers when dashboard is closed
    SOSEscalationManager.stopAll();
    super.dispose();
  }

  void _playSiren(List<QueryDocumentSnapshot> alerts) {
    final latestData =
        alerts.isNotEmpty ? alerts.last.data() as Map<String, dynamic> : null;
    showAlertNotification(
      latestData?['userName'] ?? 'Unknown',
      '${latestData?['lat']?.toStringAsFixed(4) ?? ''}, '
          '${latestData?['lng']?.toStringAsFixed(4) ?? ''}',
      phone: (latestData?['mobilePhone'] ?? '').toString(),
    );
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

  void _navigateTo(Map<String, dynamic> data) async {
    final lat = (data['lat'] as num).toDouble();
    final lng = (data['lng'] as num).toDouble();

    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Navigate To Client',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose navigation mode:',
                style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.map),
                label: const Text('Google Maps  -  Normal'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.all(14)),
                onPressed: () => Navigator.of(ctx).pop('maps'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.remove_red_eye),
                label: const Text('Google Maps  -  HUD Mode'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.all(14)),
                onPressed: () => Navigator.of(ctx).pop('hud'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );

    if (choice == 'maps') {
      final uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (choice == 'hud') {
      final googleMapsHud = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
      if (await canLaunchUrl(googleMapsHud)) {
        await launchUrl(googleMapsHud,
            mode: LaunchMode.externalNonBrowserApplication);
      } else {
        final fallback = Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
        await launchUrl(fallback, mode: LaunchMode.externalApplication);
      }
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text('Enable HUD in Google Maps',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Once Google Maps opens:',
                    style:
                        TextStyle(color: Colors.white70, fontSize: 13)),
                SizedBox(height: 12),
                Text('1. Tap the ├ó menu (top right)',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                SizedBox(height: 6),
                Text('2. Tap "HUD mode"',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                SizedBox(height: 6),
                Text('3. Place phone on dashboard',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                SizedBox(height: 12),
                Text(
                    'Google Maps HUD reflects perfectly off your windscreen.',
                    style:
                        TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Got it'),
              ),
            ],
          ),
        );
      }
    }
  }

  // ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
  // RESOLVE ALERT  -  logs officer name + timestamp
  // ├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó├ó
  Future<void> _markResponding(String id) async {
    try {
      final deviceId = await getDeviceId();
      final profileDoc = await FirebaseFirestore.instance
          .collection('profiles').doc(deviceId).get();
      final responderName = (profileDoc.exists &&
              (profileDoc.data()?['name'] ?? '').isNotEmpty)
          ? profileDoc.data()!['name'] as String
          : 'Someone';

      final alertDoc =
          await FirebaseFirestore.instance.collection('alerts').doc(id).get();
      final existing =
          (alertDoc.data()?['responders'] as List?)?.whereType<Map>().toList() ??
              <Map>[];
      final alreadyThere = existing.any((r) => r['deviceId'] == deviceId);
      final others = existing.where((r) => r['deviceId'] != deviceId).toList();

      if (!alreadyThere && existing.isNotEmpty) {
        final names = others.map((r) => (r['name'] ?? 'Someone').toString()).join(', ');
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text('Already responding'),
            content: Text(
                '$names ${others.length == 1 ? "is" : "are"} already responding to this alert. Do you still want to respond?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text("Yes, I'll respond too"),
              ),
            ],
          ),
        );
        if (confirm != true) return;
      }

      final updatedList = [
        ...others,
        {
          'deviceId': deviceId,
          'name': responderName,
          'respondingAt': DateTime.now().toIso8601String(),
        },
      ];

      await FirebaseFirestore.instance.collection('alerts').doc(id).update({
        'responders': updatedList,
        'respondingBy': responderName,
        'respondingAt': FieldValue.serverTimestamp(),
      });

      await _notifyCompanyOfUpdate(
          widget.company.id, deviceId, '$responderName is responding to the alert.');
      SOSEscalationManager.stopEscalation(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Marked as responding - rider notified'),
            backgroundColor: Colors.orange[800]));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _unmarkResponding(String id) async {
    try {
      final deviceId = await getDeviceId();
      final alertDoc =
          await FirebaseFirestore.instance.collection('alerts').doc(id).get();
      final existing =
          (alertDoc.data()?['responders'] as List?)?.whereType<Map>().toList() ??
              <Map>[];
      final updatedList = existing.where((r) => r['deviceId'] != deviceId).toList();
      await FirebaseFirestore.instance.collection('alerts').doc(id).update({
        'responders': updatedList,
        'respondingBy': updatedList.isNotEmpty
            ? (updatedList.last['name'] ?? '').toString()
            : null,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No longer marked as responding'),
            backgroundColor: Colors.grey[800]));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')));
    }
  }
  Future<void> _resolveAlert(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Resolve Alert?'),
        content: const Text(
            'This marks the alert as fully handled and removes it from the active list. The rider will see their alert as resolved. Only do this if the situation is genuinely over - this cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, Resolve')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      // Get officer's device ID and look up their profile name
      final deviceId = await getDeviceId();
      final profileDoc = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(deviceId)
          .get();

      final officerName = (profileDoc.exists &&
              (profileDoc.data()?['name'] ?? '').isNotEmpty)
          ? profileDoc.data()!['name'] as String
          : 'Officer ($deviceId)';

      // Update the alert with resolution details
      await FirebaseFirestore.instance
          .collection('alerts')
          .doc(id)
          .update({
        'status': 'RESOLVED',
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': officerName,
        'resolvedByDeviceId': deviceId,
      });

      await _notifyCompanyOfUpdate(
          widget.company.id, deviceId, 'Alert resolved by $officerName.');

      // Stop escalation reminders for this specific alert
      SOSEscalationManager.stopEscalation(id);

      setState(() {
        _selectedAlert = null;
        _selectedAlertId = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('├ó Alert resolved by $officerName'),
            backgroundColor: Colors.green[800],
          ),
        );
      }
    } catch (e) {
      debugPrint('Resolve error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resolve alert: $e')),
        );
      }
    }
  }

  IconData _alertIcon(String? helpType) {
    switch (helpType) {
      case 'CRASH': return Icons.car_crash;
      case 'LOST': return Icons.explore_off;
      case 'FUEL': return Icons.local_gas_station;
      case 'BREAKDOWN': return Icons.build;
      case 'MEDICAL': return Icons.medical_services;
      default: return Icons.warning;
    }
  }
  Color _alertColor(String? helpType, Color defaultColor) {
    switch (helpType) {
      case 'LOST': return Colors.blue;
      case 'FUEL': return Colors.orange;
      case 'BREAKDOWN': return Colors.purple;
      case 'MEDICAL': return Colors.red;
      default: return defaultColor;
    }
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
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
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
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold)),
            const Divider(height: 24),
            _profileSection("Personal Information", Icons.person, [
              _profileRow("Name", profile['name']),
              _callableRow(context, "Mobile", profile['mobilePhone']),
              _callableEmailRow(context, "Email", profile['email']),
              _profileRow("ID Number", profile['idNumber']),
              _profileRow("Age", profile['age']),
              _profileRow("Blood Type", profile['bloodType']),
            ]),
            _profileSection(
                "Medical Information", Icons.medical_services, [
              _profileRow("Allergies", profile['allergies']),
              _profileRow("Conditions", profile['conditions']),
              _profileRow("Medications", profile['medications']),
            ]),
            _profileSection(
                "Emergency Contacts", Icons.contact_phone, [
              if ((profile['contact1Name'] ?? '').isNotEmpty) ...[
                _profileRow("Contact 1", profile['contact1Name']),
                _profileRow(
                    "Relationship", profile['contact1Rel']),
                _callableRow(
                    context, "Phone", profile['contact1Phone']),
              ],
              if ((profile['contact2Name'] ?? '').isNotEmpty) ...[
                const Divider(),
                _profileRow("Contact 2", profile['contact2Name']),
                _profileRow(
                    "Relationship", profile['contact2Rel']),
                _callableRow(
                    context, "Phone", profile['contact2Phone']),
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
        Row(children: [
          Icon(icon, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.red)),
        ]),
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
              child: Text(label,
                  style: const TextStyle(color: Colors.grey))),
          Expanded(
              child: Text(text, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }

  Widget _callableEmailRow(
      BuildContext context, String label, dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(color: Colors.grey))),
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final uri = Uri(scheme: 'mailto', path: text);
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
              child: Text(
                text,
                style: const TextStyle(
                    fontSize: 15,
                    color: Colors.lightBlue,
                    decoration: TextDecoration.underline),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _callableRow(
      BuildContext context, String label, dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(color: Colors.grey))),
          Expanded(
              child: Text(text, style: const TextStyle(fontSize: 15))),
          IconButton(
            icon:
                const Icon(Icons.call, color: Colors.green, size: 22),
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
      _mapCtrl.fitCamera(CameraFit.coordinates(
          coordinates: points, padding: const EdgeInsets.all(80)));
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
        // Filter by response radius
        final allAlerts = snapshot.data!.docs;
        final alerts = allAlerts.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return _withinRadius(data);
        }).toList();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          // Follow the selected alert's live position on the map
          if (_selectedAlertId != null) {
            final selectedDocs =
                alerts.where((d) => d.id == _selectedAlertId).toList();
            String followResult;
            if (selectedDocs.isEmpty) {
              followResult = 'no matching doc in alerts list (count=${alerts.length})';
            } else {
              final freshData =
                  selectedDocs.first.data() as Map<String, dynamic>;
              final lat = (freshData['lat'] as num?)?.toDouble();
              final lng = (freshData['lng'] as num?)?.toDouble();
              if (lat == null || lng == null) {
                followResult = 'lat/lng null on matched doc';
              } else {
                setState(() => _selectedAlert = freshData);
                if (!_mapReady) {
                  followResult = 'skipped - mapReady false';
                } else {
                  try {
                    final currentZoom = _mapCtrl.camera.zoom;
                    final targetZoom = currentZoom < 15 ? 16.0 : currentZoom;
                    _mapCtrl.move(LatLng(lat, lng), targetZoom);
                    followResult =
                        'moved to $lat,$lng zoom $targetZoom (was $currentZoom)';
                  } catch (e) {
                    followResult = 'exception during move: $e';
                  }
                }
              }
            }
            FirebaseFirestore.instance
                .collection('alerts')
                .doc(_selectedAlertId)
                .update({
              'debugCameraFollowAt': FieldValue.serverTimestamp(),
              'debugCameraFollowResult': followResult,
            }).catchError((_) {});
          }

          final currentIds = alerts.map((d) => d.id).toSet();
          final newIds = currentIds.difference(_knownAlertIds);
          final isFirstLoad =
              _knownAlertIds.isEmpty && alerts.isNotEmpty;

          // Start escalation for new alerts
          for (final doc in alerts) {
            final data = doc.data() as Map<String, dynamic>;
            if (newIds.contains(doc.id) || isFirstLoad) {
              SOSEscalationManager.startEscalation(doc.id, data);
            } else {
              // Update location data in escalation manager
              SOSEscalationManager.updateAlertData(doc.id, data);
            }
          }

          // Stop escalation for alerts no longer active
          final removedIds =
              SOSEscalationManager.trackedAlertIds.difference(currentIds);
          for (final id in removedIds) {
            SOSEscalationManager.stopEscalation(id);
          }

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
                    ),
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
                            Icon(
                                isSelected
                                    ? Icons.warning
                                    : _alertIcon(data['helpType'] as String?),
                                color: isSelected
                                    ? Colors.orange
                                    : (data['helpType'] == 'CRASH'
                                        ? (_crashFlash ? Colors.redAccent : Colors.white)
                                        : _alertColor(data['helpType'] as String?, color)),
                                size: data['helpType'] == 'CRASH' ? 44 : (isSelected ? 48 : 40)),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius:
                                      BorderRadius.circular(4)),
                              child: Text(
                                data['userName'] ?? 'User',
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white),
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
                              'Showing alerts within ${widget.responseRadiusKm.toStringAsFixed(0)} km',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            // Offline GPS fallback
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
            if (widget.responseRadiusKm < 9000)
              Positioned(
                bottom: 20 + MediaQuery.of(context).padding.bottom,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.radar,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.responseRadiusKm.toStringAsFixed(0)} km radius',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            if (alerts.isNotEmpty)
              Positioned(
                top: 20,
                right: 20,
                child: GestureDetector(
                  onTap: () => setState(() => _isMuted = !_isMuted),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.85),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isMuted ? Icons.volume_off : Icons.volume_up,
                      color: _isMuted ? Colors.orange : Colors.white,
                      size: 22,
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
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.warning,
                                    color: color, size: 28),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _selectedAlert!['userName'] ??
                                        'User',
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight:
                                            FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () => setState(
                                      () {
                                        _selectedAlert = null;
                                        _selectedAlertId = null;
                                      }),
                                ),
                              ],
                            ),
                            Text(
                              " ${_selectedAlert!['lat'].toStringAsFixed(5)}, ${_selectedAlert!['lng'].toStringAsFixed(5)}",
                              style:
                                  const TextStyle(color: Colors.grey),
                            ),
                            Text(
                              _lastSeen(_selectedAlert!['timestamp']),
                              style:
                                  const TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 12),
                            Builder(builder: (context) {
                              final phone = (_selectedAlert!['mobilePhone'] ?? '').toString().trim();
                              if (phone.isEmpty) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.phone, color: Colors.white),
                                    label: Text(
                                      'CALL RIDER  —  $phone',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green[700],
                                        padding: const EdgeInsets.all(14)),
                                    onPressed: () async {
                                      final uri = Uri(scheme: 'tel', path: phone);
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri);
                                      }
                                    },
                                  ),
                                ),
                              );
                            }),
                            Row(
                              children: [
                                Expanded(
                                  child: Builder(builder: (context) {
                                    final responders = (_selectedAlert?['responders'] as List?)
                                            ?.whereType<Map>()
                                            .toList() ??
                                        [];
                                    final amResponding = _myDeviceId != null &&
                                        responders.any((r) => r['deviceId'] == _myDeviceId);
                                    return _PulsingRespondButton(
                                      amResponding: amResponding,
                                      pulse: responders.isEmpty,
                                      onPressed: () => amResponding
                                          ? _unmarkResponding(_selectedAlertId!)
                                          : _markResponding(_selectedAlertId!),
                                    );
                                  }),
                                ),
                                const SizedBox(width: 8),
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
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.person, color: Colors.black),
                                    label: const Text("PROFILE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange[700],
                                        padding: const EdgeInsets.all(12)),
                                    onPressed: () {
                                      final rawProfile = _selectedAlert!['profile'];
                                      if (rawProfile != null) {
                                        // Merge top-level alert fields into profile so
                                        // mobilePhone is available even on older alerts
                                        final merged = Map<String, dynamic>.from(rawProfile);
                                        if ((merged['mobilePhone'] ?? '').toString().isEmpty) {
                                          merged['mobilePhone'] = (_selectedAlert!['mobilePhone'] ?? '').toString();
                                        }
                                        if ((merged['email'] ?? '').toString().isEmpty) {
                                          merged['email'] = (_selectedAlert!['email'] ?? '').toString();
                                        }
                                        _showProfile(context, merged);
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text("No profile available.")));
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: currentRole == 'officer'
                                      ? ElevatedButton.icon(
                                          icon: Icon(Icons.check_circle, color: Colors.grey[400]),
                                          label: Text("RESOLVE", style: TextStyle(color: Colors.grey[400])),
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.grey[850],
                                              padding: const EdgeInsets.all(12)),
                                          onPressed: () => _resolveAlert(_selectedAlertId!),
                                        )
                                      : const SizedBox.shrink(),
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
                              onPressed: () => setState(
                                  () => _panelOpen = false),
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
                                (data['isDependent'] == true &&
                                        (data['relationship'] ?? '').toString().isNotEmpty &&
                                        (data['linkedMemberName'] ?? '').toString().isNotEmpty)
                                    ? '${data['userName'] ?? 'User'} (${data['relationship']} of ${data['linkedMemberName']})'
                                    : data['userName'] ?? 'User',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal),
                              ),
                              subtitle: Text(
                                  _lastSeen(data['timestamp'])),
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
                                    icon: const Icon(Icons.directions_run,
                                        color: Colors.orange),
                                    onPressed: () => _markResponding(doc.id),
                                  ),
                                  if (currentRole == 'officer')
                                    IconButton(
                                      icon: const Icon(
                                          Icons.check_circle,
                                          color: Colors.green),
                                      onPressed: () =>
                                          _resolveAlert(doc.id),
                                    ),
                                ],
                              ),
                              onTap: () =>
                                  _selectAlert(doc.id, data),
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









