# 🔥 Firebase Database Documentation - MoteGuard

Dokumentasi lengkap tentang struktur database Firebase Firestore untuk aplikasi MoteGuard.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Struktur Database di Firebase](#struktur-database-di-firebase)
- [Detail Collections & Fields](#detail-collections--fields)
- [Cara Setup Database di Firebase](#cara-setup-database-di-firebase)
- [Cara Menambahkan Data Manual](#cara-menambahkan-data-manual)
- [Security Rules](#security-rules)
- [Indexes](#indexes)

---

## 🎯 Overview

MoteGuard menggunakan **Cloud Firestore** (NoSQL database) untuk menyimpan:
- 📍 GPS tracking data dan history
- 🎯 Center point untuk safe zone
- 📳 Vibration detection events
- 🔔 FCM tokens untuk push notifications

### Database Location
- **Recommended**: `asia-southeast1` (Singapore) - untuk performa terbaik di Indonesia
- **Alternative**: `us-central1`, `europe-west1`

---

## 📦 Struktur Database di Firebase

### Visual Structure

```
Firestore Database
│
├── 📁 gps_data (Collection)
│   ├── 📄 {auto-generated-id-1} (Document)
│   │   ├── userId: "abc123xyz"
│   │   ├── status: "ALERT"
│   │   ├── latitude: -6.2088
│   │   ├── longitude: 106.8456
│   │   ├── distance: 25.5
│   │   ├── safeZoneRadius: 15.0
│   │   ├── timestamp: 2024-01-15 10:30:00
│   │   └── ...
│   ├── 📄 {auto-generated-id-2}
│   └── ...
│
├── 📁 gps_data_center (Collection)
│   ├── 📄 {auto-generated-id-1}
│   │   ├── userId: "abc123xyz"
│   │   ├── latitude: -6.2088
│   │   ├── longitude: 106.8456
│   │   ├── safeZoneRadius: 15.0
│   │   └── timestamp: 2024-01-15 09:00:00
│   └── ...
│
├── 📁 vibration_data (Collection)
│   ├── 📄 {auto-generated-id-1}
│   │   ├── userId: "abc123xyz"
│   │   ├── latitude: -6.2088
│   │   ├── longitude: 106.8456
│   │   └── timestamp: 2024-01-15 10:35:00
│   └── ...
│
└── 📁 user_tokens (Collection)
    ├── 📄 abc123xyz (Document ID = User ID)
    │   ├── fcmToken: "dK3jF8...xyz123"
    │   └── updatedAt: 2024-01-15 10:00:00
    └── ...
```

---

## 📊 Detail Collections & Fields

### 1. Collection: `gps_data`

**Deskripsi**: Menyimpan semua data GPS tracking termasuk status lokasi (dalam safe zone, keluar, alert, dll).

#### Fields (Fields di Document)

| Field Name | Type | Required | Description | Contoh Value |
|------------|------|----------|-------------|--------------|
| `userId` | string | ✅ Yes | Firebase Auth UID user | `"abc123xyz"` |
| `status` | string | ✅ Yes | Status GPS: NORMAL, OUTSIDE, ALERT, SAFE, CENTER | `"ALERT"` |
| `latitude` | number | ✅ Yes | GPS latitude (-90 sampai 90) | `-6.2088` |
| `longitude` | number | ✅ Yes | GPS longitude (-180 sampai 180) | `106.8456` |
| `altitude` | number | ❌ Optional | Ketinggian dalam meter | `50.5` |
| `speed` | number | ❌ Optional | Kecepatan dalam km/h | `0.0` |
| `satellites` | number | ❌ Optional | Jumlah satelit GPS | `8` |
| `distance` | number | ❌ Optional | Jarak dari center point (meter) | `25.5` |
| `safeZoneRadius` | number | ❌ Optional | Radius safe zone (meter) | `15.0` |
| `timestamp` | timestamp | ✅ Yes | Waktu data dibuat (auto) | `2024-01-15 10:30:00` |
| `deviceId` | string | ✅ Yes | Identifier device | `"ESP32-GPS"` |
| `centerDocId` | string | ❌ Optional | ID document center point | `"center_doc_123"` |

#### Contoh Data di Firebase Console

**Document ID**: `gps_alert_001` (auto-generated)

```json
{
  "userId": "abc123xyz",
  "status": "ALERT",
  "latitude": -6.2088,
  "longitude": 106.8456,
  "altitude": 50.5,
  "speed": 0.0,
  "satellites": 8,
  "distance": 25.5,
  "safeZoneRadius": 15.0,
  "timestamp": "January 15, 2024 at 10:30:00 AM UTC+7",
  "deviceId": "ESP32-GPS",
  "centerDocId": "center_doc_123"
}
```

#### Status Values

| Status | Deskripsi | Kapan Dibuat |
|--------|-----------|--------------|
| `NORMAL` | Device dalam safe zone | GPS update normal |
| `OUTSIDE` | Device keluar safe zone | Jarak > radius |
| `ALERT` | Alert zone breach | Jarak > radius (level alert) |
| `SAFE` | Device kembali ke safe zone | Jarak ≤ radius |
| `CENTER` | Center point baru diset | User set center point |

---

### 2. Collection: `gps_data_center`

**Deskripsi**: Menyimpan center point untuk safe zone geofencing.

#### Fields

| Field Name | Type | Required | Description | Contoh Value |
|------------|------|----------|-------------|--------------|
| `userId` | string | ✅ Yes | Firebase Auth UID user | `"abc123xyz"` |
| `latitude` | number | ✅ Yes | Center point latitude | `-6.2088` |
| `longitude` | number | ✅ Yes | Center point longitude | `106.8456` |
| `safeZoneRadius` | number | ❌ Optional | Radius safe zone (meter) | `15.0` |
| `altitude` | number | ❌ Optional | Ketinggian (meter) | `50.5` |
| `speed` | number | ❌ Optional | Kecepatan saat center diset | `0.0` |
| `satellites` | number | ❌ Optional | Jumlah satelit GPS | `8` |
| `timestamp` | timestamp | ✅ Yes | Waktu center diset (auto) | `2024-01-15 09:00:00` |
| `deviceId` | string | ✅ Yes | Identifier device | `"ESP32-GPS"` |

#### Contoh Data di Firebase Console

**Document ID**: `center_001` (auto-generated)

```json
{
  "userId": "abc123xyz",
  "latitude": -6.2088,
  "longitude": 106.8456,
  "safeZoneRadius": 15.0,
  "altitude": 50.5,
  "speed": 0.0,
  "satellites": 8,
  "timestamp": "January 15, 2024 at 9:00:00 AM UTC+7",
  "deviceId": "ESP32-GPS"
}
```

---

### 3. Collection: `vibration_data`

**Deskripsi**: Menyimpan event deteksi getaran dari sensor SW420.

#### Fields

| Field Name | Type | Required | Description | Contoh Value |
|------------|------|----------|-------------|--------------|
| `userId` | string | ✅ Yes | Firebase Auth UID user | `"abc123xyz"` |
| `latitude` | number | ❌ Optional | GPS latitude saat getaran | `-6.2088` |
| `longitude` | number | ❌ Optional | GPS longitude saat getaran | `106.8456` |
| `timestamp` | timestamp | ✅ Yes | Waktu getaran terdeteksi (auto) | `2024-01-15 10:35:00` |
| `deviceId` | string | ✅ Yes | Identifier device | `"ESP32-GPS"` |

#### Contoh Data di Firebase Console

**Document ID**: `vibration_001` (auto-generated)

```json
{
  "userId": "abc123xyz",
  "latitude": -6.2088,
  "longitude": 106.8456,
  "timestamp": "January 15, 2024 at 10:35:00 AM UTC+7",
  "deviceId": "ESP32-GPS"
}
```

**Note**: Jika GPS belum tersedia saat getaran, `latitude` dan `longitude` bisa `null`.

---

### 4. Collection: `user_tokens`

**Deskripsi**: Menyimpan FCM (Firebase Cloud Messaging) tokens untuk push notifications.

#### Fields

| Field Name | Type | Required | Description | Contoh Value |
|------------|------|----------|-------------|--------------|
| `fcmToken` | string | ✅ Yes | FCM token untuk push notifications | `"dK3jF8...xyz123"` |
| `updatedAt` | timestamp | ✅ Yes | Waktu token terakhir diupdate (auto) | `2024-01-15 10:00:00` |

#### Document ID
- **Document ID = User ID** (Firebase Auth UID)
- Satu document per user
- Document ID harus sama dengan `userId` dari Firebase Authentication

#### Contoh Data di Firebase Console

**Document ID**: `abc123xyz` (sama dengan User ID)

```json
{
  "fcmToken": "dK3jF8hK2mN5pQ7sT9vW1xY3zA5bC7dE9fG1hI3jK5lM7nO9pQ1rS3tU5vW7xY9zA1bC3dE5fG7hI9jK1lM3nO5pQ7rS9tU1vW3xY5z",
  "updatedAt": "January 15, 2024 at 10:00:00 AM UTC+7"
}
```

---

## 🚀 Cara Setup Database di Firebase

### Step 1: Buat Firebase Project

1. Buka [Firebase Console](https://console.firebase.google.com/)
2. Klik **"Add project"** atau **"Create a project"**
3. Isi nama project: `moteguard-app` (atau nama lain)
4. (Optional) Enable Google Analytics
5. Klik **"Create project"**
6. Tunggu proses selesai, lalu klik **"Continue"**

### Step 2: Buat Firestore Database

1. Di Firebase Console, klik **"Firestore Database"** di menu kiri
2. Klik **"Create database"**
3. Pilih mode:
   - **Production mode** (dengan security rules) - **Recommended untuk production**
   - **Test mode** (tanpa security rules) - hanya untuk development/testing
4. Pilih location: **asia-southeast1** (Singapore) - recommended untuk Indonesia
5. Klik **"Enable"**
6. Tunggu database dibuat (beberapa detik)

### Step 3: Setup Security Rules

1. Di Firestore Database, klik tab **"Rules"**
2. Copy-paste Security Rules berikut:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper function: Check if user is authenticated
    function isAuthenticated() {
      return request.auth != null;
    }
    
    // Helper function: Check if user owns the document
    function isOwner(userId) {
      return isAuthenticated() && request.auth.uid == userId;
    }
    
    // GPS Data Collection
    match /gps_data/{document=**} {
      // Allow read/write only if authenticated and userId matches
      allow read, write: if isAuthenticated() 
        && resource.data.userId == request.auth.uid;
      
      // Allow create if userId in request matches auth
      allow create: if isAuthenticated() 
        && request.resource.data.userId == request.auth.uid;
    }
    
    // GPS Data Center Collection
    match /gps_data_center/{document=**} {
      allow read, write: if isAuthenticated() 
        && resource.data.userId == request.auth.uid;
      allow create: if isAuthenticated() 
        && request.resource.data.userId == request.auth.uid;
    }
    
    // Vibration Data Collection
    match /vibration_data/{document=**} {
      allow read, write: if isAuthenticated() 
        && resource.data.userId == request.auth.uid;
      allow create: if isAuthenticated() 
        && request.resource.data.userId == request.auth.uid;
    }
    
    // User Tokens Collection
    match /user_tokens/{userId} {
      // User can only read/write their own token
      allow read, write: if isOwner(userId);
    }
    
    // Deny all other access
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

3. Klik **"Publish"** untuk menyimpan rules

### Step 4: Enable Authentication

1. Di Firebase Console, klik **"Authentication"** di menu kiri
2. Klik **"Get started"** (jika pertama kali)
3. Klik tab **"Sign-in method"**
4. Enable **"Email/Password"**:
   - Klik **"Email/Password"**
   - Toggle **"Enable"** menjadi ON
   - Klik **"Save"**
5. (Optional) Enable **"Google"** untuk Google Sign-In

### Step 5: Download `google-services.json`

1. Klik ikon **⚙️ Settings** (gear icon) di kiri atas
2. Pilih **"Project settings"**
3. Scroll ke bawah ke bagian **"Your apps"**
4. Klik ikon **Android** (🟢)
5. Register app:
   - **Android package name**: `com.example.moteguard_app` (sesuaikan dengan `build.gradle`)
   - **App nickname** (optional): `MoteGuard Android`
   - Klik **"Register app"**
6. Download **`google-services.json`**
7. Simpan file di: `android/app/google-services.json`

> **⚠️ Important**: File `google-services.json` sudah ada di `.gitignore` dan **tidak akan di-commit** ke GitHub untuk keamanan. Setiap developer harus download file ini sendiri dari Firebase Console mereka.

---

## ✏️ Cara Menambahkan Data Manual di Firebase Console

### Menambahkan GPS Data

1. Buka Firebase Console → **Firestore Database**
2. Klik **"Start collection"** (jika belum ada collection)
3. Collection ID: `gps_data`
4. Document ID: Klik **"Auto-ID"** (biarkan auto-generated)
5. Tambahkan fields:

| Field | Type | Value |
|-------|------|-------|
| `userId` | string | `abc123xyz` |
| `status` | string | `ALERT` |
| `latitude` | number | `-6.2088` |
| `longitude` | number | `106.8456` |
| `distance` | number | `25.5` |
| `safeZoneRadius` | number | `15.0` |
| `timestamp` | timestamp | Klik "Set timestamp" → Pilih waktu |
| `deviceId` | string | `ESP32-GPS` |

6. Klik **"Save"**

### Menambahkan Center Point

1. Klik **"Start collection"**
2. Collection ID: `gps_data_center`
3. Document ID: **Auto-ID**
4. Tambahkan fields:

| Field | Type | Value |
|-------|------|-------|
| `userId` | string | `abc123xyz` |
| `latitude` | number | `-6.2088` |
| `longitude` | number | `106.8456` |
| `safeZoneRadius` | number | `15.0` |
| `timestamp` | timestamp | Set timestamp |
| `deviceId` | string | `ESP32-GPS` |

5. Klik **"Save"**

### Menambahkan Vibration Data

1. Klik **"Start collection"**
2. Collection ID: `vibration_data`
3. Document ID: **Auto-ID**
4. Tambahkan fields:

| Field | Type | Value |
|-------|------|-------|
| `userId` | string | `abc123xyz` |
| `latitude` | number | `-6.2088` (atau biarkan kosong) |
| `longitude` | number | `106.8456` (atau biarkan kosong) |
| `timestamp` | timestamp | Set timestamp |
| `deviceId` | string | `ESP32-GPS` |

5. Klik **"Save"**

### Menambahkan User Token

1. Klik **"Start collection"**
2. Collection ID: `user_tokens`
3. **Document ID**: Masukkan **User ID** (bukan Auto-ID!)
   - Contoh: `abc123xyz` (sama dengan Firebase Auth UID)
4. Tambahkan fields:

| Field | Type | Value |
|-------|------|-------|
| `fcmToken` | string | `dK3jF8...xyz123` (FCM token dari app) |
| `updatedAt` | timestamp | Set timestamp |

5. Klik **"Save"**

---

## 📇 Indexes

Firestore memerlukan **composite indexes** untuk query yang kompleks. Indexes akan **otomatis dibuat** saat diperlukan, atau bisa dibuat manual.

### Index yang Mungkin Diperlukan

#### 1. Query GPS Data by User and Timestamp

**Collection**: `gps_data`  
**Fields**: 
- `userId` (Ascending)
- `timestamp` (Descending)

**Use Case**: Get latest GPS data for a user

#### 2. Query GPS Data by User and Status

**Collection**: `gps_data`  
**Fields**:
- `userId` (Ascending)
- `status` (Ascending)
- `timestamp` (Descending)

**Use Case**: Get all ALERT events for a user

### Cara Membuat Index Manual

1. Firebase Console → **Firestore Database** → Tab **"Indexes"**
2. Klik **"Create index"**
3. Pilih collection: `gps_data`
4. Tambahkan fields:
   - Field: `userId`, Order: **Ascending**
   - Field: `timestamp`, Order: **Descending**
5. Klik **"Create"**
6. Tunggu index dibuat (beberapa menit)

**Atau**: Saat query dijalankan, Firebase akan menampilkan link untuk membuat index otomatis.

---

## 💰 Biaya & Storage

### Firestore Pricing (2024)

| Operation | Free Tier | Paid Tier |
|-----------|-----------|-----------|
| Reads | 50,000/day | $0.06 per 100,000 |
| Writes | 20,000/day | $0.18 per 100,000 |
| Deletes | 20,000/day | $0.02 per 100,000 |
| Storage | 1 GB | $0.18 per GB/month |

### Perkiraan Biaya (100 users aktif)

- **Reads**: ~500,000/bulan = **$0.30**
- **Writes**: ~200,000/bulan = **$0.36**
- **Storage**: ~500 MB = **$0.09**
- **Total**: ~**$0.75/bulan** (masih dalam free tier untuk development)

---

## 🔍 Monitoring Data di Firebase Console

### Melihat Data

1. Firebase Console → **Firestore Database**
2. Klik collection (misal: `gps_data`)
3. Klik document untuk melihat detail fields
4. Gunakan filter untuk mencari data spesifik

### Menghapus Data

1. Buka collection
2. Klik document yang ingin dihapus
3. Klik **"Delete document"**
4. Konfirmasi

### Export Data

1. Firestore Database → Tab **"Usage"**
2. Scroll ke **"Export"** section
3. Klik **"Export"** untuk download data

---

## ✅ Checklist Setup Database

- [ ] Firebase project created
- [ ] Firestore database created (Production mode)
- [ ] Security rules applied
- [ ] Authentication enabled (Email/Password)
- [ ] `google-services.json` downloaded
- [ ] Collections created (atau akan otomatis dibuat oleh app)
- [ ] Test data inserted (optional)
- [ ] Indexes created (jika diperlukan)

---

## 📚 Additional Resources

- [Firestore Documentation](https://firebase.google.com/docs/firestore)
- [Security Rules Guide](https://firebase.google.com/docs/firestore/security/get-started)
- [Firebase Console](https://console.firebase.google.com/)

---

**Last Updated**: 2024-01-15  
**Version**: 2.0.0
