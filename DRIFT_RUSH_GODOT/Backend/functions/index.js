'use strict';
// DRIFT RUSH Cloud Functions (2nd gen). NOT deployed yet — see Docs/FIREBASE_SETUP.md.
// Firestore/RTDB hold accounts, rooms, presence and verified results only.
// Real-time race state goes over the ENet game server, never Firestore.

const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const crypto = require('crypto');
const rooms = require('./lib/rooms');

initializeApp();
const db = getFirestore();
const REGION = 'asia-northeast3';
const GAME_TOKEN_SECRET = defineSecret('GAME_TOKEN_SECRET');       // signs short-lived game-server join tokens
const GAME_SERVER_SECRET = defineSecret('GAME_SERVER_SECRET');     // authenticates the dedicated game server

const opts = { region: REGION, enforceAppCheck: false }; // enable App Check before launch

function requireAuth(req) {
  if (!req.auth) throw new HttpsError('unauthenticated', 'UNAUTHENTICATED');
  return req.auth.uid;
}

exports.createRoom = onCall(opts, async (req) => {
  const uid = requireAuth(req);
  const userRef = db.doc(`users/${uid}`);
  return db.runTransaction(async (tx) => {
    const user = await tx.get(userRef);
    if (user.exists && user.get('roomCode')) throw new HttpsError('failed-precondition', 'ALREADY_IN_ROOM');
    let code;
    for (let i = 0; i < 10; i++) {
      code = rooms.generateCode((n) => crypto.randomInt(n));
      const existing = await tx.get(db.doc(`rooms/${code}`));
      if (!existing.exists) break;
    }
    const room = rooms.newRoom(uid, req.data || {});
    tx.set(db.doc(`rooms/${code}`), { ...room, createdAt: FieldValue.serverTimestamp() });
    tx.set(userRef, { roomCode: code }, { merge: true });
    return { code, room };
  });
});

exports.joinRoom = onCall(opts, async (req) => {
  const uid = requireAuth(req);
  const code = rooms.normalizeCode(req.data && req.data.code);
  if (!rooms.isValidCode(code)) throw new HttpsError('invalid-argument', 'INVALID_CODE');
  return db.runTransaction(async (tx) => {
    const ref = db.doc(`rooms/${code}`);
    const snap = await tx.get(ref);
    const room = snap.exists ? snap.data() : null;
    const err = rooms.joinError(room, uid);
    if (err) throw new HttpsError('failed-precondition', err);
    const updated = rooms.applyJoin(room, uid);
    tx.update(ref, { members: updated.members });
    tx.set(db.doc(`users/${uid}`), { roomCode: code }, { merge: true });
    return { code, room: updated };
  });
});

exports.leaveRoom = onCall(opts, async (req) => {
  const uid = requireAuth(req);
  const userRef = db.doc(`users/${uid}`);
  return db.runTransaction(async (tx) => {
    const user = await tx.get(userRef);
    const code = user.exists ? user.get('roomCode') : null;
    if (!code) return { ok: true };
    const ref = db.doc(`rooms/${code}`);
    const snap = await tx.get(ref);
    if (snap.exists) {
      const updated = rooms.applyLeave(snap.data(), uid);
      if (updated) tx.set(ref, updated, { merge: true });
      else tx.delete(ref);
    }
    tx.set(userRef, { roomCode: FieldValue.delete() }, { merge: true });
    return { ok: true };
  });
});

exports.setReady = onCall(opts, async (req) => {
  const uid = requireAuth(req);
  const user = await db.doc(`users/${uid}`).get();
  const code = user.exists ? user.get('roomCode') : null;
  if (!code) throw new HttpsError('failed-precondition', 'NOT_IN_ROOM');
  await db.doc(`rooms/${code}`).update({ [`ready.${uid}`]: Boolean(req.data && req.data.ready) });
  return { ok: true };
});

// Host starts: validates and issues a short-lived signed token per player for the game server.
exports.startRace = onCall({ ...opts, secrets: [GAME_TOKEN_SECRET] }, async (req) => {
  const uid = requireAuth(req);
  const user = await db.doc(`users/${uid}`).get();
  const code = user.exists ? user.get('roomCode') : null;
  const ref = db.doc(`rooms/${code || '_'}`);
  const snap = await ref.get();
  const err = rooms.startError(snap.exists ? snap.data() : null, uid);
  if (err) throw new HttpsError('failed-precondition', err);
  const room = snap.data();
  const exp = Date.now() + 2 * 60 * 1000;
  const sessionId = crypto.randomUUID();
  const tokens = {};
  for (const m of room.members) {
    const payload = Buffer.from(JSON.stringify({ uid: m, room: code, sessionId, exp })).toString('base64url');
    const sig = crypto.createHmac('sha256', GAME_TOKEN_SECRET.value()).update(payload).digest('base64url');
    tokens[m] = `${payload}.${sig}`;
  }
  await ref.update({ started: true, sessionId });
  // Game server address comes from config once a UDP server is provisioned (cost approval needed).
  return { sessionId, token: tokens[uid], server: process.env.GAME_SERVER_ADDR || null };
});

// Called ONLY by the dedicated game server (shared secret), never by clients.
exports.reportRaceResult = onRequest({ ...opts, secrets: [GAME_SERVER_SECRET] }, async (req, res) => {
  if (req.method !== 'POST' || req.get('x-game-server-key') !== GAME_SERVER_SECRET.value()) {
    res.status(403).json({ error: 'FORBIDDEN' });
    return;
  }
  const { sessionId, roomCode, map, laps, trackLength, results } = req.body || {};
  if (!sessionId || !Array.isArray(results)) {
    res.status(400).json({ error: 'BAD_REQUEST' });
    return;
  }
  const batch = db.batch();
  for (const r of results) {
    const err = r.dnf ? null : rooms.validateResult(r, trackLength, laps);
    batch.set(db.doc(`results/${sessionId}/players/${r.uid}`), { ...r, verified: !err, rejectReason: err || null, map, roomCode });
    if (!err && !r.dnf) {
      batch.set(db.doc(`users/${r.uid}/records/${map}`), {
        bestRace: FieldValue.increment(0), lastRace: r.finishTime, updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
  }
  await batch.commit();
  res.json({ ok: true });
});

exports.listFriends = onCall(opts, async (req) => {
  const uid = requireAuth(req);
  const snap = await db.collection(`users/${uid}/friends`).limit(100).get();
  return { friends: snap.docs.map((d) => ({ uid: d.id, nickname: d.get('nickname') || '' })) };
});
