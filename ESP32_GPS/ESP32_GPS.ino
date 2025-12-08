#include <TinyGPS++.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <math.h>
#include <Preferences.h>
#include <esp_system.h>

// GPS Serial pins
#define GPS_RX_PIN 16
#define GPS_TX_PIN 17
#define GPS_BAUDRATE 9600

// Relay pin
#define RELAY_PIN 26

// Vibration Sensor pin (SW420)
#define VIBRATION_PIN 2

// Geofencing parameters
#define DEFAULT_SAFE_ZONE_RADIUS 15.0  // Default safezone radius (meter)
#define SPEED_THRESHOLD 7.0

// Safe zone radius yang bisa diubah dari aplikasi (default 15.0 meter)
double safeZoneRadius = DEFAULT_SAFE_ZONE_RADIUS;
Preferences prefs;

// Authorization / offline control
bool awaitingInitialCommand = true;
bool offlineModeActive = false;
uint32_t bootSessionId = 0;
unsigned long lastAuthStatusPublish = 0;
const unsigned long AUTH_STATUS_INTERVAL = 5000UL;
unsigned long lastOfflineLog = 0;
const unsigned long OFFLINE_LOG_INTERVAL = 10000UL;
unsigned long lastMqttErrorLog = 0;
const unsigned long MQTT_ERROR_LOG_INTERVAL = 30000UL;
unsigned long lastWifiErrorLog = 0;
const unsigned long WIFI_ERROR_LOG_INTERVAL = 30000UL;
bool lastMqttConnectionState = false;

// Publish intervals
const unsigned long SAFE_PUBLISH_INTERVAL = 2000UL;        // 1 menit saat di dalam safe zone
const unsigned long PUBLISH_INTERVAL_OUTSIDE = 2000UL;     // 2 detik saat di luar safe zone

// Vibration sensor timing
unsigned long lastVibrationCheck = 0;
const unsigned long VIBRATION_CHECK_INTERVAL = 100UL;
unsigned long lastVibrationPublish = 0;
const unsigned long VIBRATION_PUBLISH_INTERVAL = 1000UL;
bool lastVibrationState = false;

// Vibration detection - deteksi perubahan setiap 2 detik
unsigned long vibrationPeriodStart = 0;
unsigned int vibrationPeriodCount = 0;
bool vibrationChangedInPeriod = false;
const unsigned long VIBRATION_PERIOD_INTERVAL = 2000UL;
const unsigned int VIBRATION_PERIOD_MIN_COUNT = 5;
bool vibrationDetectedForMQTT = false;

WiFiClient espClient;
PubSubClient client(espClient); 
const char* ssid = "okeeeeee";
const char* password = "12345678";

const char* mqttServer = "broker.hivemq.com";
const char* topicData = "gps/data";
const char* topicAlert = "gps/alert";
const char* topicControl = "gps/control";
const char* topicRelay = "gps/relay";
const char* topicVibration = "gps/vibration";
const char* topicSafeZone = "gps/safezone";

const char* clientID = "ESP32-wokwi-gps";

TinyGPSPlus gps;
HardwareSerial GPS_Serial(2);

struct GeoPoint {
  double lat;
  double lng;
  bool isSet;
};

GeoPoint centerPoint = {0.0, 0.0, false};
bool isOutsideSafeZone = false;
bool alertSent = false;
bool relayState = false;
bool waitingForSpeed = false;

unsigned long lastGPSCheck = 0;
unsigned long lastPublish = 0;
const unsigned long GPS_CHECK_INTERVAL = 1000;

bool sleepMode = false;
bool manualControl = false;

// Track if this is a wakeup from deep sleep
bool wakeFromDeepSleep = false;

// Sleep mode timing
unsigned long lastSleepCheck = 0;
const unsigned long SLEEP_CHECK_INTERVAL = 5000UL;

void controlRelay(bool state) {
  relayState = state;
  
  // Untuk relay Active LOW (paling umum):
  // state = true (motor dikunci) → relay AKTIF → pin LOW
  // state = false (motor normal) → relay OFF → pin HIGH
  digitalWrite(RELAY_PIN, state ? LOW : HIGH);
  
  String status = state ? "MOTOR DIKUNCI" : "MOTOR NORMAL";
  Serial.print("Relay: ");
  Serial.println(status);
  Serial.print("Pin State: ");
  Serial.println(state ? "LOW (Active)" : "HIGH (Inactive)");
  
  String relayMsg = state ? "ON,Listrik_Terputus" : "OFF,Listrik_Normal";
  publishMessageIfConnected(topicRelay, relayMsg);
}

double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const double R = 6371000.0;
  double dLat = (lat2 - lat1) * PI / 180.0;
  double dLon = (lon2 - lon1) * PI / 180.0;
  double a = sin(dLat / 2.0) * sin(dLat / 2.0) +
             cos(lat1 * PI / 180.0) * cos(lat2 * PI / 180.0) *
             sin(dLon / 2.0) * sin(dLon / 2.0);
  double c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a));
  return R * c;
}

void checkVibrationSensor() {
  unsigned long now = millis();
  
  // Baca sensor (SW420 active LOW dengan INPUT_PULLUP, jadi LOW = ada getaran)
  bool vibrationDetected = digitalRead(VIBRATION_PIN) == LOW;

  // Deteksi perubahan state (edge detection)
  if (vibrationDetected != lastVibrationState) {
    vibrationChangedInPeriod = true;
  }

  // Cek apakah periode 2 detik sudah selesai
  if (vibrationPeriodStart == 0) {
    vibrationPeriodStart = now;
    vibrationPeriodCount = 0;
    vibrationChangedInPeriod = false;
    vibrationDetectedForMQTT = false;
  } else {
    unsigned long periodDuration = now - vibrationPeriodStart;
    
    if (periodDuration >= VIBRATION_PERIOD_INTERVAL) {
      if (vibrationChangedInPeriod) {
        vibrationPeriodCount++;
        Serial.print("[VIBRATION] Periode ");
        Serial.print(vibrationPeriodCount);
        Serial.println(": Ada perubahan (2 detik)");
        
        if (vibrationPeriodCount >= VIBRATION_PERIOD_MIN_COUNT && !vibrationDetectedForMQTT) {
          Serial.println("!!! GETARAN TERDETEKSI SELAMA 10 DETIK (5 PERIODE x 2 DETIK) !!!");
          Serial.print("Total periode: ");
          Serial.print(vibrationPeriodCount);
          Serial.println(" periode (setiap 2 detik)");
          
          String vibrationMsg = "VIBRATION_DETECTED";
          if (gps.location.isValid()) {
            vibrationMsg += "," + String(gps.location.lat(), 6) + "," + String(gps.location.lng(), 6);
            Serial.print("Lokasi GPS: ");
            Serial.print(gps.location.lat(), 6);
            Serial.print(", ");
            Serial.println(gps.location.lng(), 6);
          } else {
            Serial.println("[VIBRATION] GPS belum siap, kirim tanpa koordinat");
          }

          publishMessageIfConnected(topicVibration, vibrationMsg);
          Serial.println(">>> Vibration alert sent to MQTT! <<<");
          vibrationDetectedForMQTT = true;
        }
      } else {
        vibrationPeriodCount = 0;
        vibrationDetectedForMQTT = false;
      }
      
      vibrationPeriodStart = now;
      vibrationChangedInPeriod = false;
    }
  }

  lastVibrationState = vibrationDetected;
}

void setup_wifi() {
  Serial.print("Connecting to WiFi");
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(100);
  
  WiFi.begin(ssid, password);
  
  int retry = 0;
  while (WiFi.status() != WL_CONNECTED && retry < 30) {
    delay(500);
    Serial.print(".");
    retry++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi connected!");
    Serial.print("IP: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("\nWiFi connect failed or timeout");
    delay(2000);
    ESP.restart();
  }
}

void check_wifi() {
  if (WiFi.status() != WL_CONNECTED) {
    unsigned long now = millis();
    if (now - lastWifiErrorLog >= WIFI_ERROR_LOG_INTERVAL) {
      lastWifiErrorLog = now;
      Serial.println("[WiFi] Disconnected, reconnecting...");
    }
    
    WiFi.disconnect();
    delay(50);
    WiFi.begin(ssid, password);
    
    int retry = 0;
    int maxRetry = awaitingInitialCommand ? 20 : 3;
    unsigned long retryDelay = awaitingInitialCommand ? 500UL : 200UL;
    while (WiFi.status() != WL_CONNECTED && retry < maxRetry) {
      delay(retryDelay);
      retry++;
    }
    
    if (WiFi.status() == WL_CONNECTED) {
      if (now - lastWifiErrorLog >= WIFI_ERROR_LOG_INTERVAL) {
        Serial.println("[WiFi] Reconnected!");
      }
    }
  }
}

bool isAuthorizationCommand(const String& message) {
  return message == "ON" ||
         message == "OFF" ||
         message == "AUTO" ||
         message == "RELAY_ON" ||
         message == "RELAY_OFF";
}

void publishMessageIfConnected(const char* topic, const String& payload) {
  if (!client.connected()) {
    Serial.print("[MQTT OFFLINE] Skip publish to ");
    Serial.println(topic);
    return;
  }
  client.publish(topic, payload.c_str());
}

void publishStatusMessage(const String& label) {
  if (!client.connected()) {
    return;
  }
  String msg = "STATUS," + label + "," + String(bootSessionId, HEX);
  client.publish(topicData, msg.c_str());
  Serial.print("[STATUS] ");
  Serial.println(msg);
}

void acknowledgeInitialCommand(const String& commandLabel) {
  if (!awaitingInitialCommand || !isAuthorizationCommand(commandLabel)) {
    return;
  }
  awaitingInitialCommand = false;
  offlineModeActive = false;
  centerPoint.isSet = false;
  isOutsideSafeZone = false;
  alertSent = false;
  waitingForSpeed = false;
  Serial.println("[AUTH] Perintah awal dari aplikasi diterima");
  publishStatusMessage("AUTHORIZED");
}

void ensureAuthorizationHeartbeat() {
  if (!awaitingInitialCommand || !client.connected()) {
    return;
  }
  unsigned long now = millis();
  if (now - lastAuthStatusPublish >= AUTH_STATUS_INTERVAL) {
    lastAuthStatusPublish = now;
    publishStatusMessage("WAITING_AUTH");
  }
}

void enterOfflineMode(const String& reason) {
  if (offlineModeActive) {
    return;
  }
  offlineModeActive = true;
  Serial.print("[OFFLINE MODE] ");
  Serial.println(reason);
}

void exitOfflineModeIfNeeded() {
  if (!offlineModeActive) {
    return;
  }
  offlineModeActive = false;
  Serial.println("[OFFLINE MODE] Koneksi MQTT kembali normal");
}

void callback(char* topic, byte* payload, unsigned int length) {
  String message = "";
  for (unsigned int i = 0; i < length; i++) {
    message += (char)payload[i];
  }
  
  Serial.print("[MQTT] ");
  Serial.print(topic);
  Serial.print(": ");
  Serial.println(message);
  
  if (String(topic) == topicControl) {
    acknowledgeInitialCommand(message);
    if (message == "RELAY_OFF") {
      Serial.println(">> MANUAL: Motor Dikunci");
      manualControl = true;
      controlRelay(true);
      waitingForSpeed = false;
      
    } else if (message == "RELAY_ON") {
      Serial.println(">> MANUAL: Motor Normal");
      manualControl = true;
      controlRelay(false);
      waitingForSpeed = false;
      
    } else if (message == "AUTO") {
      Serial.println(">> AUTO Mode");
      manualControl = false;
      waitingForSpeed = false;
      
    } else if (message == "OFF") {
      Serial.println(">> Sleep Mode - Preparing for periodic sleep...");
      sleepMode = true;
      centerPoint.isSet = false;
      isOutsideSafeZone = false;
      manualControl = false;
      waitingForSpeed = false;
      controlRelay(false);
      
      publishMessageIfConnected(topicData, "SLEEP");
      client.loop();
      delay(500);
      
      Serial.println("Entering light sleep mode...");
      Serial.println("ESP32 will wake up every 5 seconds to check for 'ON' command");
      Serial.flush();
      
    } else if (message == "ON") {
      Serial.println(">> Active Mode - Waking up from sleep!");
      sleepMode = false;
      wakeFromDeepSleep = false;
      centerPoint.isSet = false;
      isOutsideSafeZone = false;
      manualControl = false;
      waitingForSpeed = false;
      controlRelay(false);
      
      if (!client.connected()) {
        reconnect(false);
      }
      publishMessageIfConnected(topicData, "ACTIVE");
      Serial.println(">> ESP32 is now ACTIVE and monitoring GPS");
      
    } else if (message == "RESET_CENTER") {
      Serial.println(">> Reset Center Point");
      centerPoint.isSet = false;
      isOutsideSafeZone = false;
      alertSent = false;
      manualControl = false;
      waitingForSpeed = false;
      controlRelay(false);
      publishMessageIfConnected(topicData, "RESET");
    }
  } else if (String(topic) == topicSafeZone) {
    double newRadius = message.toDouble();
    if (newRadius > 0 && newRadius <= 1000.0) {
      safeZoneRadius = newRadius;
      Serial.print(">> Safe Zone Radius updated: ");
      Serial.print(safeZoneRadius);
      Serial.println(" meter");
      
      String confirmMsg = "SAFEZONE_SET," + String(safeZoneRadius, 1);
      publishMessageIfConnected(topicData, confirmMsg);
      prefs.putDouble("safeZone", safeZoneRadius);
    } else {
      Serial.print(">> Invalid safezone radius: ");
      Serial.println(newRadius);
    }
  }
}

bool reconnect(bool allowLongWait) {
  unsigned long now = millis();
  bool shouldLog = (now - lastMqttErrorLog >= MQTT_ERROR_LOG_INTERVAL);
  
  int retryCount = 0;
  int maxRetry = allowLongWait ? 10 : (offlineModeActive ? 1 : 3);
  unsigned long delayPerRetry = allowLongWait ? 2000UL : (offlineModeActive ? 200UL : 500UL);
  while (!client.connected() && retryCount < maxRetry) {
    if (shouldLog && retryCount == 0) {
      Serial.println("[MQTT] Connecting...");
      lastMqttErrorLog = now;
    }
    
    String uniqueClientID = String(clientID) + "_" + String(millis());
    
    if (client.connect(uniqueClientID.c_str())) {
      if (shouldLog) {
        Serial.println("[MQTT] Connected!");
      }
      exitOfflineModeIfNeeded();
      lastMqttConnectionState = true;
      client.subscribe(topicControl);
      client.subscribe(topicSafeZone);
      
      if (wakeFromDeepSleep) {
        publishMessageIfConnected(topicData, "ACTIVE");
        wakeFromDeepSleep = false;
      }
      if (awaitingInitialCommand) {
        lastAuthStatusPublish = 0;
        publishStatusMessage("WAITING_AUTH");
      }
      return true;
    } else {
      if (shouldLog && retryCount == maxRetry - 1) {
        Serial.print("[MQTT] Connection failed, rc=");
        Serial.println(client.state());
      }
      delay(delayPerRetry);
      retryCount++;
    }
  }
  
  if (shouldLog && !client.connected()) {
    Serial.println("[MQTT] Connection could not be established (mode offline)");
  }
  lastMqttConnectionState = client.connected();
  
  if (!allowLongWait && !awaitingInitialCommand) {
    enterOfflineMode("MQTT unreachable");
  }
  return client.connected();
}

void setup() {
  Serial.begin(115200);
  delay(1000);
  
  prefs.begin("moteguard", false);
  double storedRadius = prefs.getDouble("safeZone", DEFAULT_SAFE_ZONE_RADIUS);
  if (storedRadius > 0.0 && storedRadius <= 1000.0) {
    safeZoneRadius = storedRadius;
  } else {
    prefs.putDouble("safeZone", safeZoneRadius);
  }
  
  bootSessionId = esp_random();
  if (bootSessionId == 0) {
    bootSessionId = (uint32_t)(millis() + random(1, 1000));
  }
  
  esp_sleep_wakeup_cause_t wakeup_reason = esp_sleep_get_wakeup_cause();
  if (wakeup_reason == ESP_SLEEP_WAKEUP_TIMER) {
    wakeFromDeepSleep = true;
    Serial.println("\n=== WAKE FROM DEEP SLEEP ===");
  } else {
    Serial.println("\n=== NORMAL STARTUP ===");
  }
  
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, HIGH);
  
  pinMode(VIBRATION_PIN, INPUT_PULLUP);
  Serial.println("\n=== Setup Vibration Sensor ===");
  Serial.print("Vibration Pin: GPIO ");
  Serial.println(VIBRATION_PIN);
  Serial.println("Sensor ready!");
  Serial.println("MQTT: Akan kirim jika getaran >= 10 detik");
  Serial.println("Serial Monitor: Tampilkan setiap getaran");
  Serial.println();
  
  Serial.println("=== ESP32 GPS Geofencing + Speed Lock + Vibration Sensor ===");
  Serial.print("Safe Zone: ");
  Serial.print(safeZoneRadius);
  Serial.println(" meter");
  Serial.print("Speed Threshold: ");
  Serial.print(SPEED_THRESHOLD);
  Serial.println(" km/h");
  Serial.print("Relay Pin: GPIO ");
  Serial.println(RELAY_PIN);
  Serial.print("Vibration Pin: GPIO ");
  Serial.println(VIBRATION_PIN);
  Serial.println("=========================================");
  Serial.println("LOGIKA: Relay OFF -> Speed <=7km/h -> Motor Lock");
  Serial.println("VIBRATION: Serial Monitor = setiap getaran");
  Serial.println("VIBRATION: MQTT = hanya jika >= 10 detik");
  Serial.println("=========================================\n");
  
  GPS_Serial.begin(GPS_BAUDRATE, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
  
  setup_wifi();
  client.setServer(mqttServer, 1883);
  client.setCallback(callback);
  client.setKeepAlive(60);
  client.setSocketTimeout(15);
  
  if (!client.connected()) {
    reconnect(true);
  }
}

void loop() {
  unsigned long currentMillis = millis();
  
  checkVibrationSensor();

  check_wifi();
  bool mqttConnected = client.connected();
  if (!mqttConnected) {
    mqttConnected = reconnect(awaitingInitialCommand);
    if (!mqttConnected && awaitingInitialCommand) {
      delay(200);
      return;
    }
  } else {
    exitOfflineModeIfNeeded();
  }
  
  bool currentMqttState = mqttConnected;
  if (currentMqttState != lastMqttConnectionState) {
    lastMqttConnectionState = currentMqttState;
  }
  
  if (mqttConnected) {
    client.loop();
  }
  
  if (awaitingInitialCommand) {
    ensureAuthorizationHeartbeat();
    delay(200);
    return;
  }
  
  if (sleepMode) {
    if (currentMillis - lastSleepCheck >= SLEEP_CHECK_INTERVAL) {
      lastSleepCheck = currentMillis;
      
      Serial.println("[SLEEP] Checking for wake command...");
      
      check_wifi();
      
      if (!client.connected()) {
        reconnect(true);
      }
      
      if (client.connected()) {
        client.loop();
      }
      
      if (!sleepMode) {
        Serial.println("[SLEEP] Waking up from sleep mode!");
        lastGPSCheck = currentMillis;
        lastPublish = currentMillis;
      }
      
      delay(100);
    } else {
      delay(100);
    }
    return;
  }
  
  if (offlineModeActive) {
    if (millis() - lastOfflineLog >= OFFLINE_LOG_INTERVAL) {
      lastOfflineLog = millis();
      Serial.println("[OFFLINE MODE] MQTT masih offline, pantau mandiri.");
    }
  }
  
  while (GPS_Serial.available() > 0) {
    gps.encode(GPS_Serial.read());
  }
  
  if (currentMillis - lastGPSCheck >= GPS_CHECK_INTERVAL) {
    lastGPSCheck = currentMillis;
    
    if (gps.location.isValid()) {
      double currentLat = gps.location.lat();
      double currentLng = gps.location.lng();
      double currentAlt = 0.0;
      if (gps.altitude.isValid()) {
        currentAlt = gps.altitude.meters();
      }
      int satCount = gps.satellites.value();
      
      double currentSpeed = 0.0;
      if (gps.speed.isValid()) {
        currentSpeed = gps.speed.kmph();
      }
      
      Serial.println("\n--- GPS DATA ---");
      Serial.print("Lat: ");
      Serial.println(currentLat, 6);
      Serial.print("Lng: ");
      Serial.println(currentLng, 6);
      Serial.print("Alt: ");
      Serial.print(currentAlt, 2);
      Serial.println(" m");
      Serial.print("Speed: ");
      Serial.print(currentSpeed, 2);
      Serial.println(" km/h");
      Serial.print("Satellites: ");
      Serial.println(satCount);
      
      if (!centerPoint.isSet) {
        centerPoint.lat = currentLat;
        centerPoint.lng = currentLng;
        centerPoint.isSet = true;
        
        Serial.println("\n*** CENTER POINT SET ***");
        Serial.print("Center Lat: ");
        Serial.println(centerPoint.lat, 6);
        Serial.print("Center Lng: ");
        Serial.println(centerPoint.lng, 6);
        Serial.println("\n");
        
        if (!manualControl) {
          controlRelay(false);
        }
        
        lastPublish = currentMillis;
        String msg = "CENTER," + 
                     String(currentLat, 6) + "," + 
                     String(currentLng, 6) + "," + 
                     String(currentAlt, 2) + "," + 
                     String(currentSpeed, 2) + "," + 
                     String(satCount) + "," + 
                     String(safeZoneRadius, 1);
        publishMessageIfConnected(topicData, msg);
        
      } else {
        double distance = calculateDistance(
          centerPoint.lat, centerPoint.lng,
          currentLat, currentLng
        );
        
        Serial.print("Distance: ");
        Serial.print(distance, 2);
        Serial.println(" m");
        
        bool inSafeZone = (distance <= safeZoneRadius);
        unsigned long publishInterval = inSafeZone ? SAFE_PUBLISH_INTERVAL : PUBLISH_INTERVAL_OUTSIDE;
        
        if (!manualControl) {
          if (!inSafeZone) {
            if (!isOutsideSafeZone) {
              isOutsideSafeZone = true;
              alertSent = false;
              
              Serial.println("\n!!! KELUAR ZONA AMAN !!!");
              Serial.println(">>> STEP 1: Memutus Relay <<<");
              
              controlRelay(true);
              waitingForSpeed = true;
              
              Serial.println(">>> Menunggu kecepatan <= 7 km/h <<<\n");
            }
            
            if (waitingForSpeed && relayState == true) {
              if (currentSpeed <= SPEED_THRESHOLD) {
                Serial.println("\n>>> KECEPATAN CUKUP RENDAH <<<");
                Serial.print("Kecepatan: ");
                Serial.print(currentSpeed, 2);
                Serial.println(" km/h");
                Serial.println(">>> MOTOR TERKUNCI (Relay OFF) <<<");
                
                waitingForSpeed = false;
                
                Serial.println(">>> PENGUNCIAN SELESAI <<<\n");
              } else {
                Serial.print("Menunggu... Speed: ");
                Serial.print(currentSpeed, 2);
                Serial.println(" km/h");
              }
            }
            
            if (!alertSent) {
              String motorStatus = (!waitingForSpeed && relayState == true) ? "LOCKED" : "WAITING_SPEED";
              
              String alertMsg = "ALERT," + 
                               String(currentLat, 6) + "," + 
                               String(currentLng, 6) + "," + 
                               String(currentAlt, 2) + "," + 
                               String(currentSpeed, 2) + "," + 
                               String(satCount) + "," + 
                               String(distance, 2) + "," + 
                               motorStatus;
              publishMessageIfConnected(topicAlert, alertMsg);
              Serial.println("Alert sent!");
              alertSent = true;
              
              lastPublish = currentMillis;
            }
            
            if (currentMillis - lastPublish >= publishInterval) {
              lastPublish = currentMillis;
              String msg = "OUTSIDE," + 
                          String(currentLat, 6) + "," + 
                          String(currentLng, 6) + "," + 
                          String(currentAlt, 2) + "," + 
                          String(currentSpeed, 2) + "," + 
                          String(satCount) + "," + 
                          String(distance, 2);
              publishMessageIfConnected(topicData, msg);
            }
            
            String statusMsg = (!waitingForSpeed && relayState == true) ? "LUAR ZONA (Relay OFF - Motor Lock)" : 
                                            "LUAR ZONA (Relay OFF, Waiting Speed)";
            Serial.print("Status: ");
            Serial.println(statusMsg);
            
          } else {
            if (isOutsideSafeZone) {
              Serial.println("\n*** KEMBALI KE ZONA AMAN ***");
              Serial.println(">>> STEP 1: Menyambung Relay <<<");
              
              isOutsideSafeZone = false;
              alertSent = false;
              waitingForSpeed = false;
              
              controlRelay(false);
              
              Serial.println(">>> MOTOR NORMAL KEMBALI <<<\n");
              
              lastPublish = currentMillis;
              String msg = "SAFE," + 
                          String(currentLat, 6) + "," + 
                          String(currentLng, 6) + "," + 
                          String(currentAlt, 2) + "," + 
                          String(currentSpeed, 2) + "," + 
                          String(satCount) + "," + 
                          String(distance, 2);
              publishMessageIfConnected(topicData, msg);
            }
            
            Serial.println("Status: DALAM ZONA (Motor Normal)");
            
            if (currentMillis - lastPublish >= publishInterval) {
              lastPublish = currentMillis;
              String msg = "NORMAL," + 
                          String(currentLat, 6) + "," + 
                          String(currentLng, 6) + "," + 
                          String(currentAlt, 2) + "," + 
                          String(currentSpeed, 2) + "," + 
                          String(satCount) + "," + 
                          String(distance, 2);
              publishMessageIfConnected(topicData, msg);
            }
          }
        } else {
          Serial.println("Status: MANUAL CONTROL");
        }
      }
      
      Serial.println("----------------");
      
    } else {
      Serial.println("GPS: Waiting for signal...");
    }
  }
  
  if (millis() > 10000 && gps.charsProcessed() < 10) {
    Serial.println("\n!!! WARNING: NO GPS DATA !!!");
    Serial.println("Check wiring!\n");
    delay(5000);
  }
}