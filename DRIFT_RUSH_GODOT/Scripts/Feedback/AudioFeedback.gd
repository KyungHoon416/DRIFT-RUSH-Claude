extends Node
## Procedurally synthesized sound (no third-party audio assets).
## Autoload name: AudioFeedback. Buses "SFX"/"BGM" are created by SaveSettings;
## a hard limiter on Master keeps stacked effects from clipping.
##
## Layers in a race:
##   engine  — two seamless loops (low idle rumble + high rev) cross-faded and
##             pitched by speed, extra "boost roar" layer while boosting
##   drift   — tyre-squeal loop, pitch/volume follow drift charge
##   one-shots — impacts, drift-boost tiers, items, countdown, laps, UI
##   3D      — every other kart carries a quiet positional engine loop

const RATE := 24000

var streams: Dictionary = {}
var listener_pos := Vector3.ZERO      # set by RaceWorld (player kart position)
var _players: Array[AudioStreamPlayer] = []
var _engine_lo: AudioStreamPlayer
var _engine_hi: AudioStreamPlayer
var _roar: AudioStreamPlayer
var _drift: AudioStreamPlayer
var _bgm: AudioStreamPlayer
var _last_play_ms: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _engine_on := false
var plays := 0                         # for tests


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1234
	_add_limiter()
	streams["ui_click"] = _ui_click()
	streams["beep"] = _countdown_beep(784.0, 0.22)
	streams["go"] = _go_chord()
	streams["wall"] = _wall_crash()
	streams["kart"] = _kart_bonk()
	streams["item"] = _explosion(0.7)
	streams["boost"] = _jet_whoosh(1.2, 0.55)
	streams["mini_boost"] = _jet_whoosh(0.45, 0.4)
	streams["drift_boost_1"] = _drift_boost(1)
	streams["drift_boost_2"] = _drift_boost(2)
	streams["drift_boost_3"] = _drift_boost(3)
	streams["drift_tier_1"] = _sparkle([1046.0, 1318.0], 0.06)
	streams["drift_tier_2"] = _sparkle([1318.0, 1568.0, 2093.0], 0.05)
	streams["pickup"] = _sparkle([784.0, 988.0, 1175.0, 1568.0], 0.055)
	streams["missile"] = _missile_launch()
	streams["shield"] = _shield()
	streams["trap"] = _trap_plop()
	streams["blocked"] = _sparkle([2093.0, 1568.0], 0.05)
	streams["respawn"] = _warp()
	streams["lap"] = _fanfare([[784.0], [1046.0]], 0.13)
	streams["final_lap"] = _fanfare([[659.0], [784.0], [988.0, 1318.0]], 0.14)
	streams["finish"] = _fanfare([[523.0, 659.0], [659.0, 784.0], [784.0, 988.0], [1046.0, 1318.0, 1568.0]], 0.18)
	streams["wrong_way"] = _buzzer()
	streams["engine_lo"] = _engine_loop(46.0, 0.0)
	streams["engine_hi"] = _engine_loop(92.0, 1.0)
	streams["roar"] = _roar_loop()
	streams["drift"] = _squeal_loop()
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_engine_lo = _loop_player("engine_lo", -9.0)
	_engine_hi = _loop_player("engine_hi", -60.0)
	_roar = _loop_player("roar", -60.0)
	_drift = _loop_player("drift", -10.0)
	_bgm = AudioStreamPlayer.new()
	_bgm.bus = "BGM"
	_bgm.volume_db = -11.0
	add_child(_bgm)


func _loop_player(stream_name: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	p.stream = streams[stream_name]
	p.volume_db = db
	add_child(p)
	return p


func _add_limiter() -> void:
	var master := AudioServer.get_bus_index("Master")
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			return
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	AudioServer.add_bus_effect(master, lim)


# ------------------------------------------------------------- playback API
func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not streams.has(sound):
		return
	# Same sound within 60 ms is skipped (avoids phasing on double events).
	var now := Time.get_ticks_msec()
	if now - int(_last_play_ms.get(sound, -1000)) < 60:
		return
	_last_play_ms[sound] = now
	var target: AudioStreamPlayer = null
	for p in _players:
		if not p.playing:
			target = p
			break
	if target == null:
		target = _players[0]   # steal the oldest voice
	target.stream = streams[sound]
	target.volume_db = volume_db
	target.pitch_scale = pitch
	target.play()
	plays += 1


## Distance-attenuated one-shot (other karts' items/crashes). Silent beyond 60 m.
func play_at(sound: String, pos: Vector3, volume_db := 0.0) -> void:
	var d := pos.distance_to(listener_pos)
	if d > 60.0:
		return
	play(sound, volume_db + linear_to_db(clampf(1.0 - d / 60.0, 0.05, 1.0)), _rng.randf_range(0.95, 1.05))


func play_impact(kind: String, strength: float) -> void:
	var s := kind if streams.has(kind) else "wall"
	play(s, linear_to_db(clampf(0.35 + strength * 0.8, 0.25, 1.0)), _rng.randf_range(0.9, 1.1) * (1.1 - strength * 0.2))


func play_drift_boost(tier: int) -> void:
	play("drift_boost_%d" % clampi(tier, 1, 3))


## Called every frame by RaceWorld with the player's state.
func set_engine(active: bool, speed_ratio := 0.0, boosting := false) -> void:
	if active != _engine_on:
		_engine_on = active
		for p in [_engine_lo, _engine_hi, _roar]:
			if active:
				p.play()
			else:
				p.stop()
	if not active:
		return
	var r := clampf(speed_ratio, 0.0, 1.6)
	_engine_lo.pitch_scale = 0.8 + r * 0.55
	_engine_hi.pitch_scale = 0.75 + r * 0.6
	var hi_mix := clampf((r - 0.25) / 0.6, 0.0, 1.0)
	_engine_lo.volume_db = linear_to_db(lerpf(0.55, 0.28, hi_mix))
	_engine_hi.volume_db = linear_to_db(maxf(0.001, hi_mix * 0.42))
	var target_roar := 0.4 if boosting else 0.0
	var cur := db_to_linear(_roar.volume_db)
	_roar.volume_db = linear_to_db(maxf(0.001, move_toward(cur, target_roar, 0.05)))
	_roar.pitch_scale = 0.9 + r * 0.3


func set_engine_simple(active: bool, speed_ratio := 0.0) -> void:
	set_engine(active, speed_ratio, false)


## Drift squeal; charge 0..1 raises pitch (and tier ticks are separate one-shots).
func set_drift(active: bool, charge := 0.0) -> void:
	if active and not _drift.playing:
		_drift.play()
	elif not active and _drift.playing:
		_drift.stop()
	if active:
		_drift.pitch_scale = 0.9 + charge * 0.35
		_drift.volume_db = linear_to_db(0.32 + charge * 0.18)


func play_bgm(on: bool) -> void:
	if on and not _bgm.playing:
		if not streams.has("bgm"):
			streams["bgm"] = _bgm_loop()  # generated lazily (~15 s of audio)
			_bgm.stream = streams["bgm"]
		_bgm.play()
	elif not on:
		_bgm.stop()


func stop_race_loops() -> void:
	set_engine(false)
	set_drift(false)


## Quiet positional engine loop for another kart (bots / remote players).
func make_kart_engine_3d() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = streams["engine_hi"]
	p.bus = "SFX"
	p.volume_db = -14.0
	p.unit_size = 6.0
	p.max_distance = 45.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.autoplay = false
	return p


# ------------------------------------------------------------- synthesis helpers
func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _buf(sec: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(sec * RATE))
	return s


func _osc(kind: String, phase: float) -> float:
	var f := phase - floorf(phase)
	match kind:
		"square":
			return 1.0 if f < 0.5 else -1.0
		"saw":
			return f * 2.0 - 1.0
		"tri":
			return absf(f * 4.0 - 2.0) - 1.0
		_:
			return sin(phase * TAU)


## Make a loop seamless by cross-fading its tail into its head.
func _seamless(s: PackedFloat32Array, fade_sec := 0.05) -> PackedFloat32Array:
	var n := s.size()
	var f := int(fade_sec * RATE)
	var out := s.slice(0, n - f)
	for i in f:
		var w := float(i) / f
		out[i] = s[i] * w + s[n - f + i] * (1.0 - w)
	return out


func _normalize(s: PackedFloat32Array, peak := 0.9) -> PackedFloat32Array:
	var m := 0.0001
	for v in s:
		m = maxf(m, absf(v))
	for i in s.size():
		s[i] = s[i] / m * peak
	return s


## Simple resonant band-pass (state-variable filter) over a noise source.
class SVF:
	var low := 0.0
	var band := 0.0
	func process(x: float, f: float, q: float) -> float:
		low += f * band
		var high := x - low - q * band
		band += f * high
		return band


# ------------------------------------------------------------- engine / loops
func _engine_loop(fund: float, brightness: float) -> AudioStreamWAV:
	# fund must give an integer number of cycles in 0.5 s for a clean loop.
	var s := _buf(0.55)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var ph := fund * t
		var firing := pow(maxf(0.0, sin(TAU * ph * 2.0)), 6.0)       # cylinder pulses
		var body := sin(TAU * ph) * 0.5 + sin(TAU * ph * 2.0) * 0.35 + sin(TAU * ph * 3.0) * 0.2
		var buzz := _osc("saw", ph * 4.0) * (0.08 + brightness * 0.18)
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.08 + brightness * 0.2)
		s[i] = body * 0.6 + firing * 0.5 + buzz + lp * (0.05 + brightness * 0.08)
	return _wav(_normalize(_seamless(s), 0.8), true)


func _roar_loop() -> AudioStreamWAV:
	var s := _buf(0.65)
	var f := SVF.new()
	for i in s.size():
		var t := float(i) / RATE
		var n := _rng.randf_range(-1.0, 1.0)
		s[i] = f.process(n, 0.12, 0.6) * 0.8 + sin(TAU * 61.0 * t) * 0.25
	return _wav(_normalize(_seamless(s, 0.08), 0.8), true)


func _squeal_loop() -> AudioStreamWAV:
	var s := _buf(0.7)
	var f1 := SVF.new()
	var f2 := SVF.new()
	for i in s.size():
		var t := float(i) / RATE
		var n := _rng.randf_range(-1.0, 1.0)
		var wob := 1.0 + 0.04 * sin(TAU * 7.0 * t)
		var tone := sin(TAU * 1320.0 * wob * t) * 0.35 + sin(TAU * 2650.0 * wob * t) * 0.12
		s[i] = f1.process(n, 0.42, 0.25) * 0.7 + f2.process(n, 0.18, 0.4) * 0.3 + tone
	return _wav(_normalize(_seamless(s, 0.08), 0.75), true)


# ------------------------------------------------------------- one-shots
func _ui_click() -> AudioStreamWAV:
	var s := _buf(0.05)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = sin(TAU * 1800.0 * t) * exp(-t * 90.0) * 0.5 + sin(TAU * 900.0 * t) * exp(-t * 60.0) * 0.3
	return _wav(s)


func _countdown_beep(freq: float, dur: float) -> AudioStreamWAV:
	var s := _buf(dur)
	for i in s.size():
		var t := float(i) / RATE
		var env := minf(1.0, t * 300.0) * exp(-t * 6.0)
		s[i] = (sin(TAU * freq * t) * 0.6 + _osc("square", freq * t) * 0.15) * env
	return _wav(_normalize(s, 0.7))


func _go_chord() -> AudioStreamWAV:
	var s := _buf(0.8)
	for i in s.size():
		var t := float(i) / RATE
		var env := minf(1.0, t * 300.0) * exp(-t * 2.8)
		var v := 0.0
		for f in [1046.0, 1318.0, 1568.0, 2093.0]:
			v += sin(TAU * f * t) * 0.25 + _osc("square", f * t) * 0.04
		s[i] = v * env
	return _wav(_normalize(s, 0.75))


func _wall_crash() -> AudioStreamWAV:
	var s := _buf(0.6)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var thud_f := lerpf(110.0, 38.0, minf(1.0, t * 8.0))
		var thud := sin(TAU * thud_f * t) * exp(-t * 14.0)
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.25)
		var crunch := lp * exp(-t * 22.0)
		var clank := 0.0
		for p in [[523.0, 9.0], [1271.0, 12.0], [2213.0, 16.0], [3407.0, 20.0]]:
			clank += sin(TAU * float(p[0]) * t) * exp(-t * float(p[1]))
		s[i] = thud * 0.9 + crunch * 0.6 + clank * 0.18
	return _wav(_normalize(s, 0.95))


func _kart_bonk() -> AudioStreamWAV:
	var s := _buf(0.28)
	for i in s.size():
		var t := float(i) / RATE
		var f := lerpf(260.0, 120.0, minf(1.0, t * 10.0))
		s[i] = (sin(TAU * f * t) * 0.8 + _rng.randf_range(-1.0, 1.0) * 0.25 * exp(-t * 60.0)) * exp(-t * 16.0)
	return _wav(_normalize(s, 0.85))


func _explosion(dur: float) -> AudioStreamWAV:
	var s := _buf(dur)
	var f := SVF.new()
	for i in s.size():
		var t := float(i) / RATE
		var n := _rng.randf_range(-1.0, 1.0)
		var cut := lerpf(0.5, 0.04, minf(1.0, t * 3.0))
		var boom := sin(TAU * lerpf(70.0, 30.0, t / dur) * t) * exp(-t * 6.0)
		s[i] = (f.process(n, cut, 0.5) * 1.2 + boom) * exp(-t * 4.5) * minf(1.0, t * 400.0)
	return _wav(_normalize(s, 0.95))


func _jet_whoosh(dur: float, vol: float) -> AudioStreamWAV:
	var s := _buf(dur)
	var f := SVF.new()
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var k := t / dur
		var env := minf(1.0, k * 12.0) * pow(1.0 - k, 1.5)
		ph += lerpf(160.0, 720.0, k) / RATE
		var n := f.process(_rng.randf_range(-1.0, 1.0), lerpf(0.05, 0.35, k), 0.5)
		s[i] = (n * 0.9 + _osc("saw", ph) * 0.25 + sin(TAU * 55.0 * t) * 0.3 * (1.0 - k)) * env
	return _wav(_normalize(s, vol + 0.4))


func _drift_boost(tier: int) -> AudioStreamWAV:
	# whoosh + ascending chime, brighter and longer per tier
	var dur := 0.35 + 0.15 * tier
	var s := _buf(dur)
	var f := SVF.new()
	var notes: Array = [[880.0], [880.0, 1318.0], [880.0, 1318.0, 1760.0]][tier - 1]
	for i in s.size():
		var t := float(i) / RATE
		var k := t / dur
		var env := minf(1.0, k * 20.0) * (1.0 - k)
		var n := f.process(_rng.randf_range(-1.0, 1.0), lerpf(0.08, 0.45, k), 0.45)
		var chime := 0.0
		for j in notes.size():
			var start: float = j * 0.05
			if t > start:
				chime += sin(TAU * float(notes[j]) * (t - start)) * exp(-(t - start) * 8.0)
		s[i] = n * env * 0.8 + chime * 0.35 + sin(TAU * 70.0 * t) * exp(-t * 18.0) * 0.6
	return _wav(_normalize(s, 0.85))


func _sparkle(freqs: Array, step: float) -> AudioStreamWAV:
	var s := _buf(step * freqs.size() + 0.25)
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for j in freqs.size():
			var st := j * step
			if t >= st:
				var lt := t - st
				v += (sin(TAU * float(freqs[j]) * lt) + 0.3 * sin(TAU * float(freqs[j]) * 2.0 * lt)) * exp(-lt * 14.0)
		s[i] = v
	return _wav(_normalize(s, 0.6))


func _missile_launch() -> AudioStreamWAV:
	var s := _buf(0.6)
	var f := SVF.new()
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var k := t / 0.6
		ph += lerpf(300.0, 1200.0, k) / RATE
		var n := f.process(_rng.randf_range(-1.0, 1.0), 0.3, 0.4)
		s[i] = (_osc("saw", ph) * 0.35 + n * 0.6) * minf(1.0, k * 30.0) * (1.0 - k)
	return _wav(_normalize(s, 0.8))


func _shield() -> AudioStreamWAV:
	var s := _buf(0.7)
	for i in s.size():
		var t := float(i) / RATE
		var trem := 0.75 + 0.25 * sin(TAU * 14.0 * t)
		var v := sin(TAU * 880.0 * t) + sin(TAU * 1108.7 * t) * 0.8 + sin(TAU * 1318.5 * t) * 0.6
		s[i] = v * trem * minf(1.0, t * 40.0) * exp(-t * 3.5)
	return _wav(_normalize(s, 0.6))


func _trap_plop() -> AudioStreamWAV:
	var s := _buf(0.35)
	for i in s.size():
		var t := float(i) / RATE
		var f := lerpf(700.0, 180.0, minf(1.0, t * 6.0))
		s[i] = sin(TAU * f * t) * exp(-t * 11.0) + sin(TAU * 1500.0 * t) * exp(-t * 40.0) * 0.2
	return _wav(_normalize(s, 0.7))


func _warp() -> AudioStreamWAV:
	var s := _buf(0.5)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var k := t / 0.5
		ph += lerpf(1400.0, 300.0, k) / RATE
		s[i] = (_osc("tri", ph) * 0.6 + sin(TAU * ph * 1.5) * 0.3) * sin(PI * k)
	return _wav(_normalize(s, 0.6))


func _fanfare(steps: Array, step: float) -> AudioStreamWAV:
	var s := _buf(step * steps.size() + 0.45)
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for j in steps.size():
			var st := j * step
			if t >= st:
				var lt := t - st
				var last := j == steps.size() - 1
				var env := minf(1.0, lt * 200.0) * exp(-lt * (2.5 if last else 7.0))
				for f in steps[j]:
					v += (_osc("square", float(f) * lt) * 0.12 + sin(TAU * float(f) * lt) * 0.35) * env
		s[i] = v
	return _wav(_normalize(s, 0.75))


func _buzzer() -> AudioStreamWAV:
	var s := _buf(0.5)
	for i in s.size():
		var t := float(i) / RATE
		var gate := 1.0 if fmod(t, 0.25) < 0.17 else 0.0
		s[i] = (_osc("square", 196.0 * t) * 0.5 + _osc("saw", 98.0 * t) * 0.3) * gate * 0.6
	return _wav(s)


func _bgm_loop() -> AudioStreamWAV:
	# Upbeat 8-bar loop, 128 BPM, synthesized lazily on first use.
	var bpm := 128.0
	var beat := 60.0 / bpm
	var bars := 8
	var n := int(bars * 4 * beat * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var chords := [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]  # Am F C G
	var lead := [76, 74, 72, 74, 76, 79, 76, 74, 72, 71, 72, 74, 72, 69, 67, 69]
	var step_len := int(beat / 2.0 * RATE)
	for i in n:
		var t := float(i) / RATE
		var step := i / step_len
		var bar := int(t / (beat * 4.0)) % 4
		var ch: Array = chords[bar]
		var arp_note: int = ch[step % 3] - 12
		var ft := float(i % step_len) / RATE
		var env := exp(-ft * 9.0)
		var v := _osc("square", 440.0 * pow(2.0, (arp_note - 69) / 12.0) * t) * 0.1 * env
		var bass_note: int = ch[0] - 24
		v += _osc("tri", 440.0 * pow(2.0, (bass_note - 69) / 12.0) * t) * 0.22
		var ln: int = lead[(step / 2) % lead.size()]
		var lenv := exp(-fmod(t, beat) * 4.0)
		v += sin(TAU * 440.0 * pow(2.0, (ln - 69) / 12.0) * t) * 0.12 * lenv
		var bt := fmod(t, beat)
		v += sin(TAU * lerpf(90.0, 40.0, minf(1.0, bt * 12.0)) * bt) * exp(-bt * 18.0) * 0.35   # kick
		if fmod(t, beat / 2.0) < 0.02:
			v += _rng.randf_range(-0.12, 0.12)   # hat
		s[i] = v * 0.7
	return _wav(s, true)
