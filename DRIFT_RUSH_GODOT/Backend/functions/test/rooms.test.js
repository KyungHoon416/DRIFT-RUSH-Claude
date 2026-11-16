'use strict';
const test = require('node:test');
const assert = require('node:assert');
const r = require('../lib/rooms');

test('codes are 6 unambiguous chars', () => {
  let i = 0;
  const code = r.generateCode((n) => (i++ * 7) % n);
  assert.strictEqual(code.length, 6);
  assert.ok(r.isValidCode(code));
  assert.ok(!r.isValidCode('ABC0O1'));
  assert.strictEqual(r.normalizeCode(' a7f3k9 '), 'A7F3K9');
});

test('create options are clamped', () => {
  const o = r.sanitizeCreateOptions({ capacity: 99, laps: 0, mode: 'hack', map: 'x' });
  assert.deepStrictEqual([o.capacity, o.laps, o.mode, o.map], [8, 1, 'speed', 'sakura_valley']);
});

test('join errors: not found, duplicate, started, full', () => {
  assert.strictEqual(r.joinError(null, 'u'), 'ROOM_NOT_FOUND');
  let room = r.newRoom('h', { capacity: 2 });
  assert.strictEqual(r.joinError(room, 'h'), 'ALREADY_IN_ROOM');
  assert.strictEqual(r.joinError(room, 'g'), null);
  room = r.applyJoin(room, 'g');
  assert.strictEqual(r.joinError(room, 'x'), 'ROOM_FULL');
  assert.strictEqual(r.joinError({ ...room, started: true, capacity: 8 }, 'x'), 'RACE_STARTED');
});

test('leave migrates host and deletes empty rooms', () => {
  let room = r.applyJoin(r.newRoom('h', {}), 'g');
  room = r.applyLeave(room, 'h');
  assert.strictEqual(room.host, 'g');
  assert.strictEqual(r.applyLeave(room, 'g'), null);
});

test('start requires host, 2+ players, all ready', () => {
  let room = r.newRoom('h', {});
  assert.strictEqual(r.startError(room, 'h'), 'NOT_ENOUGH_PLAYERS');
  room = r.applyJoin(room, 'g');
  assert.strictEqual(r.startError(room, 'g'), 'NOT_HOST');
  assert.strictEqual(r.startError(room, 'h'), 'NOT_ALL_READY');
  room.ready.g = true;
  assert.strictEqual(r.startError(room, 'h'), null);
});

test('result validation rejects impossible laps', () => {
  assert.strictEqual(r.validateResult({ lapTimes: [33, 34, 33], finishTime: 100 }, 960, 3), null);
  assert.strictEqual(r.validateResult({ lapTimes: [5, 34, 33], finishTime: 72 }, 960, 3), 'IMPOSSIBLE_LAP');
  assert.strictEqual(r.validateResult({ lapTimes: [33, 34], finishTime: 67 }, 960, 3), 'BAD_LAPS');
  assert.strictEqual(r.validateResult({ lapTimes: [33, 34, 33], finishTime: 90 }, 960, 3), 'TIME_MISMATCH');
});
