'use strict';
// Pure room rules shared by Cloud Functions and unit tests.
// Mirrors Scripts/Backend/MockBackend.gd so the offline mock behaves the same.

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I
const MAX_PLAYERS = 8;

function generateCode(randomInt) {
  let s = '';
  for (let i = 0; i < 6; i++) s += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  return s;
}

function normalizeCode(code) {
  return String(code || '').trim().toUpperCase();
}

function isValidCode(code) {
  return /^[A-Z2-9]{6}$/.test(code) && [...code].every((c) => CODE_ALPHABET.includes(c));
}

function sanitizeCreateOptions(o = {}) {
  const num = (v, dflt) => (Number.isNaN(parseInt(v, 10)) ? dflt : parseInt(v, 10));
  const capacity = Math.min(MAX_PLAYERS, Math.max(2, num(o.capacity, MAX_PLAYERS)));
  const laps = Math.min(5, Math.max(1, num(o.laps, 3)));
  const mode = ['speed', 'item'].includes(o.mode) ? o.mode : 'speed';
  const map = ['sakura_valley', 'neon_city'].includes(o.map) ? o.map : 'sakura_valley';
  return { capacity, laps, mode, map, public: Boolean(o.public) };
}

function newRoom(hostUid, opts) {
  return { host: hostUid, members: [hostUid], ready: {}, started: false, ...sanitizeCreateOptions(opts) };
}

// Returns null when joining is allowed, otherwise an error code.
function joinError(room, uid) {
  if (!room) return 'ROOM_NOT_FOUND';
  if (room.members.includes(uid)) return 'ALREADY_IN_ROOM';
  if (room.started) return 'RACE_STARTED';
  if (room.members.length >= room.capacity) return 'ROOM_FULL';
  return null;
}

function applyJoin(room, uid) {
  return { ...room, members: [...room.members, uid] };
}

// Returns the updated room, or null when the room should be deleted.
function applyLeave(room, uid) {
  const members = room.members.filter((m) => m !== uid);
  if (members.length === 0) return null;
  const ready = { ...room.ready };
  delete ready[uid];
  const host = room.host === uid ? members[0] : room.host; // host migration
  return { ...room, members, ready, host };
}

function startError(room, uid) {
  if (!room) return 'ROOM_NOT_FOUND';
  if (room.host !== uid) return 'NOT_HOST';
  if (room.started) return 'RACE_STARTED';
  if (room.members.length < 2) return 'NOT_ENOUGH_PLAYERS';
  const notReady = room.members.filter((m) => m !== room.host && !room.ready[m]);
  if (notReady.length > 0) return 'NOT_ALL_READY';
  return null;
}

// Server-side plausibility check for a race result reported by the game server.
function validateResult(r, trackLengthM, laps) {
  const minLap = trackLengthM / 60; // > 216 km/h average is impossible
  if (!Array.isArray(r.lapTimes) || r.lapTimes.length !== laps) return 'BAD_LAPS';
  if (r.lapTimes.some((t) => typeof t !== 'number' || t < minLap)) return 'IMPOSSIBLE_LAP';
  const sum = r.lapTimes.reduce((a, b) => a + b, 0);
  if (Math.abs(sum - r.finishTime) > 0.5) return 'TIME_MISMATCH';
  return null;
}

module.exports = {
  CODE_ALPHABET, MAX_PLAYERS, generateCode, normalizeCode, isValidCode, sanitizeCreateOptions,
  newRoom, joinError, applyJoin, applyLeave, startError, validateResult,
};
