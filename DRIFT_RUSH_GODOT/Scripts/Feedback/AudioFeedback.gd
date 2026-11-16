extends Node
## Procedurally synthesized SFX/BGM (no third-party audio assets needed).
## Autoload name: AudioFeedback. Buses "SFX"/"BGM" are created by SaveSettings.

const RATE := 22050

var streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _engine: AudioStreamPlayer
var _drift: AudioStreamPlayer
var _bgm: AudioStreamPlayer
var _last_play_ms: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	streams["ui_click"] = _tone(1200.0, 0.05, 0.25, "sine", 0.0)
	streams["beep"] = _tone(660.0, 0.18, 0.4, "square", 0.0)
	streams["go"] = _tone(990.0, 0.5, 0.45, "square", 0.0)
	streams["wall"] = _crash(0.32, 0.9, 90.0)
	streams["kart"] = _crash(0.18, 0.6, 160.0)
	streams["item"] = _crash(0.45, 0.9, 60.0)
	streams["boost"] = _sweep(220.0, 880.0, 0.7, 0.4)
	streams["mini_boost"] = _sweep(330.0, 760.0, 0.3, 0.3)
	streams["pickup"] = _arp([880.0, 1175.0, 1568.0], 0.07, 0.3)
	streams["lap"] = _arp([660.0, 880.0], 0.12, 0.35)
	streams["finish"] = _arp([523.0, 659.0, 784.0, 1046.0], 0.14, 0.4)
	streams["wrong_way"] = _tone(220.0, 0.3, 0.3, "square", 0.0)
	streams["engine"] = _engine_loop()
	streams["drift"] = _noise_loop(0.5, 0.18)
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_engine = AudioStreamPlayer.new()
	_engine.bus = "SFX"
	_engine.stream = streams["engine"]
	_engine.volume_db = -14.0
	add_child(_engine)
	_drift = AudioStreamPlayer.new()
	_drift.bus = "SFX"
	_drift.stream = streams["drift"]
	_drift.volume_db = -12.0
	add_child(_drift)
	_bgm = AudioStreamPlayer.new()
	_bgm.bus = "BGM"
	_bgm.volume_db = -10.0
	add_child(_bgm)


func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not streams.has(name):
		return
	# Light de-duplication: same sound within 60 ms is skipped.
	var now := Time.get_ticks_msec()
	if now - int(_last_play_ms.get(name, -1000)) < 60:
		return
	_last_play_ms[name] = now
	for p in _players:
		if not p.playing:
			p.stream = streams[name]
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return


func play_impact(kind: String, strength: float) -> void:
	play(kind if streams.has(kind) else "wall", linear_to_db(clampf(0.35 + strength, 0.2, 1.0)), randf_range(0.9, 1.1))


func set_engine(active: bool, speed_ratio := 0.0) -> void:
	if active and not _engine.playing:
		_engine.play()
	elif not active and _engine.playing:
		_engine.stop()
	_engine.pitch_scale = clampf(0.65 + speed_ratio * 1.25, 0.5, 2.4)


func set_drift(active: bool) -> void:
	if active and not _drift.playing:
		_drift.play()
	elif not active and _drift.playing:
		_drift.stop()


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


# ------------------------------------------------------------- synthesis
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


func _osc(kind: String, phase: float) -> float:
	match kind:
		"square":
			return 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		"saw":
			return fmod(phase, 1.0) * 2.0 - 1.0
		"tri":
			return absf(fmod(phase, 1.0) * 4.0 - 2.0) - 1.0
		_:
			return sin(phase * TAU)


func _tone(freq: float, dur: float, vol: float, kind: String, slide: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := minf(1.0, t * 200.0) * (1.0 - float(i) / n)
		ph += (freq + slide * t) / RATE
		s[i] = _osc(kind, ph) * vol * env
	return _wav(s)


func _crash(dur: float, vol: float, thump_freq: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 14.0)
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.35)
		var thump := sin(TAU * thump_freq * t * (1.0 - t)) * exp(-t * 20.0)
		s[i] = (lp * 0.7 + thump * 0.8) * vol * env
	return _wav(s)


func _sweep(f0: float, f1: float, dur: float, vol: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var k := float(i) / n
		var env := minf(1.0, k * 10.0) * (1.0 - k)
		ph += lerpf(f0, f1, k) / RATE
		s[i] = (_osc("saw", ph) * 0.5 + randf_range(-0.4, 0.4) * k) * vol * env
	return _wav(s)


func _arp(freqs: Array, step: float, vol: float) -> AudioStreamWAV:
	var per := int(step * RATE)
	var s := PackedFloat32Array()
	s.resize(per * freqs.size() + per)
	var ph := 0.0
	for j in freqs.size():
		for i in per * 2:
			var idx := j * per + i
			if idx >= s.size():
				break
			var env := (1.0 - float(i) / (per * 2))
			ph += float(freqs[j]) / RATE
			s[idx] += _osc("tri", ph) * vol * env * 0.8
	return _wav(s)


func _engine_loop() -> AudioStreamWAV:
	# 0.5 s loop of a low saw+square blend; pitch_scale tracks kart speed.
	var n := RATE / 2
	var s := PackedFloat32Array()
	s.resize(n)
	var base := 110.0 # integer number of cycles in loop for seamless looping
	for i in n:
		var t := float(i) / RATE
		var ph := base * t
		var rumble := sin(TAU * 27.0 * t) * 0.25
		s[i] = (_osc("saw", ph) * 0.35 + _osc("square", ph * 0.5) * 0.25 + rumble) * 0.6
	return _wav(s, true)


func _noise_loop(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var bp := 0.0
	var prev := 0.0
	for i in n:
		var w := randf_range(-1.0, 1.0)
		bp = lerpf(bp, w - prev, 0.5)
		prev = w
		var t := float(i) / RATE
		s[i] = (bp * 0.8 + sin(TAU * 1760.0 * t) * 0.15) * vol
	return _wav(s, true)


func _bgm_loop() -> AudioStreamWAV:
	# Upbeat 8-bar chiptune-ish loop, 128 BPM, synthesized at startup.
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
		var f_arp := 440.0 * pow(2.0, (arp_note - 69) / 12.0)
		var v := _osc("square", f_arp * t) * 0.12 * env
		var bass_note: int = ch[0] - 24
		v += _osc("tri", 440.0 * pow(2.0, (bass_note - 69) / 12.0) * t) * 0.22
		var ln: int = lead[(step / 2) % lead.size()]
		var lenv := exp(-fmod(t, beat) * 4.0)
		v += sin(TAU * 440.0 * pow(2.0, (ln - 69) / 12.0) * t) * 0.12 * lenv
		# hats
		if fmod(t, beat / 2.0) < 0.02:
			v += randf_range(-0.15, 0.15)
		s[i] = v * 0.7
	return _wav(s, true)
