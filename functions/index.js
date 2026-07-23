const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onRequest} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const crypto = require("crypto");

admin.initializeApp();

// ─────────────────────────────────────────────────────────────────
// Triggered when a new alert is created in Firestore
// Sends FCM push notification to all devices in the same company
// ─────────────────────────────────────────────────────────────────
exports.onAlertCreated = onDocumentCreated("alerts/{alertId}", async (event) => {
  const snap = event.data;
  if (!snap) return;

  const alert = snap.data();
  const companyId = alert.companyId;
  const userName = alert.userName || "Rider";
  const helpType = alert.helpType || "SOS";
  const lat = alert.lat || 0;
  const lng = alert.lng || 0;
  const customMessage = alert.customMessage || "";
  const isUrgent = helpType === "SOS" || helpType === "CRASH";

  if (!companyId) {
    console.log("No companyId on alert, skipping");
    return;
  }

  // Build notification title and body
  let title;
  let body;
  switch (helpType) {
    case "CRASH":
      title = `CRASH DETECTED — ${userName}`;
      body = "May be injured. Open app to respond.";
      break;
    case "LOST":
      title = `RIDER LOST — ${userName}`;
      body = "Needs directions. Open app to respond.";
      break;
    case "FUEL":
      title = `FUEL REQUEST — ${userName}`;
      body = "Has run out of fuel. Open app to respond.";
      break;
    case "BREAKDOWN":
      title = `BREAKDOWN — ${userName}`;
      body = "Needs mechanical help. Open app to respond.";
      break;
    case "MEDICAL":
      title = `MEDICAL EMERGENCY — ${userName}`;
      body = "Needs medical help. Open app to respond.";
      break;
    case "OTHER":
      title = `HELP NEEDED \u2014 ${userName}`;
      body = customMessage || "Needs assistance. Open app to respond.";
      break;
    default:
      title = `EMERGENCY SOS — ${userName}`;
      body = "Needs urgent help. Open app to respond.";
  }

  const mapsLink = `https://www.google.com/maps?q=${lat},${lng}`;

  // Get all devices in the company
  const devicesSnap = await admin.firestore()
      .collection("devices")
      .where("companyId", "==", companyId)
      .get();

  if (devicesSnap.empty) {
    console.log("No devices found for company:", companyId);
    return;
  }

  // Collect FCM tokens
  const tokens = [];
  const tokenDeviceIds = [];
  devicesSnap.forEach((doc) => {
    const token = doc.data().fcmToken;
    if (token) {
      tokens.push(token);
      tokenDeviceIds.push(doc.id);
    }
  });

  if (tokens.length === 0) {
    console.log("No FCM tokens found for company:", companyId);
    return;
  }

  console.log(`Sending FCM to ${tokens.length} devices for ${companyId}`);

  // Send to all devices
  const message = {
    notification: {
      title: title,
      body: body,
    },
    data: {
      alertId: event.params.alertId,
      companyId: companyId,
      lat: lat.toString(),
      lng: lng.toString(),
      mapsLink: mapsLink,
      helpType: helpType,
      userName: userName,
    },
    android: {
      priority: "high",
      notification: {
        channelId: "sos_alerts",
        priority: isUrgent ? "max" : "high",
        ...(isUrgent ? {sound: "siren", defaultSound: false} : {defaultSound: true}),
      },
    },
    tokens: tokens,
  };

  try {
    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(`FCM sent: ${response.successCount} success, ${response.failureCount} failures`);
    response.responses.forEach((resp, i) => {
      if (!resp.success) {
        console.error(`FCM failed for device ${tokenDeviceIds[i]}: ${resp.error && resp.error.code} - ${resp.error && resp.error.message}`);
      }
    });
  } catch (error) {
    console.error("FCM send error:", error);
  }
});

// ─────────────────────────────────────────────────────────────────
// Clean up old notifications every hour
// ─────────────────────────────────────────────────────────────────
exports.onAlertUpdated = onDocumentUpdated("alerts/{alertId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!before || !after) return;

  const companyId = after.companyId;
  if (!companyId) {
    console.log("No companyId on updated alert, skipping");
    return;
  }

  let title = null;
  let body = null;
  let excludeDeviceId = null;

  if (before.status !== "RESOLVED" && after.status === "RESOLVED") {
    title = "Alert Update";
    body = `Alert resolved by ${after.resolvedBy || "an officer"}.`;
    excludeDeviceId = after.resolvedByDeviceId || null;
  } else {
    const beforeResponders = before.responders || [];
    const afterResponders = after.responders || [];
    if (afterResponders.length > beforeResponders.length) {
      const beforeIds = new Set(beforeResponders.map((r) => r.deviceId));
      const newResponder = afterResponders.find((r) => !beforeIds.has(r.deviceId));
      if (newResponder) {
        title = "Alert Update";
        body = `${newResponder.name || "Someone"} is responding to the alert.`;
        excludeDeviceId = newResponder.deviceId;
      }
    }
  }

  if (!title) return;

  const devicesSnap = await admin.firestore()
      .collection("devices")
      .where("companyId", "==", companyId)
      .get();

  if (devicesSnap.empty) {
    console.log("No devices found for company:", companyId);
    return;
  }

  const tokens = [];
  const tokenDeviceIds = [];
  devicesSnap.forEach((doc) => {
    if (doc.id === excludeDeviceId) return;
    const token = doc.data().fcmToken;
    if (token) {
      tokens.push(token);
      tokenDeviceIds.push(doc.id);
    }
  });

  if (tokens.length === 0) {
    console.log("No FCM tokens to notify for update:", companyId);
    return;
  }

  console.log(`Sending update FCM to ${tokens.length} devices for ${companyId}`);

  const message = {
    notification: {
      title: title,
      body: body,
    },
    data: {
      alertId: event.params.alertId,
      companyId: companyId,
    },
    android: {
      priority: "high",
      notification: {
        channelId: "sos_alerts",
        priority: "high",
      },
    },
    tokens: tokens,
  };

  try {
    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(`Update FCM sent: ${response.successCount} success, ${response.failureCount} failures`);
    response.responses.forEach((resp, i) => {
      if (!resp.success) {
        console.error(`Update FCM failed for device ${tokenDeviceIds[i]}: ${resp.error && resp.error.code} - ${resp.error && resp.error.message}`);
      }
    });
  } catch (error) {
    console.error("Update FCM send error:", error);
  }
});

exports.cleanupNotifications = onSchedule("every 60 minutes", async () => {
  const cutoff = new Date(Date.now() - 60 * 60 * 1000);
  const snap = await admin.firestore()
      .collection("notifications")
      .where("delivered", "==", true)
      .where("createdAt", "<", cutoff)
      .get();
  const batch = admin.firestore().batch();
  snap.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
  console.log(`Cleaned up ${snap.size} old notifications`);
});

// ─────────────────────────────────────────────────────────────────────────────
// PAYFAST ITN (Instant Transaction Notification) - SKELETON ONLY
// Just logs incoming notifications for now. No signature
// verification or Firestore updates yet - deliberately left for
// a dedicated session, since that part is security-sensitive.
// ─────────────────────────────────────────────────────────────────────────────
// Encodes a string exactly the way PHP's urlencode() does, since
// JavaScript's encodeURIComponent leaves ! ' ( ) * ~ unencoded, while
// PHP encodes them. This mismatch is a common cause of PayFast
// signature failures when porting PHP reference code to Node.js.
function phpUrlEncode(str) {
  return encodeURIComponent(str)
      .replace(/%20/g, "+")
      .replace(/[!'()*~]/g, (c) => "%" + c.charCodeAt(0).toString(16).toUpperCase());
}

// Rebuilds PayFast's signature exactly per their documented algorithm:
// https://developers.payfast.co.za/docs#step_2_signature
// 1. Concatenate non-blank fields as key=value&key2=value2... in the
//    ORDER RECEIVED (not alphabetical - that's the separate API format).
// 2. Append &passphrase=... if a passphrase is set.
// 3. MD5 hash the result.
function generatePayfastSignature(data, passphrase) {
  let pfOutput = "";
  for (const key of Object.keys(data)) {
    if (key === "signature") continue;
    const val = data[key];
    if (val !== undefined && val !== null && String(val) !== "") {
      pfOutput += `${key}=${phpUrlEncode(String(val).trim())}&`;
    }
  }
  let getString = pfOutput.slice(0, -1);
  if (passphrase) {
    getString += `&passphrase=${phpUrlEncode(passphrase.trim())}`;
  }
  return crypto.createHash("md5").update(getString).digest("hex");
}

exports.payfastItn = onRequest(async (req, res) => {
  try {
    const receivedSignature = req.body.signature;
    // TODO: move to Firebase secret manager before going live -
    // hardcoded here only for sandbox testing.
    const passphrase = "dOors1024567";
    const expectedSignature = generatePayfastSignature(req.body, passphrase);

    if (receivedSignature !== expectedSignature) {
      console.error("PayFast ITN signature mismatch", {
        received: receivedSignature,
        expected: expectedSignature,
        body: req.body,
      });
      res.status(400).send("Invalid signature");
      return;
    }

    console.log("PayFast ITN verified successfully:", JSON.stringify(req.body));
    // No Firestore updates yet - that's the next step, once signature
    // verification itself has been confirmed working in sandbox.
    res.status(200).send("OK");
  } catch (e) {
    console.error("PayFast ITN error:", e);
    res.status(500).send("Error");
  }
});
