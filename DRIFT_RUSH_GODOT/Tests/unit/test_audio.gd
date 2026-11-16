extends TestCase
## Synthesized sound set: every cue exists, loops are seamless, engine follows speed.

const CUES := ["ui_click", "beep", "go", "wall", "kart", "item", "boost", "drift_boost_1", "drift_boost_2",
	"drift_boost_3", "drift_tier_1", "drift_tier_2", "pickup", "missile", "shield", "trap", "respawn",
	"lap", "final_lap", "finish", "wrong_way", "engine_lo", "engine_hi", "roar", "drift"]


func test_all_cues_exist_and_are_not_silent() -> void:
	for c in CUES:
		var w: AudioStreamWAV = AudioFeedback.streams.get(c)
		check(w != null, "cue %s exists" % c)
		if w == null:
			continue
		var peak := 0
		for i in range(0, w.data.size() - 1, 64):
			peak = maxi(peak, absi(w.data.decode_s16(i)))
		check(peak > 3000, "cue %s is audible (peak %d)" % [c, peak])


func test_loops_are_seamless() -> void:
	for c in ["engine_lo", "engine_hi", "roar", "drift"]:
		var w: AudioStreamWAV = AudioFeedback.streams[c]
		eq(w.loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s loops" % c)
		var n := w.data.size() / 2
		var first := w.data.decode_s16(0)
		var last := w.data.decode_s16((n - 1) * 2)
		# The seam may not jump more than the waveform itself does between samples
		# (saw harmonics have natural steps), i.e. no extra click at the loop point.
		var max_step := 0
		for i in range(1, n):
			max_step = maxi(max_step, absi(w.data.decode_s16(i * 2) - w.data.decode_s16((i - 1) * 2)))
		check(absi(first - last) <= max_step, "%s loop seam adds no click (|Δ| %d ≤ %d)" % [c, absi(first - last), max_step])


func test_engine_pitch_and_layers_follow_speed() -> void:
	AudioFeedback.set_engine(true, 0.0)
	var lo_idle: float = AudioFeedback._engine_lo.pitch_scale
	var hi_idle_db: float = AudioFeedback._engine_hi.volume_db
	AudioFeedback.set_engine(true, 1.0)
	check(AudioFeedback._engine_lo.pitch_scale > lo_idle + 0.4, "engine pitch rises with speed")
	check(AudioFeedback._engine_hi.volume_db > hi_idle_db + 20.0, "high-rev layer fades in at speed")
	AudioFeedback.set_engine(false)
	check(not AudioFeedback._engine_lo.playing, "engine stops")


func test_drift_boost_tiers_play_distinct_sounds() -> void:
	var before := AudioFeedback.plays
	for t in [1, 2, 3]:
		AudioFeedback._last_play_ms.clear()
		AudioFeedback.play_drift_boost(t)
	eq(AudioFeedback.plays - before, 3, "three tier sounds played")
	check(AudioFeedback.streams["drift_boost_3"].data.size() > AudioFeedback.streams["drift_boost_1"].data.size(), "higher tier = longer sound")
