import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'mqtt_client_factory_io.dart'
    if (dart.library.html) 'mqtt_client_factory_web.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:io';
import 'auth_service.dart';
import 'login_page.dart';

class AppColors {
  static const Color primary = Color(0xFF1D4ED8);
  static const Color primaryDark = Color(0xFF1E3A8A);
  static const Color secondary = Color(0xFF3B82F6);
  static const Color accent = Color(0xFFFFB020);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color softBlue = Color(0xFFE8EDFF);
  static const Color background = Color(0xFFF5F7FF);
  static const Color textDark = Color(0xFF0F172A);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  try {
    await Firebase.initializeApp();
    print('Firebase initialized successfully');
  } catch (e) {
    print('Firebase initialization error: $e');
    // Continue even if Firebase fails (for development)
  }

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GPS Geofencing Tracker',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          background: AppColors.background,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.textDark,
          titleTextStyle: TextStyle(
            color: AppColors.textDark,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 3,
          margin: EdgeInsets.zero,
          shadowColor: AppColors.primary.withOpacity(0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Wrapper untuk check login status
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final isLoggedIn = await AuthService.isLoggedIn();
    setState(() {
      _isLoggedIn = isLoggedIn;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return _isLoggedIn ? const MqttHomePage() : const LoginPage();
  }
}

class MqttHomePage extends StatefulWidget {
  const MqttHomePage({super.key});

  @override
  State<MqttHomePage> createState() => _MqttHomePageState();
}

class _MqttHomePageState extends State<MqttHomePage> {
  MqttClient? client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage?>>>?
  _mqttSubscription;
  String status = "Disconnected";
  List<String> messages = [];

  // Local Notifications
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // Audio player untuk ringtone dengan konteks audio nada dering
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRingtonePlaying = false;

  // Geofencing data
  String? centerLat;
  String? centerLng;
  String? currentLat;
  String? currentLng;
  String? currentAlt;
  String? currentSpd;
  String? currentSats;
  String? distance;
  String? safeZoneRadius;
  String geofenceStatus = "UNKNOWN";
  double _currentSafeZoneRadius = 15.0; // Default safezone radius (meter)

  // Vibration sensor data
  String? lastVibrationTime;
  String? vibrationLocation;
  int vibrationCount = 0;

  // Relay control state
  bool _relayState = true; // Default: ON (relay aktif/motor dikunci)

  // Timer untuk notifikasi berulang seperti ringtone telepon
  Timer? _alertNotificationTimer;
  bool _isAlertActive = false;
  bool _espAwaitingAuthorization = false;
  String? _lastHandledAuthSession;
  DateTime? _lastAuthReplayAt;

  // Firestore instance
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _currentUserId;
  String? _currentCenterDocId;
  DateTime? _lastFirestoreSave;
  static const int _firestoreSaveInterval =
      30000; // Save ke Firestore setiap 30 detik

  bool isConnecting = false;
  late final MapController _mapController;
  final List<LatLng> _trackPoints = [];
  LatLng? _currentPoint;
  static const double _mapZoom = 16;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _configureRingtoneAudioContext();
    _getCurrentUserId();
    _initializeNotifications();
    _loadEsp32Status(); // Load status terakhir ESP32
    _loadSafeZoneRadius(); // Load safezone radius terakhir
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupAndConnect();
    });
  }

  void _configureRingtoneAudioContext() {
    _audioPlayer.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.notificationRingtone,
          audioFocus: AndroidAudioFocus.gain,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playAndRecord,
          options: const {AVAudioSessionOptions.defaultToSpeaker},
        ),
      ),
    );
  }

  // Initialize Local Notifications
  Future<void> _initializeNotifications() async {
    if (kIsWeb) return; // Notifications tidak support di web

    // Android initialization settings
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // iOS initialization settings (opsional, jika perlu iOS support)
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle ketika user tap notifikasi atau action button
        print(
          'Notification response: actionId=${response.actionId}, payload=${response.payload}',
        );

        // Jika user tap action "STOP_ALERT" atau tap notifikasi GPS alert
        if (response.actionId == 'STOP_ALERT') {
          print('User tapped STOP_ALERT button to stop alert');
          _stopAlertNotification();
        } else if (response.payload == 'gps_alert_channel') {
          print('User tapped GPS alert notification to stop alert');
          _stopAlertNotification();
        }
      },
    );

    // Request permissions untuk Android 13+
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();

    // Create notification channels
    await _createNotificationChannels();
  }

  // Create notification channels untuk Android
  Future<void> _createNotificationChannels() async {
    if (kIsWeb) return;

    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin != null) {
      // Hapus channel lama jika ada untuk memastikan settings baru digunakan
      // Ini penting karena channel settings tidak bisa diubah setelah dibuat
      try {
        await androidPlugin.deleteNotificationChannel('gps_alert_channel');
        print('✅ Deleted old gps_alert_channel to apply new settings');
        // Tunggu sebentar sebelum membuat channel baru
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        print('ℹ️ Channel not found or already deleted: $e');
      }

      // Buat channel baru untuk GPS Alert (dengan getar dan suara custom ringtone)
      // Pastikan sound menggunakan nama file tanpa extension
      const channel = AndroidNotificationChannel(
        'gps_alert_channel',
        'GPS Alerts',
        description:
            'Notifications for GPS geofencing alerts - with sound and vibration',
        importance: Importance.max, // MAX untuk heads-up notification
        enableVibration: true,
        playSound: true, // Aktifkan suara
        sound: RawResourceAndroidNotificationSound(
          'alert_ringtone',
        ), // Nama file tanpa .mp3
      );

      await androidPlugin.createNotificationChannel(channel);
      print('✅ Created gps_alert_channel with custom ringtone: alert_ringtone');
      print(
        '📁 Make sure file exists at: android/app/src/main/res/raw/alert_ringtone.mp3',
      );

      // Channel untuk Vibration Alert (hanya notifikasi biasa, tanpa getar/suara)
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'vibration_alert_channel',
          'Vibration Alerts',
          description:
              'Notifications for vibration sensor alerts - silent notification',
          importance: Importance
              .defaultImportance, // Default importance (tidak heads-up)
          enableVibration: false, // Tidak ada getar
          playSound: false, // Tidak ada suara
        ),
      );
    }
  }

  // Fungsi untuk show GPS Alert notification (dengan getar dan suara berulang seperti ringtone telepon)
  Future<void> _showGpsAlertNotification(
    String? distance,
    String? radius,
  ) async {
    if (kIsWeb) return;

    // Set flag bahwa alert sedang aktif
    _isAlertActive = true;

    // Vibration pattern yang lebih panjang dan berulang
    // Pattern: [0, 500, 200, 500, 200, 500, 200, 500, 200, 500, 200, 500]
    // Artinya: diam 0ms, lalu getar 500ms - diam 200ms - getar 500ms (berulang)
    // Sistem Android akan mengulang pattern ini sampai notifikasi di-clear
    final vibrationPattern = Int64List.fromList([
      0,
      500,
      200,
      500,
      200,
      500,
      200,
      500,
      200,
      500,
      200,
      500,
      200,
      500,
    ]);

    // Action button untuk stop alert notification
    const stopAction = AndroidNotificationAction(
      'STOP_ALERT',
      'Stop Alert',
      titleColor: Color(0xFFFF0000),
      cancelNotification: true, // Cancel notification saat action di-tap
    );

    // Gunakan custom ringtone MP3 file untuk suara notifikasi
    // Coba dengan berbagai cara untuk memastikan sound bekerja
    final androidDetails = AndroidNotificationDetails(
      'gps_alert_channel',
      'GPS Alerts',
      channelDescription:
          'Notifications for GPS geofencing alerts - with sound and vibration',
      importance: Importance
          .max, // MAX untuk heads-up notification (muncul di atas layar)
      priority: Priority
          .high, // High priority untuk muncul seperti notifikasi penting
      showWhen: true,
      enableVibration: true,
      vibrationPattern:
          vibrationPattern, // Pattern getar berulang (akan diulang oleh Android)
      playSound: true, // Aktifkan suara
      sound: const RawResourceAndroidNotificationSound(
        'alert_ringtone',
      ), // Custom ringtone MP3 file - tanpa extension
      // Alternatif: Jika RawResourceAndroidNotificationSound tidak bekerja, coba komentar baris di atas
      // dan uncomment baris di bawah ini untuk menggunakan default sound terlebih dahulu
      // sound: null, // Akan menggunakan sound dari channel settings
      enableLights: true, // Aktifkan LED jika ada
      ledColor: const Color(0xFFFF0000), // LED merah
      ledOnMs: 1000, // LED nyala 1 detik
      ledOffMs: 500, // LED mati 0.5 detik (blink cycle berulang)
      color: const Color(0xFFFF0000), // Warna notifikasi merah
      icon: '@mipmap/ic_launcher', // Icon aplikasi
      ongoing: false, // Bisa di-swipe
      autoCancel: false, // Jangan auto cancel agar bisa berulang
      ticker:
          '🚨 GPS Alert - Device has left the safe zone!', // Ticker text yang muncul di status bar
      actions: [stopAction], // Tambahkan action button untuk stop alert
      styleInformation: BigTextStyleInformation(
        'Device has left the safe zone!\nDistance: ${distance ?? "?"} m | Radius: ${radius ?? "?"} m',
        contentTitle: '🚨 GPS Alert - Zone Breach!',
      ),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default', // Default notification sound untuk iOS
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Tampilkan notifikasi pertama kali
    await _notifications.show(
      1,
      '🚨 GPS Alert - Zone Breach!',
      'Device has left the safe zone!\nDistance: ${distance ?? "?"} m | Radius: ${radius ?? "?"} m',
      notificationDetails,
      payload: 'gps_alert_channel',
    );

    // Mainkan ringtone menggunakan audio player
    _playRingtone();

    // Hentikan timer sebelumnya jika ada (untuk memastikan tidak ada duplikasi timer)
    _alertNotificationTimer?.cancel();
    _alertNotificationTimer = null;

    print(
      '🚨 Starting repeating alert notification - ringtone will play continuously every 3 seconds until stopped',
    );

    // Mulai timer untuk mengirim notifikasi berulang setiap 3 detik (seperti ringtone telepon)
    // Timer ini akan terus berjalan dan memainkan ringtone MP3 setiap 3 detik sampai dimatikan
    _alertNotificationTimer = Timer.periodic(const Duration(seconds: 3), (
      timer,
    ) {
      if (!_isAlertActive) {
        // Jika alert sudah tidak aktif, stop timer
        print('Alert inactive, stopping timer - ringtone will stop');
        timer.cancel();
        _alertNotificationTimer = null;
        return;
      }

      // Kirim notifikasi lagi (akan bergetar lagi)
      print('Repeating alert notification - playing ringtone MP3 again');
      _notifications.show(
        1,
        '🚨 GPS Alert - Zone Breach!',
        'Device telah keluar dari safe zone!\nJarak: ${distance ?? "?"} m | Radius: ${radius ?? "?"} m',
        notificationDetails,
        payload: 'gps_alert_channel',
      );

      // Mainkan ringtone lagi setiap 3 detik
      _playRingtone();
    });
  }

  // Fungsi untuk memainkan ringtone MP3 dari assets Flutter menggunakan stream nada dering
  Future<void> _playRingtone() async {
    if (kIsWeb) return;
    if (!_isAlertActive || _isRingtonePlaying) return;

    try {
      print(
        '🔊 Playing ringtone (ringtone stream): assets/sounds/alert_ringtone.mp3',
      );
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(
        AssetSource('sounds/alert_ringtone.mp3'),
        volume: 1.0,
      );
      _isRingtonePlaying = true;
      print('✅ Ringtone started using Android usageType=notificationRingtone');
    } catch (e) {
      _isRingtonePlaying = false;
      print('❌ Error playing ringtone from assets: $e');
      print(
        '💡 Make sure file exists di assets/sounds/alert_ringtone.mp3 dan terdaftar di pubspec.yaml',
      );

      // Fallback: coba dengan Android raw resource
      try {
        if (Platform.isAndroid) {
          print(
            '🔄 Trying Android raw resource as fallback dengan stream nada dering...',
          );
          const packageName = 'com.example.moteguard_app';
          final resourcePath =
              'android.resource://$packageName/raw/alert_ringtone';
          await _audioPlayer.setReleaseMode(ReleaseMode.loop);
          await _audioPlayer.play(UrlSource(resourcePath), volume: 1.0);
          _isRingtonePlaying = true;
          print('✅ Ringtone started from Android raw resource (fallback)');
        }
      } catch (e2) {
        _isRingtonePlaying = false;
        print('❌ All methods failed: $e2');
        print(
          '📁 Pastikan file ada di assets/sounds/alert_ringtone.mp3 atau android/app/src/main/res/raw/alert_ringtone.mp3',
        );
      }
    }
  }

  // Fungsi untuk stop ringtone
  Future<void> _stopRingtone() async {
    try {
      await _audioPlayer.stop();
      print('🔇 Ringtone stopped');
    } catch (e) {
      print('Error stopping ringtone: $e');
    } finally {
      _isRingtonePlaying = false;
    }
  }

  // Fungsi untuk stop alert notification (dipanggil saat kembali ke safe zone atau user click stop)
  void _stopAlertNotification() {
    if (_isAlertActive) {
      print('🛑 Stopping alert notification - ringtone will stop');
      _isAlertActive = false;
      _alertNotificationTimer?.cancel();
      _alertNotificationTimer = null;
      // Stop ringtone
      _stopRingtone();
      // Cancel notification yang sedang aktif
      _notifications.cancel(1);
      print('✅ Alert notification stopped - ringtone stopped');

      // Update UI jika widget masih mounted
      if (mounted) {
        setState(() {});
      }
    }
  }

  // Fungsi untuk show Vibration Alert notification (hanya notifikasi biasa, tanpa getar/suara)
  Future<void> _showVibrationAlertNotification(String? location) async {
    if (kIsWeb) return;

    const androidDetails = AndroidNotificationDetails(
      'vibration_alert_channel',
      'Vibration Alerts',
      channelDescription:
          'Notifications for vibration sensor alerts - silent notification',
      importance:
          Importance.defaultImportance, // Default importance (tidak heads-up)
      priority: Priority.defaultPriority, // Default priority (tidak urgent)
      showWhen: true,
      enableVibration: false, // Tidak ada getar
      playSound: false, // Tidak ada suara
      icon: '@mipmap/ic_launcher',
      autoCancel: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: false, // Tidak ada suara untuk iOS juga
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      2,
      '⚠️ Vibration Detected!',
      'Vibration detected on the motorcycle!\nLocation: ${location ?? "GPS not available"}',
      notificationDetails,
      payload: 'vibration_alert_channel',
    );
  }

  Future<void> _getCurrentUserId() async {
    _currentUserId = await AuthService.getUserId();
  }

  // Load status terakhir ESP32 dari SharedPreferences
  Future<void> _loadEsp32Status() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastStatus = prefs.getString(
        'esp32_last_status',
      ); // 'ON' atau 'OFF' atau null

      if (lastStatus != null) {
        // Ada status terakhir, gunakan itu
        if (mounted) {
          setState(() {
            if (lastStatus == 'ON') {
              geofenceStatus = 'ACTIVE';
            } else {
              geofenceStatus = 'SLEEP';
            }
          });
        }
        print('Loaded ESP32 last status: $lastStatus');
      } else {
        // Pertama kali login, default ke SLEEP (akan kirim OFF)
        if (mounted) {
          setState(() {
            geofenceStatus = 'SLEEP';
          });
        }
        print('First time login, default to SLEEP (OFF)');
      }
    } catch (e) {
      print('Error loading ESP32 status: $e');
      // Default ke SLEEP jika error
      if (mounted) {
        setState(() {
          geofenceStatus = 'SLEEP';
        });
      }
    }
  }

  // Save status ESP32 ke SharedPreferences
  Future<void> _saveEsp32Status(String status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('esp32_last_status', status); // 'ON' atau 'OFF'
      print('Saved ESP32 status: $status');
    } catch (e) {
      print('Error saving ESP32 status: $e');
    }
  }

  // Load safezone radius dari SharedPreferences
  Future<void> _loadSafeZoneRadius() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedRadius = prefs.getDouble(
        'safezone_radius',
      ); // double atau null

      if (savedRadius != null && savedRadius >= 5.0 && savedRadius <= 80.0) {
        _currentSafeZoneRadius = savedRadius;
        if (mounted) {
          setState(() {
            safeZoneRadius = savedRadius.toStringAsFixed(1);
          });
        }
        print('Loaded safezone radius: ${_currentSafeZoneRadius} m');
      } else {
        // Default 15.0 meter
        _currentSafeZoneRadius = 15.0;
        await _saveSafeZoneRadius(15.0);
        if (mounted) {
          setState(() {
            safeZoneRadius = '15.0';
          });
        }
        print('First time, default safezone radius: 15.0 m');
      }
    } catch (e) {
      print('Error loading safezone radius: $e');
      _currentSafeZoneRadius = 15.0;
      if (mounted) {
        setState(() {
          safeZoneRadius = '15.0';
        });
      }
    }
  }

  // Save safezone radius ke SharedPreferences
  Future<void> _saveSafeZoneRadius(double radius) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('safezone_radius', radius);
      _currentSafeZoneRadius = radius;
      print('Saved safezone radius: $radius m');
    } catch (e) {
      print('Error saving safezone radius: $e');
    }
  }

  // Kirim safezone radius ke ESP32
  void _sendSafeZoneRadius(double radius) {
    if (client == null ||
        client!.connectionStatus?.state != MqttConnectionState.connected) {
      print('Cannot send safezone radius: client not connected');
      return;
    }
    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(radius.toStringAsFixed(1)); // Format: "15.0"
      client!.publishMessage(
        "gps/safezone",
        MqttQos.atLeastOnce,
        builder.payload!,
      );
      print('Safezone radius sent to ESP32: $radius m');
    } catch (e) {
      print('Failed to send safezone radius: $e');
    }
  }

  void _resendAuthorizationHandshake() {
    _sendLastStatusToEsp32();
    _sendSafeZoneRadius(_currentSafeZoneRadius);
  }

  void _handleEspStatusMessage(List<String> parts) {
    if (parts.length < 2) return;
    final statusValue = parts[1];
    final sessionId = parts.length >= 3 ? parts[2] : null;
    switch (statusValue) {
      case 'WAITING_AUTH':
        _handleEspWaitingAuth(sessionId);
        break;
      case 'AUTHORIZED':
        _handleEspAuthorized(sessionId);
        break;
      default:
        break;
    }
  }

  void _handleEspWaitingAuth(String? sessionId) {
    final didChange = !_espAwaitingAuthorization;
    _espAwaitingAuthorization = true;
    _maybeReplayAuthorization(sessionId);
    if (didChange && mounted) {
      setState(() {});
    }
  }

  void _handleEspAuthorized(String? sessionId) {
    if (!_espAwaitingAuthorization) return;
    _espAwaitingAuthorization = false;
    if (mounted) {
      setState(() {});
    }
  }

  void _maybeReplayAuthorization(String? sessionId) {
    final normalizedSession = sessionId ?? 'unknown';
    final now = DateTime.now();
    if (_lastHandledAuthSession == normalizedSession) {
      if (normalizedSession == 'unknown') {
        if (_lastAuthReplayAt != null &&
            now.difference(_lastAuthReplayAt!).inSeconds < 4) {
          return;
        }
      } else {
        return;
      }
    }
    _lastHandledAuthSession = normalizedSession;
    _lastAuthReplayAt = now;
    _sendLastStatusToEsp32();
    _sendSafeZoneRadius(_currentSafeZoneRadius);
  }

  void _markEspActiveFromData() {
    if (!_espAwaitingAuthorization) return;
    _espAwaitingAuthorization = false;
    if (mounted) {
      setState(() {});
    }
  }

  // Dialog untuk mengatur Safe Zone Radius
  void _showSafeZoneDialog(BuildContext context) {
    final TextEditingController radiusController = TextEditingController(
      text: _currentSafeZoneRadius.toStringAsFixed(1),
    );

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        title: Row(
          children: const [
            Icon(Icons.location_on, color: AppColors.primary, size: 28),
            SizedBox(width: 10),
            Text(
              'Safe Zone Settings',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Set safe zone radius (meters)',
                style: TextStyle(fontSize: 14, color: AppColors.textDark),
              ),
              SizedBox(height: 12),
              TextField(
                controller: radiusController,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Radius (meters)',
                  hintText: 'Example: 15.0',
                  prefixIcon: Icon(
                    Icons.radio_button_unchecked,
                    color: AppColors.secondary,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.primary,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: AppColors.softBlue.withOpacity(0.3),
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Radius provides a distance tolerance of 6.59 meters',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textDark.withOpacity(0.7),
                  fontStyle: FontStyle.italic,
                ),
              ),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.softBlue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.secondary.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppColors.secondary,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Range: 5 - 80 meters\nDefault: 15.0 meters',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 4),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textDark),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final input = radiusController.text.trim();
              final newRadius = double.tryParse(input);

              if (newRadius == null || newRadius < 5.0 || newRadius > 80.0) {
                // Show error
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'Radius must be between 5 - 80 meters!',
                      ),
                      backgroundColor: AppColors.danger,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }
                return;
              }

              // Simpan dan kirim ke ESP32
              await _saveSafeZoneRadius(newRadius);
              _sendSafeZoneRadius(newRadius);

              if (mounted) {
                setState(() {
                  safeZoneRadius = newRadius.toStringAsFixed(1);
                });
              }

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Safe Zone Radius: ${newRadius.toStringAsFixed(1)}m',
                    ),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _onGpsUpdate(String latStr, String lngStr) {
    final double? lat = double.tryParse(latStr);
    final double? lng = double.tryParse(lngStr);
    if (lat == null || lng == null) {
      print('Invalid GPS coordinates: lat=$latStr, lng=$lngStr');
      return;
    }
    final point = LatLng(lat, lng);
    print('GPS Update: $lat, $lng');

    if (mounted) {
      setState(() {
        _currentPoint = point;
        _trackPoints.add(point);
        if (_trackPoints.length > 500) {
          _trackPoints.removeAt(0);
        }
      });

      // Smooth animation instead of instant move
      try {
        _mapController.move(point, _mapZoom);
        print('Map moved to: $point');
      } catch (e) {
        print('Map move error: $e');
      }
    }
  }

  void _showFullscreenMap() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.white,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Live GPS Tracking'),
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          body: _currentPoint != null
              ? FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentPoint!,
                    initialZoom: _mapZoom,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'moteguard_app',
                    ),
                    if (_trackPoints.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _trackPoints,
                            strokeWidth: 4,
                            color: Colors.blue,
                          ),
                        ],
                      ),
                    if (_currentPoint != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _currentPoint!,
                            width: 50,
                            height: 50,
                            child: const Icon(
                              Icons.motorcycle,
                              color: Colors.red,
                              size: 35,
                            ),
                          ),
                        ],
                      ),
                    // Center point marker in fullscreen
                    if (centerLat != null && centerLng != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(
                              double.tryParse(centerLat!) ?? 0,
                              double.tryParse(centerLng!) ?? 0,
                            ),
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.place,
                              color: Colors.blue,
                              size: 25,
                            ),
                          ),
                        ],
                      ),
                  ],
                )
              : const Center(
                  child: Text(
                    'Waiting for GPS data...',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
        ),
      ),
    );
  }

  void _setupAndConnect() async {
    setState(() {
      isConnecting = true;
      status = "Connecting...";
    });

    _setupClient();
    await _connect();

    setState(() {
      isConnecting = false;
    });
  }

  void _setupClient() {
    client = createMqttClient();
    client!.onConnected = _onConnected;
    client!.onDisconnected = _onDisconnected;
    client!.onSubscribed = _onSubscribed;
    client!.logging(on: false);
    client!.keepAlivePeriod = 60;
    client!.autoReconnect = true;
  }

  Future<void> _connect() async {
    if (client == null) return;

    final connMess = MqttConnectMessage()
        .withClientIdentifier(client!.clientIdentifier)
        .withWillTopic('willtopic')
        .withWillMessage('Client disconnected unexpectedly')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    client!.connectionMessage = connMess;

    try {
      print('Attempting to connect...');
      await client!.connect();
    } catch (e) {
      print('Connection error: $e');
      if (mounted) {
        setState(() {
          status = "Connection failed: $e";
        });
      }
      client!.disconnect();
      return;
    }

    if (client!.connectionStatus?.state == MqttConnectionState.connected) {
      print('Connected successfully');
      if (mounted) {
        setState(() {
          status = "Connected";
        });
      }

      // Subscribe topics
      client!.subscribe("gps/data", MqttQos.atLeastOnce);
      client!.subscribe("gps/alert", MqttQos.atLeastOnce);
      client!.subscribe("gps/vibration", MqttQos.atLeastOnce);

      // Listen untuk pesan masuk
      _mqttSubscription = client!.updates?.listen((
        List<MqttReceivedMessage<MqttMessage?>>? c,
      ) {
        if (c == null || c.isEmpty) return;
        if (!mounted) return; // Pastikan widget masih mounted

        final recMess = c[0].payload as MqttPublishMessage;
        final pt = MqttPublishPayload.bytesToStringAsString(
          recMess.payload.message,
        );
        final topic = c[0].topic;

        print('Received on $topic: $pt');

        if (mounted) {
          setState(() {
            // Only add message to list if it's from a known topic or successfully parsed
            // For gps/data topic, only add if message format is recognized
            if (topic == "gps/data") {
              // Check if message starts with known message types
              final knownTypes = ['STATUS', 'CENTER', 'NORMAL', 'OUTSIDE', 'ALERT', 'SAFE', 'SLEEP', 'ACTIVE', 'RESET'];
              final messageType = pt.split(',').isNotEmpty ? pt.split(',')[0] : '';
              if (knownTypes.contains(messageType)) {
            messages.insert(0, "[$topic] $pt");
              } else {
                // Log unknown messages but don't show in UI
                print('Unknown message format from gps/data: $pt');
              }
            } else {
              // For other topics (gps/alert, gps/vibration), always add
              messages.insert(0, "[$topic] $pt");
            }
            _parseMessage(pt, topic);
          });
        }
      });

      // Kirim status terakhir ESP32 dan safezone radius setelah MQTT connected
      // Delay sedikit untuk memastikan subscribe selesai
      Future.delayed(const Duration(milliseconds: 500), () {
        _sendLastStatusToEsp32();
        _sendSafeZoneRadius(
          _currentSafeZoneRadius,
        ); // Kirim safezone radius ke ESP32
        // Initialize relay to ON state when app connects
        _relayState = true;
        _sendControl('RELAY_ON');
      });
    } else {
      print('Connection failed - status: ${client!.connectionStatus?.state}');
      if (mounted) {
        setState(() {
          status = "Connection failed";
        });
      }
      client!.disconnect();
    }
  }

  // Fungsi untuk save GPS data ke Firestore
  Future<void> _saveGpsDataToFirestore({
    required String status,
    required String? lat,
    required String? lng,
    String? alt,
    String? speed,
    String? satellites,
    String? distance,
    String? safeZoneRadius,
    String? centerDocId,
    bool forceSave = false,
  }) async {
    try {
      if (_currentUserId == null) {
        _currentUserId = await AuthService.getUserId();
        if (_currentUserId == null) return; // User belum login
      }

      // Check interval - jangan save terlalu sering
      final now = DateTime.now();
      if (!forceSave &&
          _lastFirestoreSave != null &&
          now.difference(_lastFirestoreSave!).inMilliseconds <
              _firestoreSaveInterval) {
        return; // Skip jika baru save < 30 detik yang lalu
      }

      if (lat == null || lng == null) return;

      final gpsData = {
        'userId': _currentUserId,
        'status': status,
        'latitude': double.tryParse(lat) ?? 0.0,
        'longitude': double.tryParse(lng) ?? 0.0,
        'altitude': alt != null ? double.tryParse(alt) : null,
        'speed': speed != null ? double.tryParse(speed) : null,
        'satellites': satellites != null ? int.tryParse(satellites) : null,
        'distance': distance != null ? double.tryParse(distance) : null,
        'safeZoneRadius': safeZoneRadius != null
            ? double.tryParse(safeZoneRadius)
            : null,
        'timestamp': FieldValue.serverTimestamp(),
        'deviceId': 'ESP32-GPS', // Identifier untuk device
        'centerDocId': centerDocId ?? _currentCenterDocId,
      };

      // Save ke Firestore collection 'gps_data'
      await _firestore.collection('gps_data').add(gpsData);

      _lastFirestoreSave = now;
      print('GPS data saved to Firestore: $status');
    } catch (e) {
      print('Error saving GPS data to Firestore: $e');
      // Jangan throw error, biarkan MQTT tetap jalan
    }
  }

  // Fungsi untuk menyimpan center point ke Firestore
  Future<String?> _saveCenterToFirestore({
    required String lat,
    required String lng,
    String? safeZoneRadius,
    String? alt,
    String? speed,
    String? satellites,
  }) async {
    try {
      if (_currentUserId == null) {
        _currentUserId = await AuthService.getUserId();
        if (_currentUserId == null) return null;
      }

      final centerData = {
        'userId': _currentUserId,
        'latitude': double.tryParse(lat) ?? 0.0,
        'longitude': double.tryParse(lng) ?? 0.0,
        'safeZoneRadius': safeZoneRadius != null
            ? double.tryParse(safeZoneRadius)
            : null,
        'altitude': alt != null ? double.tryParse(alt) : null,
        'speed': speed != null ? double.tryParse(speed) : null,
        'satellites': satellites != null ? int.tryParse(satellites) : null,
        'timestamp': FieldValue.serverTimestamp(),
        'deviceId': 'ESP32-GPS',
      };

      final docRef = await _firestore
          .collection('gps_data_center')
          .add(centerData);
      _currentCenterDocId = docRef.id;
      print('Center saved to Firestore: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('Error saving center to Firestore: $e');
      return null;
    }
  }

  // Fungsi untuk save vibration data ke Firestore
  Future<void> _saveVibrationToFirestore({
    required String? lat,
    required String? lng,
  }) async {
    try {
      if (_currentUserId == null) {
        _currentUserId = await AuthService.getUserId();
        if (_currentUserId == null) return;
      }

      final vibrationData = {
        'userId': _currentUserId,
        'latitude': lat != null ? double.tryParse(lat) : null,
        'longitude': lng != null ? double.tryParse(lng) : null,
        'timestamp': FieldValue.serverTimestamp(),
        'deviceId': 'ESP32-GPS',
      };

      await _firestore.collection('vibration_data').add(vibrationData);
      print('Vibration data saved to Firestore');
    } catch (e) {
      print('Error saving vibration data to Firestore: $e');
    }
  }

  void _parseMessage(String message, String topic) {
    // Handle vibration topic separately
    if (topic == "gps/vibration") {
      _parseVibrationMessage(message);
      return;
    }

    final parts = message.split(',');
    if (parts.isEmpty) return;

    final messageType = parts[0];
    print('Parsing message: $messageType with ${parts.length} parts');

    switch (messageType) {
      case 'STATUS':
        _handleEspStatusMessage(parts);
        break;
      case 'CENTER':
        _markEspActiveFromData();
        // CENTER,lat,lng,radius (ESP32 format - 4 parts)
        // CENTER,lat,lng,alt,spd,sats,radius (Expected format - 7 parts)
        if (parts.length >= 3) {
          centerLat = parts[1];
          centerLng = parts[2];
          currentLat = parts[1];
          currentLng = parts[2];

          String? centerAltValue = "0";
          String? centerSpeedValue = "0";
          String? centerSatValue = "0";
          String? centerRadiusValue;

          // Handle both formats
          if (parts.length >= 7) {
            // Full format with all fields
            currentAlt = parts[3];
            currentSpd = parts[4];
            currentSats = parts[5];
            safeZoneRadius = parts[6];
            centerAltValue = parts[3];
            centerSpeedValue = parts[4];
            centerSatValue = parts[5];
            centerRadiusValue = parts[6];
          } else if (parts.length >= 4) {
            // Short format: CENTER,lat,lng,radius
            currentAlt = "0";
            currentSpd = "0";
            currentSats = "0";
            safeZoneRadius = parts[3];
            centerRadiusValue = parts[3];
          }

          distance = "0.00";
          geofenceStatus = "CENTER_SET";
          _onGpsUpdate(parts[1], parts[2]);

          // Simpan center ke Firestore (koleksi gps_data_center)
          _saveCenterToFirestore(
            lat: parts[1],
            lng: parts[2],
            safeZoneRadius: centerRadiusValue,
            alt: centerAltValue,
            speed: centerSpeedValue,
            satellites: centerSatValue,
          );
        }
        break;

      case 'NORMAL':
        _markEspActiveFromData();
        // NORMAL,lat,lng,distance,speed (ESP32 format - 5 parts)
        // NORMAL,lat,lng,alt,spd,sats,distance (Expected format - 7 parts)
        if (parts.length >= 3) {
          currentLat = parts[1];
          currentLng = parts[2];

          if (parts.length >= 7) {
            // Full format
            currentAlt = parts[3];
            currentSpd = parts[4];
            currentSats = parts[5];
            distance = parts[6];
          } else if (parts.length >= 5) {
            // Short format: NORMAL,lat,lng,distance,speed
            currentAlt = "0";
            distance = parts[3];
            currentSpd = parts[4];
            currentSats = "0";
          }

          geofenceStatus = "SAFE";
          _stopAlertNotification(); // Stop alert notification yang berulang
          _onGpsUpdate(parts[1], parts[2]);

          // Save ke Firestore
          _saveGpsDataToFirestore(
            status: 'NORMAL',
            lat: parts[1],
            lng: parts[2],
            alt: parts.length >= 7 ? parts[3] : "0",
            speed: parts.length >= 7
                ? parts[4]
                : (parts.length >= 5 ? parts[4] : "0"),
            satellites: parts.length >= 7 ? parts[5] : "0",
            distance: parts.length >= 7
                ? parts[6]
                : (parts.length >= 5 ? parts[3] : "0"),
          );
        }
        break;

      case 'OUTSIDE':
        _markEspActiveFromData();
        // OUTSIDE,lat,lng,distance,speed (ESP32 format - 5 parts)
        // OUTSIDE,lat,lng,alt,spd,sats,distance (Expected format - 7 parts)
        if (parts.length >= 3) {
          currentLat = parts[1];
          currentLng = parts[2];

          if (parts.length >= 7) {
            // Full format
            currentAlt = parts[3];
            currentSpd = parts[4];
            currentSats = parts[5];
            distance = parts[6];
          } else if (parts.length >= 5) {
            // Short format: OUTSIDE,lat,lng,distance,speed
            currentAlt = "0";
            distance = parts[3];
            currentSpd = parts[4];
            currentSats = "0";
          }

          geofenceStatus = "OUTSIDE";
          _onGpsUpdate(parts[1], parts[2]);

          // Save ke Firestore
          _saveGpsDataToFirestore(
            status: 'OUTSIDE',
            lat: parts[1],
            lng: parts[2],
            alt: parts.length >= 7 ? parts[3] : "0",
            speed: parts.length >= 7
                ? parts[4]
                : (parts.length >= 5 ? parts[4] : "0"),
            satellites: parts.length >= 7 ? parts[5] : "0",
            distance: parts.length >= 7
                ? parts[6]
                : (parts.length >= 5 ? parts[3] : "0"),
          );
        }
        break;

      case 'ALERT':
        _markEspActiveFromData();
        // ALERT message format: ALERT,lat,lng,alt,spd,sats,distance,status
        // Or short: ALERT,lat,lng,distance,speed,...
        if (parts.length >= 3) {
          currentLat = parts[1];
          currentLng = parts[2];

          if (parts.length >= 8) {
            // Full format: ALERT,lat,lng,alt,spd,sats,distance,status
            currentAlt = parts[3];
            currentSpd = parts[4];
            currentSats = parts[5];
            distance = parts[6];
          } else if (parts.length >= 7) {
            // Format: ALERT,lat,lng,alt,spd,sats,distance
            currentAlt = parts[3];
            currentSpd = parts[4];
            currentSats = parts[5];
            distance = parts[6];
          } else if (parts.length >= 4) {
            // Short format: ALERT,lat,lng,distance,speed,...
            distance = parts[3];
            currentSpd = parts.length >= 5 ? parts[4] : "0";
            currentAlt = "0";
            currentSats = "0";
          }

          geofenceStatus = "ALERT";
          _onGpsUpdate(parts[1], parts[2]);
          _showAlertDialog();

          // Show notification di HP
          _showGpsAlertNotification(
            parts.length >= 8
                ? parts[6]
                : (parts.length >= 7
                      ? parts[6]
                      : (parts.length >= 4 ? parts[3] : null)),
            safeZoneRadius,
          );

          // Save ke Firestore
          _saveGpsDataToFirestore(
            status: 'ALERT',
            lat: parts[1],
            lng: parts[2],
            alt: parts.length >= 8
                ? parts[3]
                : (parts.length >= 7 ? parts[3] : "0"),
            speed: parts.length >= 8
                ? parts[4]
                : (parts.length >= 7
                      ? parts[4]
                      : (parts.length >= 5 ? parts[4] : "0")),
            satellites: parts.length >= 8
                ? parts[5]
                : (parts.length >= 7 ? parts[5] : "0"),
            distance: parts.length >= 8
                ? parts[6]
                : (parts.length >= 7
                      ? parts[6]
                      : (parts.length >= 4 ? parts[3] : "0")),
          );
        }
        break;

      case 'SAFE':
        // SAFE,lat,lng,distance,speed,status (ESP32 format - varies)
        if (parts.length >= 3) {
          currentLat = parts[1];
          currentLng = parts[2];

          if (parts.length >= 7) {
            // Full format
            currentAlt = parts[3];
            currentSpd = parts[4];
            currentSats = parts[5];
            distance = parts[6];
          } else if (parts.length >= 4) {
            // Short format
            distance = parts[3];
            currentSpd = parts.length >= 5 ? parts[4] : "0";
            currentAlt = "0";
            currentSats = "0";
          }

          geofenceStatus = "RETURNED_SAFE";
          _stopAlertNotification(); // Stop alert notification yang berulang
          _onGpsUpdate(parts[1], parts[2]);

          // Save ke Firestore
          _saveGpsDataToFirestore(
            status: 'SAFE',
            lat: parts[1],
            lng: parts[2],
            alt: parts.length >= 7 ? parts[3] : "0",
            speed: parts.length >= 7
                ? parts[4]
                : (parts.length >= 5 ? parts[4] : "0"),
            satellites: parts.length >= 7 ? parts[5] : "0",
            distance: parts.length >= 7
                ? parts[6]
                : (parts.length >= 4 ? parts[3] : "0"),
          );
        }
        break;

      case 'SLEEP':
      case 'ACTIVE':
      case 'RESET':
        geofenceStatus = messageType;
        // Clear GPS data when sleeping/resetting
        if (messageType == 'SLEEP' || messageType == 'RESET') {
          currentLat = null;
          currentLng = null;
          centerLat = null;
          centerLng = null;
        }
        break;
      default:
        // Handle unknown message types - log but don't show in UI
        print('Unknown message type: $messageType from topic: $topic');
        // Don't add unknown messages to the messages list to avoid clutter
        return;
    }
  }

  void _parseVibrationMessage(String message) {
    final parts = message.split(',');
    if (parts.isEmpty) return;

    final messageType = parts[0];
    print('Parsing vibration: $messageType with ${parts.length} parts');

    if (messageType == "VIBRATION_DETECTED") {
      String? vibrationLat;
      String? vibrationLng;

      if (parts.length >= 3) {
        vibrationLat = parts[1];
        vibrationLng = parts[2];
        vibrationLocation = "${parts[1]}, ${parts[2]}";
      } else {
        vibrationLocation = "GPS belum tersedia";
      }

      if (mounted) {
        setState(() {
          vibrationCount++;
          lastVibrationTime = DateTime.now().toString().substring(
            11,
            19,
          ); // HH:MM:SS
        });
      }

      // Save vibration ke Firestore
      if (vibrationLat != null && vibrationLng != null) {
        _saveVibrationToFirestore(lat: vibrationLat, lng: vibrationLng);
      }

      // Show vibration alert dialog
      _showVibrationAlert();
    }
  }

  void _showAlertDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red, size: 32),
            SizedBox(width: 8),
            Text('Geofencing Alert!'),
          ],
        ),
        content: Text(
          'Device has moved outside the safe zone!\n\n'
          'Distance from center: ${distance ?? "?"} m\n'
          'Safe zone radius: ${safeZoneRadius ?? "?"} m',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showVibrationAlert() {
    if (!mounted) return;

    // Show notification di HP
    _showVibrationAlertNotification(vibrationLocation);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.vibration, color: Colors.orange, size: 32),
            SizedBox(width: 8),
            Text('Vibration Detected!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '⚠️ Vibration detected on the motorcycle!',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (vibrationLocation != null) ...[
              Text('Location: $vibrationLocation'),
              const SizedBox(height: 8),
            ],
            Text('Time: ${lastVibrationTime ?? "?"}'),
            const SizedBox(height: 8),
            Text('Total vibrations: $vibrationCount'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _onDisconnected() {
    print('Disconnected');
    if (mounted) {
      setState(() {
        status = "Disconnected";
      });
    }
  }

  void _onConnected() {
    print('Connected');
    if (mounted) {
      setState(() {
        status = "Connected";
      });
    }
  }

  void _onSubscribed(String topic) {
    print('Subscribed to $topic');
  }

  // Kirim status terakhir ke ESP32 setelah MQTT connected
  Future<void> _sendLastStatusToEsp32() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastStatus = prefs.getString(
        'esp32_last_status',
      ); // 'ON' atau 'OFF' atau null

      String commandToSend;
      if (lastStatus != null) {
        // Ada status terakhir, kirim itu
        commandToSend = lastStatus;
        print('Sending last ESP32 status: $commandToSend');
      } else {
        // Pertama kali login, kirim OFF (default)
        commandToSend = 'OFF';
        await _saveEsp32Status('OFF'); // Simpan OFF sebagai status awal
        print('First time login, sending default: $commandToSend');
      }

      // Kirim command ke ESP32
      _sendControl(commandToSend);

      // Update geofenceStatus sesuai command yang dikirim
      if (mounted) {
        setState(() {
          if (commandToSend == 'ON') {
            geofenceStatus = 'ACTIVE';
          } else {
            geofenceStatus = 'SLEEP';
          }
        });
      }
    } catch (e) {
      print('Error sending last status to ESP32: $e');
      // Default kirim OFF jika error
      _sendControl('OFF');
      if (mounted) {
        setState(() {
          geofenceStatus = 'SLEEP';
        });
      }
    }
  }

  void _sendControl(String command) {
    if (client == null ||
        client!.connectionStatus?.state != MqttConnectionState.connected) {
      print('Cannot send control: client not connected');
      return;
    }
    final builder = MqttClientPayloadBuilder();
    builder.addString(command);
    try {
      client!.publishMessage(
        "gps/control",
        MqttQos.atLeastOnce,
        builder.payload!,
      );
      print('Control message sent: $command');
    } catch (e) {
      print('Failed to send control message: $e');
    }
  }

  void _reconnect() {
    client?.disconnect();
    messages.clear();
    centerLat = null;
    centerLng = null;
    currentLat = null;
    currentLng = null;
    geofenceStatus = "UNKNOWN";
    _setupAndConnect();
  }

  Color _getStatusColor() {
    if (_espAwaitingAuthorization) {
      return AppColors.warning;
    }
    switch (geofenceStatus) {
      case 'CENTER_SET':
      case 'SAFE':
      case 'RETURNED_SAFE':
        return AppColors.success;
      case 'OUTSIDE':
      case 'ALERT':
        return AppColors.danger;
      case 'SLEEP':
        return Colors.grey.shade600;
      case 'ACTIVE':
        return AppColors.secondary;
      default:
        return AppColors.accent;
    }
  }

  String _getStatusText() {
    if (_espAwaitingAuthorization) {
      return '🔐 Menunggu perintah awal dari aplikasi';
    }
    switch (geofenceStatus) {
      case 'CENTER_SET':
        return '📍 Center Point Set';
      case 'SAFE':
        return '✅ Inside Safe Zone';
      case 'OUTSIDE':
        return '⚠️ Outside Safe Zone';
      case 'ALERT':
        return '🚨 ALERT: Zone Breach!';
      case 'RETURNED_SAFE':
        return '✅ Returned to Safe Zone';
      case 'SLEEP':
        return '😴 Sleep Mode';
      case 'ACTIVE':
        return '🟢 Active';
      default:
        return '❓ Unknown';
    }
  }

  Widget _buildSectionContainer({
    required Widget child,
    List<Color>? gradientColors,
    EdgeInsets padding = const EdgeInsets.all(20),
    EdgeInsets margin = const EdgeInsets.only(bottom: 18),
  }) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        gradient: gradientColors != null
            ? LinearGradient(colors: gradientColors)
            : null,
        color: gradientColors == null ? Colors.white : null,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildMetricTile({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.softBlue,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textDark.withOpacity(0.6),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }

  // Fungsi untuk membersihkan MQTT connection
  Future<void> _cleanupMqtt() async {
    try {
      // Stop alert notification timer
      _stopAlertNotification();

      // Cancel subscription terlebih dahulu
      await _mqttSubscription?.cancel();
      _mqttSubscription = null;

      // Disconnect client
      client?.disconnect();
      client = null;
    } catch (e) {
      print('Error cleaning up MQTT: $e');
    }
  }

  @override
  void dispose() {
    _stopAlertNotification(); // Stop alert notification timer
    _cleanupMqtt();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "GPS Geofencing Tracker",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.primaryDark],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Logout',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Apakah anda yakin ingin logout?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Batal'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Logout'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                // Cleanup MQTT connection sebelum logout
                await _cleanupMqtt();

                // Logout
                await AuthService.logout();

                // Navigate ke login page
                if (mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                    (route) => false, // Remove semua route sebelumnya
                  );
                }
              }
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.softBlue, Colors.white],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionContainer(
                gradientColors: const [
                  AppColors.primary,
                  AppColors.primaryDark,
                ],
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          client?.connectionStatus?.state ==
                                  MqttConnectionState.connected
                              ? Icons.wifi
                              : Icons.wifi_off,
                          color: Colors.white,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "MQTT: $status",
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),

              _buildSectionContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: StatefulBuilder(
                            builder: (context, setLocal) {
                              final turningOn =
                                  geofenceStatus == 'SLEEP' ||
                                  geofenceStatus == 'UNKNOWN';
                              return ElevatedButton.icon(
                                onPressed: isConnecting
                                    ? null
                                    : () async {
                                        final command = turningOn
                                            ? 'ON'
                                            : 'OFF';
                                        _sendControl(command);

                                        // Simpan status ke SharedPreferences
                                        await _saveEsp32Status(command);

                                        if (mounted) {
                                          setState(() {
                                            geofenceStatus = turningOn
                                                ? 'ACTIVE'
                                                : 'SLEEP';
                                          });
                                        }
                                        setLocal(() {});
                                      },
                                icon: Icon(
                                  turningOn
                                      ? Icons.power
                                      : Icons.power_settings_new,
                                ),
                                label: Text(
                                  turningOn
                                      ? 'Turn ON (wake ESP32)'
                                      : 'Turn OFF (sleep ESP32)',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: turningOn
                                      ? AppColors.success
                                      : AppColors.danger,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: isConnecting ? null : _reconnect,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 18,
                            ),
                          ),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Tombol Stop Alert - muncul hanya ketika alert aktif
                    if (_isAlertActive) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.danger, width: 2),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: AppColors.danger,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text(
                                    '🚨 Alert Aktif!',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: AppColors.danger,
                                    ),
                                  ),
                                  Text(
                                    'Ringtone berulang setiap 3 detik',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          _stopAlertNotification();
                          if (mounted) {
                            setState(() {});
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                '✅ Alert notification telah dimatikan',
                              ),
                              backgroundColor: AppColors.success,
                              behavior: SnackBarBehavior.floating,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.danger,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 4,
                        ),
                        icon: const Icon(Icons.stop_circle, size: 24),
                        label: const Text(
                          '🛑 Matikan Alert & Ringtone',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isConnecting
                                ? null
                                : () => _sendControl('RESET_CENTER'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(
                                color: AppColors.primary,
                                width: 1.4,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.restart_alt),
                            label: const Text('Reset Center'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isConnecting
                                ? null
                                : () => _showSafeZoneDialog(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.secondary,
                              side: const BorderSide(
                                color: AppColors.secondary,
                                width: 1.4,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.settings),
                            label: const Text('Safe Zone'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Manual Relay Control Button
                    _buildSectionContainer(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.power_settings_new,
                                  color: AppColors.primary,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Kontrol Relay Manual',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: isConnecting
                                      ? null
                                      : () {
                                          setState(() {
                                            _relayState = !_relayState;
                                          });
                                          _sendControl(
                                            _relayState ? 'RELAY_ON' : 'RELAY_OFF',
                                          );
                                        },
                                  icon: Icon(
                                    _relayState
                                        ? Icons.lock
                                        : Icons.lock_open,
                                    size: 20,
                                  ),
                                  label: Text(
                                    _relayState
                                        ? 'Relay ON (Motor Dikunci)'
                                        : 'Relay OFF (Motor Normal)',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _relayState
                                        ? AppColors.danger
                                        : AppColors.success,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: (_relayState
                                      ? AppColors.danger
                                      : AppColors.success)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _relayState
                                      ? Icons.info_outline
                                      : Icons.check_circle_outline,
                                  color: _relayState
                                      ? AppColors.danger
                                      : AppColors.success,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _relayState
                                        ? 'Relay aktif - Motor dalam keadaan terkunci'
                                        : 'Relay nonaktif - Motor dalam keadaan normal',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textDark.withOpacity(0.7),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_espAwaitingAuthorization) ...[
                      const SizedBox(height: 16),
                      _buildSectionContainer(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.lock_clock,
                                color: AppColors.warning,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Menunggu perintah aplikasi',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: AppColors.warning,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Kirim tombol ON/OFF (atau tekan "Kirim ulang") agar ESP32 mulai bekerja dan siap offline.',
                                    style: TextStyle(
                                      color: AppColors.textDark.withOpacity(
                                        0.7,
                                      ),
                                      fontSize: 13,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            TextButton.icon(
                              onPressed: isConnecting
                                  ? null
                                  : _resendAuthorizationHandshake,
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.warning,
                              ),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Kirim ulang'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              _buildSectionContainer(
                gradientColors: [
                  _getStatusColor().withOpacity(0.18),
                  Colors.white,
                ],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _getStatusColor().withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.location_on,
                            color: _getStatusColor(),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            _getStatusText(),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _getStatusColor(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (safeZoneRadius != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Safe Zone Radius',
                        style: TextStyle(
                          color: AppColors.textDark.withOpacity(0.6),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$safeZoneRadius m',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _getStatusColor(),
                        ),
                      ),
                    ],
                    if (distance != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Distance from Center',
                        style: TextStyle(
                          color: AppColors.textDark.withOpacity(0.6),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$distance m',
                        style: TextStyle(
                          color: _getStatusColor(),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Center Point Card (Static)
              if (centerLat != null) ...[
                _buildSectionContainer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.secondary.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.my_location,
                              color: AppColors.secondary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Current Center Point',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Latitude',
                                  style: TextStyle(
                                    color: AppColors.textDark.withOpacity(0.6),
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  centerLat!,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Longitude',
                                  style: TextStyle(
                                    color: AppColors.textDark.withOpacity(0.6),
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  centerLng!,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              // Live Tracking Map
              if (currentLat != null) ...[
                _buildSectionContainer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.track_changes, color: AppColors.success),
                          SizedBox(width: 8),
                          Text(
                            'Live GPS Tracking',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () => _showFullscreenMap(),
                        child: Container(
                          height: 260,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: AppColors.primary.withOpacity(0.2),
                              width: 1.5,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Stack(
                              children: [
                                FlutterMap(
                                  mapController: _mapController,
                                  options: MapOptions(
                                    initialCenter:
                                        _currentPoint ??
                                        LatLng(
                                          double.tryParse(currentLat!) ??
                                              -6.200000,
                                          double.tryParse(currentLng!) ??
                                              106.816666,
                                        ),
                                    initialZoom: _mapZoom,
                                    interactionOptions:
                                        const InteractionOptions(
                                          flags: ~InteractiveFlag.rotate,
                                        ),
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate:
                                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName: 'moteguard_app',
                                    ),
                                    if (_trackPoints.isNotEmpty)
                                      PolylineLayer(
                                        polylines: [
                                          Polyline(
                                            points: _trackPoints,
                                            strokeWidth: 4,
                                            color: AppColors.secondary,
                                          ),
                                        ],
                                      ),
                                    if (_currentPoint != null)
                                      MarkerLayer(
                                        markers: [
                                          Marker(
                                            point: _currentPoint!,
                                            width: 40,
                                            height: 40,
                                            child: const Icon(
                                              Icons.motorcycle,
                                              color: AppColors.danger,
                                              size: 30,
                                            ),
                                          ),
                                        ],
                                      ),
                                    if (centerLat != null &&
                                        centerLng != null &&
                                        _currentPoint != null)
                                      MarkerLayer(
                                        markers: [
                                          Marker(
                                            point: LatLng(
                                              double.tryParse(centerLat!) ?? 0,
                                              double.tryParse(centerLng!) ?? 0,
                                            ),
                                            width: 30,
                                            height: 30,
                                            child: const Icon(
                                              Icons.place,
                                              color: AppColors.secondary,
                                              size: 20,
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                                Positioned(
                                  top: 10,
                                  right: 10,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Icon(
                                      Icons.fullscreen,
                                      color: AppColors.primary,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 12,
                                  left: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.55),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      "Tap to expand",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 12,
                                  right: 12,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.motorcycle,
                                              color: AppColors.danger,
                                              size: 16,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              'Current',
                                              style: TextStyle(fontSize: 10),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 4),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.place,
                                              color: AppColors.secondary,
                                              size: 16,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              'Center',
                                              style: TextStyle(fontSize: 10),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (currentLat != null) ...[
                _buildSectionContainer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.gps_fixed, color: AppColors.accent),
                          SizedBox(width: 8),
                          Text(
                            'Current Position',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricTile(
                              label: 'Latitude',
                              value: currentLat!,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricTile(
                              label: 'Longitude',
                              value: currentLng!,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricTile(
                              label: 'Altitude',
                              value: '$currentAlt m',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricTile(
                              label: 'Speed',
                              value: '$currentSpd km/h',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricTile(
                              label: 'Satellites',
                              value: '$currentSats',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              if (vibrationCount > 0) ...[
                _buildSectionContainer(
                  gradientColors: const [Color(0xFFFFF2E0), Colors.white],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.vibration, color: AppColors.warning),
                          SizedBox(width: 8),
                          Text(
                            'Vibration Sensor Status',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricTile(
                              label: 'Total Detections',
                              value: '$vibrationCount',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricTile(
                              label: 'Last Detection',
                              value: lastVibrationTime ?? "N/A",
                            ),
                          ),
                        ],
                      ),
                      if (vibrationLocation != null &&
                          vibrationLocation != "GPS belum tersedia") ...[
                        const SizedBox(height: 14),
                        Text(
                          'Last Location',
                          style: TextStyle(
                            color: AppColors.textDark.withOpacity(0.6),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          vibrationLocation!,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              _buildSectionContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(
                          Icons.mark_chat_unread,
                          color: AppColors.secondary,
                        ),
                        SizedBox(width: 8),
                        Text(
                          "Message Log",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 240,
                      child: messages.isEmpty
                          ? Center(
                              child: Text(
                                "No messages yet.\nWaiting for GPS data...",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.textDark.withOpacity(0.5),
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                final msg = messages[index];
                                Color cardColor = Colors.white;
                                IconData icon = Icons.message_outlined;
                                Color iconColor = AppColors.primary;
                                if (msg.contains('ALERT')) {
                                  cardColor = AppColors.danger.withOpacity(
                                    0.12,
                                  );
                                  icon = Icons.warning_amber_outlined;
                                  iconColor = AppColors.danger;
                                } else if (msg.contains('CENTER')) {
                                  cardColor = AppColors.secondary.withOpacity(
                                    0.12,
                                  );
                                  icon = Icons.my_location;
                                  iconColor = AppColors.secondary;
                                } else if (msg.contains('OUTSIDE')) {
                                  cardColor = AppColors.accent.withOpacity(
                                    0.15,
                                  );
                                  icon = Icons.error_outline;
                                  iconColor = AppColors.accent;
                                } else if (msg.contains('SAFE') ||
                                    msg.contains('NORMAL')) {
                                  cardColor = AppColors.success.withOpacity(
                                    0.15,
                                  );
                                  icon = Icons.check_circle_outline;
                                  iconColor = AppColors.success;
                                } else if (msg.toUpperCase().contains(
                                  'VIBRATION',
                                )) {
                                  cardColor = AppColors.warning.withOpacity(
                                    0.15,
                                  );
                                  icon = Icons.vibration;
                                  iconColor = AppColors.warning;
                                }
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cardColor,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(icon, size: 18, color: iconColor),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          msg,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}




