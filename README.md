# 🛵 MoteGuard - GPS Geofencing & Motor Security System

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-3.9.2-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.9.2-0175C2?logo=dart)
![ESP32](https://img.shields.io/badge/ESP32-Platform-FF6F00?logo=espressif)
![Firebase](https://img.shields.io/badge/Firebase-Cloud-FFCA28?logo=firebase)
![MQTT](https://img.shields.io/badge/MQTT-Protocol-3C873A?logo=eclipsemosquitto)

**Sistem keamanan motor berbasis GPS Geofencing dengan real-time tracking, vibration detection, dan remote control relay**

[Features](#-features) • [Architecture](#-system-architecture) • [Installation](#-installation) • [Usage](#-usage) • [Documentation](#-documentation)

</div>

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Features](#-features)
- [System Architecture](#-system-architecture)
- [Tech Stack](#-tech-stack)
- [Prerequisites](#-prerequisites)
- [Installation](#-installation)
- [Configuration](#-configuration)
- [Usage](#-usage)
- [Project Structure](#-project-structure)
- [ESP32 Setup](#-esp32-setup)
- [Firebase Setup](#-firebase-setup)
- [Database Documentation](#-database-documentation)
- [Troubleshooting](#-troubleshooting)
- [Contributing](#-contributing)
- [License](#-license)

---

## 🎯 Overview

**MoteGuard** adalah sistem keamanan motor yang mengintegrasikan GPS tracking, geofencing, dan sensor getaran untuk melindungi kendaraan Anda. Sistem ini terdiri dari:

- **ESP32** dengan GPS NEO-7M sebagai device tracker
- **Flutter Mobile App** untuk monitoring dan kontrol
- **Firebase** sebagai backend untuk data storage dan push notifications
- **MQTT** sebagai protokol komunikasi real-time

### Alur Sistem

```
ESP32 (GPS + Vibration Sensor) 
    ↓ MQTT
Mobile App (Flutter)
    ↓ Firestore
Firebase Cloud Functions
    ↓ FCM
Push Notifications
```

---

## ✨ Features

### 🎯 Core Features

- **📍 Real-time GPS Tracking**
  - Live location tracking dengan update setiap 1-2 detik
  - Visualisasi peta interaktif dengan marker dan polyline
  - History tracking dengan timestamp

- **🛡️ Geofencing System**
  - Set safe zone dengan radius yang dapat disesuaikan (default: 15 meter)
  - Alert otomatis saat keluar dari safe zone
  - Status monitoring: INSIDE, OUTSIDE, ALERT, SAFE

- **🔒 Motor Lock Control**
  - Remote control relay untuk mengunci/membuka motor
  - Auto-lock saat keluar safe zone + kecepatan ≤ 7 km/h
  - Manual control via aplikasi (ON/OFF/AUTO)

- **📳 Vibration Detection**
  - Sensor getaran SW420 terintegrasi
  - Alert otomatis saat getaran terdeteksi ≥ 10 detik
  - Notifikasi push ke aplikasi

- **🔔 Push Notifications**
  - Real-time alerts via Firebase Cloud Messaging (FCM)
  - Custom ringtone untuk alert GPS
  - Local notifications untuk vibration alerts

- **👤 User Authentication**
  - Firebase Authentication (Email/Password)
  - Google Sign-In support
  - User-specific data isolation

- **💾 Data Persistence**
  - GPS data history di Firestore
  - Center point storage
  - Vibration event logs
  - Offline mode support

### 🎨 UI/UX Features

- Modern Material Design 3
- Real-time status indicators
- Interactive map dengan OpenStreetMap
- Dark/Light theme support (coming soon)
- Responsive design untuk berbagai ukuran layar

---

## 🏗️ System Architecture

### Data Flow

```
┌─────────────┐
│   ESP32     │
│  (GPS +     │───MQTT───┐
│  Vibration) │          │
└─────────────┘          │
                         ▼
                  ┌──────────────┐
                  │  MQTT Broker │
                  │ (HiveMQ.com) │
                  └──────────────┘
                         │
                         ▼
                  ┌──────────────┐
                  │ Flutter App  │
                  │  (Subscriber)│
                  └──────────────┘
                         │
                         ▼
                  ┌──────────────┐
                  │   Firestore   │
                  │  (Database)  │
                  └──────────────┘
                         │
                         ▼
                  ┌──────────────┐
                  │Cloud Functions│
                  │  (Triggers)  │
                  └──────────────┘
                         │
                         ▼
                  ┌──────────────┐
                  │  FCM Push     │
                  │ Notifications │
                  └──────────────┘
```

### Communication Topics

| Topic | Direction | Description |
|-------|-----------|-------------|
| `gps/data` | ESP32 → App | GPS status, location updates |
| `gps/alert` | ESP32 → App | Alert notifications |
| `gps/control` | App → ESP32 | Control commands (ON/OFF/AUTO) |
| `gps/relay` | ESP32 → App | Relay status updates |
| `gps/vibration` | ESP32 → App | Vibration detection alerts |
| `gps/safezone` | App → ESP32 | Safe zone radius updates |

---

## 🛠️ Tech Stack

### Mobile App (Flutter)
- **Framework**: Flutter 3.9.2
- **Language**: Dart 3.9.2
- **State Management**: setState (StatefulWidget)
- **Mapping**: `flutter_map` + `latlong2`
- **MQTT**: `mqtt_client`
- **Firebase**: 
  - `firebase_core`
  - `cloud_firestore`
  - `firebase_auth`
- **Notifications**: `flutter_local_notifications`
- **Audio**: `audioplayers`
- **Storage**: `shared_preferences`

### Hardware (ESP32)
- **Microcontroller**: ESP32 (ESP32-WROOM-32)
- **GPS Module**: NEO-7M (9600 baud)
- **Display**: SSD1306 OLED (128x64)
- **Sensor**: SW420 Vibration Sensor
- **Relay**: 5V Relay Module (Active LOW)
- **Libraries**: 
  - TinyGPS++
  - PubSubClient (MQTT)
  - Adafruit SSD1306

### Backend (Firebase)
- **Database**: Cloud Firestore
- **Authentication**: Firebase Auth
- **Functions**: Cloud Functions (Node.js 18)
- **Messaging**: Firebase Cloud Messaging (FCM)
- **Storage**: Firestore Collections

---

## 📦 Prerequisites

### Software
- **Flutter SDK** ≥ 3.9.2
- **Dart SDK** ≥ 3.9.2
- **Android Studio** / **VS Code** dengan Flutter extension
- **Arduino IDE** atau **PlatformIO** (untuk ESP32)
- **Node.js** ≥ 18 (untuk Firebase Functions)
- **Firebase CLI** (untuk deploy functions)

### Hardware
- ESP32 Development Board
- GPS NEO-7M Module
- SSD1306 OLED Display (128x64)
- SW420 Vibration Sensor
- 5V Relay Module
- Jumper wires
- Power supply untuk ESP32 (USB atau external)

### Accounts
- Firebase project (gratis)
- MQTT Broker account (HiveMQ public broker atau private)

---

## 🚀 Installation

### 1. Clone Repository

```bash
git clone https://github.com/yourusername/moteguard_app.git
cd moteguard_app
```

### 2. Install Flutter Dependencies

```bash
flutter pub get
```

### 3. Setup Firebase

#### 3.1 Download `google-services.json`

1. Buka [Firebase Console](https://console.firebase.google.com/)
2. Pilih project Anda
3. Settings → Project settings → Your apps
4. Download `google-services.json`
5. Simpan di `android/app/google-services.json`

> **⚠️ Important**: File `google-services.json` sudah ada di `.gitignore` dan **tidak akan di-commit** ke GitHub untuk keamanan. Setiap developer harus download file ini sendiri dari Firebase Console.

#### 3.2 Setup Firestore Database

1. Di Firebase Console, buka **Firestore Database**
2. Create database (Production atau Test mode)
3. Pilih lokasi server (recommended: `asia-southeast1`)
4. Setup Security Rules (lihat [Firebase Setup](#firebase-setup))

#### 3.3 Enable Authentication

1. Buka **Authentication** → **Sign-in method**
2. Enable **Email/Password**
3. (Optional) Enable **Google Sign-In**

### 4. Setup Firebase Functions

```bash
cd functions
npm install
```

Deploy functions:
```bash
firebase deploy --only functions
```

### 5. Configure MQTT (Optional)

Jika ingin menggunakan MQTT broker sendiri, edit:
- ESP32: `esp32_fixed_code.ino` → `mqttServer`
- Flutter App: `lib/main.dart` → MQTT broker URL

### 6. Run Application

```bash
flutter run
```

---

## ⚙️ Configuration

### ESP32 Configuration

Edit `esp32_fixed_code.ino`:

```cpp
// WiFi Credentials
const char* ssid = "YOUR_WIFI_SSID";
const char* password = "YOUR_WIFI_PASSWORD";

// MQTT Broker
const char* mqttServer = "broker.hivemq.com"; // atau broker Anda

// Safe Zone Radius (meter)
#define DEFAULT_SAFE_ZONE_RADIUS 15.0

// Speed Threshold (km/h)
#define SPEED_THRESHOLD 7.0
```

### Flutter App Configuration

Edit `lib/main.dart` untuk mengubah:
- MQTT broker URL (jika menggunakan broker sendiri)
- Firestore collection names
- Notification settings

### Firebase Security Rules

Update Firestore Rules di Firebase Console:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    match /gps_data/{document=**} {
      allow read, write: if request.auth != null;
    }
    
    match /vibration_data/{document=**} {
      allow read, write: if request.auth != null;
    }
    
    match /gps_data_center/{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

---

## 📱 Usage

### First Time Setup

1. **Register/Login**
   - Buka aplikasi
   - Register dengan email/password atau Google Sign-In
   - Login ke aplikasi

2. **Connect ESP32**
   - Pastikan ESP32 sudah terhubung ke WiFi
   - ESP32 akan otomatis connect ke MQTT broker
   - Aplikasi akan otomatis subscribe ke topics

3. **Activate Geofencing**
   - Tap tombol **"ON"** untuk mengaktifkan tracking
   - ESP32 akan set center point dari lokasi GPS pertama
   - Safe zone akan terlihat di peta

### Daily Usage

- **Monitor Location**: Lihat posisi real-time di peta
- **Set Safe Zone**: Adjust radius dengan slider
- **Control Motor**: 
  - **ON**: Aktifkan geofencing
  - **OFF**: Sleep mode (hemat baterai)
  - **AUTO**: Auto-lock berdasarkan geofencing
- **View History**: Scroll ke bawah untuk melihat log messages
- **Alerts**: Notifikasi otomatis saat:
  - Keluar dari safe zone
  - Getaran terdeteksi ≥ 10 detik

### Status Indicators

| Status | Description |
|--------|-------------|
| 🟢 **ACTIVE** | Geofencing aktif, monitoring GPS |
| 😴 **SLEEP** | Sleep mode, tidak tracking |
| ✅ **SAFE** | Dalam safe zone, motor normal |
| ⚠️ **OUTSIDE** | Keluar safe zone, relay OFF |
| 🚨 **ALERT** | Alert zone breach |
| 📍 **CENTER_SET** | Center point baru diset |

---

## 📁 Project Structure

```
moteguard_app/
├── lib/
│   ├── main.dart                 # Main application file
│   ├── auth_service.dart         # Firebase authentication service
│   ├── login_page.dart           # Login UI
│   ├── register_page.dart        # Register UI
│   ├── mqtt_client_factory_io.dart    # MQTT client (mobile)
│   └── mqtt_client_factory_web.dart    # MQTT client (web)
│
├── esp32_fixed_code.ino          # ESP32 firmware (main)
├── esp32_oled_fun_animation.ino  # ESP32 dengan animasi OLED
│
├── functions/
│   ├── index.js                  # Cloud Functions
│   └── package.json              # Functions dependencies
│
├── android/                      # Android configuration
│   └── app/
│       └── google-services.json  # Firebase config (add manually)
│
├── assets/
│   └── sounds/
│       └── alert_ringtone.mp3    # Alert sound
│
├── pubspec.yaml                  # Flutter dependencies
├── README.md                     # This file
├── FIREBASE_DATABASE.md          # Firebase database documentation
└── MAIN_DART_DOCUMENTATION.md    # Detailed main.dart documentation
```

---

## 🔌 ESP32 Setup

### Hardware Connections

| Component | ESP32 Pin | Notes |
|-----------|-----------|-------|
| GPS RX | GPIO 16 | Serial2 RX |
| GPS TX | GPIO 17 | Serial2 TX |
| OLED SDA | GPIO 21 | I2C |
| OLED SCL | GPIO 22 | I2C |
| Vibration Sensor | GPIO 2 | INPUT_PULLUP |
| Relay | GPIO 26 | OUTPUT (Active LOW) |

### Upload Firmware

1. Install ESP32 board di Arduino IDE:
   - File → Preferences → Additional Board Manager URLs
   - Tambahkan: `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
   - Tools → Board → Boards Manager → Install "ESP32"

2. Install Libraries:
   - **TinyGPS++** (by Mikal Hart)
   - **PubSubClient** (by Nick O'Leary)
   - **Adafruit SSD1306** (by Adafruit)
   - **Adafruit GFX** (by Adafruit)

3. Upload Code:
   - Pilih board: **ESP32 Dev Module**
   - Upload speed: **115200**
   - Upload `esp32_fixed_code.ino`

### Testing

1. Buka Serial Monitor (115200 baud)
2. Cek WiFi connection
3. Cek MQTT connection
4. Cek GPS signal (tunggu fix)
5. Test relay control via MQTT

---

## 🔥 Firebase Setup

### 1. Create Firebase Project

1. Buka [Firebase Console](https://console.firebase.google.com/)
2. Add project → Isi nama project
3. Enable Google Analytics (optional)

### 2. Add Android App

1. Klik ikon Android → Register app
2. Package name: `com.example.moteguard_app` (sesuaikan dengan `build.gradle`)
3. Download `google-services.json`
4. Simpan di `android/app/google-services.json`

### 3. Setup Firestore

1. Firestore Database → Create database
2. Start in **Production mode** atau **Test mode**
3. Pilih location: `asia-southeast1` (recommended untuk Indonesia)
4. Update Security Rules (lihat [Configuration](#-configuration))

### 4. Enable Authentication

1. Authentication → Get started
2. Sign-in method → Enable **Email/Password**
3. (Optional) Enable **Google Sign-In**

### 5. Deploy Cloud Functions

```bash
cd functions
npm install
firebase login
firebase init functions
firebase deploy --only functions
```

### 6. Setup FCM (Optional)

Untuk push notifications:
1. Cloud Messaging → Get started
2. Generate FCM server key
3. Update Cloud Functions dengan server key

---

## 📊 Database Documentation

**📖 Untuk dokumentasi lengkap tentang struktur database Firebase, lihat: [FIREBASE_DATABASE.md](FIREBASE_DATABASE.md)**

### Quick Overview

Aplikasi menggunakan **Cloud Firestore** dengan 4 collections utama:

| Collection | Description |
|------------|-------------|
| `gps_data` | GPS tracking history dengan status (NORMAL, OUTSIDE, ALERT, SAFE) |
| `gps_data_center` | Center point untuk safe zone geofencing |
| `vibration_data` | Vibration detection events dari sensor SW420 |
| `user_tokens` | FCM tokens untuk push notifications (document ID = user ID) |

### Database Structure

```
Firestore
├── gps_data/
│   ├── {auto-id}/
│   │   ├── userId: string
│   │   ├── status: string (NORMAL|OUTSIDE|ALERT|SAFE)
│   │   ├── latitude: number
│   │   ├── longitude: number
│   │   ├── distance: number
│   │   ├── safeZoneRadius: number
│   │   └── timestamp: Timestamp
│   └── ...
├── gps_data_center/
│   ├── {auto-id}/
│   │   ├── userId: string
│   │   ├── latitude: number
│   │   ├── longitude: number
│   │   ├── safeZoneRadius: number
│   │   └── timestamp: Timestamp
│   └── ...
├── vibration_data/
│   ├── {auto-id}/
│   │   ├── userId: string
│   │   ├── latitude: number | null
│   │   ├── longitude: number | null
│   │   └── timestamp: Timestamp
│   └── ...
└── user_tokens/
    ├── {userId}/  (document ID = user ID)
    │   ├── fcmToken: string
    │   └── updatedAt: Timestamp
    └── ...
```

### Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /gps_data/{document=**} {
      allow read, write: if request.auth != null 
        && resource.data.userId == request.auth.uid;
    }
    match /gps_data_center/{document=**} {
      allow read, write: if request.auth != null 
        && resource.data.userId == request.auth.uid;
    }
    match /vibration_data/{document=**} {
      allow read, write: if request.auth != null 
        && resource.data.userId == request.auth.uid;
    }
    match /user_tokens/{userId} {
      allow read, write: if request.auth != null 
        && request.auth.uid == userId;
    }
  }
}
```

**Untuk detail lengkap tentang struktur, indexes, queries, dan setup, baca [FIREBASE_DATABASE.md](FIREBASE_DATABASE.md)**

---

## 🐛 Troubleshooting

### ESP32 Issues

**Problem**: ESP32 tidak connect ke WiFi
- ✅ Cek SSID dan password
- ✅ Pastikan WiFi 2.4GHz (ESP32 tidak support 5GHz)
- ✅ Cek signal strength

**Problem**: GPS tidak dapat fix
- ✅ Pastikan GPS module di outdoor (butuh line-of-sight ke satelit)
- ✅ Tunggu 1-2 menit untuk first fix
- ✅ Cek wiring (RX/TX tidak terbalik)
- ✅ Cek baudrate (9600)

**Problem**: MQTT tidak connect
- ✅ Cek internet connection
- ✅ Cek MQTT broker URL
- ✅ Cek firewall/port 1883

### Flutter App Issues

**Problem**: Firebase initialization error
- ✅ Pastikan `google-services.json` ada di `android/app/`
- ✅ Run `flutter clean` dan `flutter pub get`
- ✅ Cek Firebase project configuration

**Problem**: MQTT tidak receive messages
- ✅ Cek MQTT broker connection status
- ✅ Pastikan subscribe ke topics yang benar
- ✅ Cek ESP32 publish ke topics yang sama

**Problem**: Map tidak muncul
- ✅ Cek internet connection
- ✅ Pastikan `flutter_map` dependency terinstall
- ✅ Cek API key (jika menggunakan Google Maps)

### Firebase Issues

**Problem**: Firestore permission denied
- ✅ Update Security Rules (lihat [Configuration](#-configuration))
- ✅ Pastikan user sudah login
- ✅ Cek userId di document

**Problem**: Cloud Functions tidak trigger
- ✅ Cek function logs: `firebase functions:log`
- ✅ Pastikan function sudah di-deploy
- ✅ Cek Firestore trigger path

---

## 🤝 Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Code Style

- Follow Dart/Flutter style guide
- Use meaningful variable names
- Add comments for complex logic
- Test your changes before submitting

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 👨‍💻 Author

**Your Name**
- GitHub: [@yourusername](https://github.com/yourusername)
- Email: your.email@example.com

---

## 🙏 Acknowledgments

- [TinyGPS++](https://github.com/mikalhart/TinyGPSPlus) - GPS parsing library
- [PubSubClient](https://github.com/knolleary/pubsubclient) - MQTT client for Arduino
- [Flutter Map](https://github.com/fleaflet/flutter_map) - Mapping library
- [Firebase](https://firebase.google.com/) - Backend services
- [HiveMQ](https://www.hivemq.com/) - Public MQTT broker

---

## 📚 Additional Resources

### Documentation Files

- **[FIREBASE_DATABASE.md](FIREBASE_DATABASE.md)** - Complete Firebase Firestore database documentation
- **[MAIN_DART_DOCUMENTATION.md](MAIN_DART_DOCUMENTATION.md)** - Detailed `main.dart` code documentation

### External Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [ESP32 Documentation](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/)
- [Firebase Documentation](https://firebase.google.com/docs)
- [Firestore Documentation](https://firebase.google.com/docs/firestore)
- [MQTT Protocol](https://mqtt.org/)

---

<div align="center">

**⭐ If you find this project helpful, please give it a star! ⭐**

Made with ❤️ using Flutter & ESP32

</div>
