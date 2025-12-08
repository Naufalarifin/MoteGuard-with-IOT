const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * Cloud Function untuk mengirim FCM ketika dokumen ALERT baru ditambahkan
 * ke collection `gps_data`.
 */
exports.sendAlertNotification = functions.firestore
  .document("gps_data/{docId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const docId = context.params.docId;

    if (data.status !== "ALERT") {
      console.log(`Document ${docId} status ${data.status}, skip notification`);
      return null;
    }

    const userId = data.userId;
    const distance = data.distance || "?";
    const radius = data.safeZoneRadius || "?";

    if (!userId) {
      console.error(`Document ${docId} tidak memiliki userId`);
      return null;
    }

    console.log(
      `Alert terdeteksi untuk user ${userId}, distance=${distance}, radius=${radius}`,
    );

    try {
      const userTokenDoc = await admin
        .firestore()
        .collection("user_tokens")
        .doc(userId)
        .get();

      if (!userTokenDoc.exists) {
        console.log(`Token FCM untuk user ${userId} tidak ditemukan`);
        return null;
      }

      const { fcmToken } = userTokenDoc.data() || {};
      if (!fcmToken) {
        console.log(`Token FCM kosong untuk user ${userId}`);
        return null;
      }

      const message = {
        token: fcmToken,
        notification: {
          title: "🚨 GPS Alert - Zone Breach!",
          body: `Device keluar safe zone! Jarak: ${distance}m | Radius: ${radius}m`,
        },
        android: {
          priority: "high",
          notification: {
            channelId: "gps_alert_channel",
            sound: "alert_ringtone",
            defaultSound: false,
            priority: "high",
            vibrateTimingsMillis: [0, 500, 200, 500, 200, 500],
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "alert_ringtone.mp3",
              badge: 1,
              alert: {
                title: "🚨 GPS Alert - Zone Breach!",
                body: `Device keluar safe zone! Jarak: ${distance}m | Radius: ${radius}m`,
              },
            },
          },
        },
        data: {
          type: "gps_alert",
          distance: distance.toString(),
          radius: radius.toString(),
          timestamp: new Date().toISOString(),
        },
      };

      const response = await admin.messaging().send(message);
      console.log(`FCM alert terkirim ke user ${userId}:`, response);
      return response;
    } catch (error) {
      console.error(`Gagal mengirim FCM alert ke user ${userId}:`, error);
      return null;
    }
  });

/**
 * Cloud Function untuk notifikasi vibration.
 */
exports.sendVibrationNotification = functions.firestore
  .document("vibration_data/{docId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const docId = context.params.docId;
    const userId = data.userId;

    if (!userId) {
      console.error(`Document ${docId} tidak memiliki userId`);
      return null;
    }

    try {
      const userTokenDoc = await admin
        .firestore()
        .collection("user_tokens")
        .doc(userId)
        .get();

      if (!userTokenDoc.exists) {
        console.log(`Token FCM untuk user ${userId} tidak ditemukan`);
        return null;
      }

      const { fcmToken } = userTokenDoc.data() || {};
      if (!fcmToken) {
        console.log(`Token FCM kosong untuk user ${userId}`);
        return null;
      }

      const message = {
        token: fcmToken,
        notification: {
          title: "⚠️ Vibration Detected!",
          body: "Getaran terdeteksi pada motor Anda!",
        },
        android: {
          priority: "high",
          notification: {
            channelId: "vibration_alert_channel",
            priority: "high",
          },
        },
        data: {
          type: "vibration_alert",
          timestamp: new Date().toISOString(),
        },
      };

      const response = await admin.messaging().send(message);
      console.log(`FCM vibration terkirim ke user ${userId}:`, response);
      return response;
    } catch (error) {
      console.error(`Gagal mengirim FCM vibration ke user ${userId}:`, error);
      return null;
    }
  });
