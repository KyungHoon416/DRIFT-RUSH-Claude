class_name RaceManager
extends Node
## Owns race state: countdown, timer, lap managers, ranking, wrong-way,
## off-track recovery, finish/DNF policy and results.
##
## Tie policy: finish order is the order in which finish events are processed
## (frame order). Equal times (to the ms) keep that order.
## DNF policy: once the local player (offline) or the first kart (online host)
## finishes, the others get `finish_grace_sec` to finish; then they are DNF and
## ranked by progress behind all finishers.

signal countdown_tick(n: int)        # 3,2,1,0(=GO)
signal race_started
signal lap_completed(kart: KartController, lap: int, lap_time: float)
signal kart_finished(kart: KartController, rank: int, time: float)
signal race_finished(results: Array)
signal wrong_way_changed(kart: KartController, wrong: bool)
signal kart_respawned(kart: KartController)

enum State { IDLE, COUNTDOWN, RACING, FINISHED }

var track: TrackBuilder
var karts: Array[KartController] = []
var laps := 3
var state := State.IDLE
var race_time := 0.0
var countdown := 3.0
var finish_grace_sec := 15.0
var auto_finish_on_player := true
var authoritative := true            # false on network clients: results come from host
var stuck_respawn_sec := 3.0

var lap_managers: Dictionary = {}    # kart -> LapManager
var offsets: Dictionary = {}         # kart -> float
var progress_by_kart: Dictionary = {}
var wrong_way: Dictionary = {}       # kart -> bool
var _wrong_timer: Dictionary = {}
var _stuck_timer: Dictionary = {}
var _safe_offset: Dictionary = {}
var _outside_timer: Dictionary = {}
var _finish_counter := 0
var _grace_left := -1.0
var _last_tick := 4
var results: Array = []


func setup(t: TrackBuilder, kart_list: Array[KartController], lap_count: int) -> void:
	track = t
	karts = kart_list
	laps = lap_count
	for k in karts:
		var lm := LapManager.new(track.checkpoint_count, laps)
		lm.min_lap_time = track.length / 60.0
		lap_managers[k] = lm
		wrong_way[k] = false
		_wrong_timer[k] = 0.0
		_stuck_timer[k] = 0.0
		_safe_offset[k] = track.closest_offset(k.global_position)
	if not track.checkpoint_passed.is_connected(_on_checkpoint):
		track.checkpoint_passed.connect(_on_checkpoint)


func add_kart(k: KartController) -> void:
	karts.append(k)
	var lm := LapManager.new(track.checkpoint_count, laps)
	lm.min_lap_time = track.length / 60.0
	lap_managers[k] = lm
	wrong_way[k] = false
	_wrong_timer[k] = 0.0
	_stuck_timer[k] = 0.0
	_safe_offset[k] = track.closest_offset(k.global_position)


func start_countdown(seconds := 3.0) -> void:
	state = State.COUNTDOWN
	countdown = seconds
	_last_tick = int(ceil(seconds)) + 1
	for k in karts:
		k.control_enabled = false


func start_race_now() -> void:
	state = State.RACING
	race_time = 0.0
	for k in karts:
		if not k.is_remote:
			k.control_enabled = true
		lap_managers[k].lap_start_time = 0.0
	countdown_tick.emit(0)
	race_started.emit()


func _physics_process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			countdown -= delta
			var n := int(ceil(countdown))
			if n < _last_tick and n > 0:
				_last_tick = n
				countdown_tick.emit(n)
			if countdown <= 0.0:
				start_race_now()
		State.RACING:
			race_time += delta
			_update_karts(delta)
			if _grace_left > 0.0:
				_grace_left -= delta
				if _grace_left <= 0.0 and authoritative:
					_finalize()
		_:
			pass


func _update_karts(delta: float) -> void:
	for k in karts:
		if not is_instance_valid(k):
			continue
		var lm: LapManager = lap_managers[k]
		var off := track.closest_offset(k.global_position)
		offsets[k] = off
		progress_by_kart[k] = lm.progress(off, track.length)
		if k.is_remote:
			continue
		# Off-road detection (grass beyond kerbs) and safe point tracking.
		var lat := absf(track.lateral_distance(k.global_position, off))
		k.offroad = lat > track.half_width() + TrackBuilder.KERB_W + 0.3
		# Safety net: centre beyond the wall line = escaped the track → recover.
		if lat > track.half_width() + TrackBuilder.KERB_W + 0.6:
			_outside_timer[k] = float(_outside_timer.get(k, 0.0)) + delta
			if float(_outside_timer[k]) > 0.5:
				_outside_timer[k] = 0.0
				respawn(k)
				continue
		else:
			_outside_timer[k] = 0.0
		if not k.offroad and k.is_on_floor():
			_safe_offset[k] = off
		# Wrong way
		if not lm.finished:
			var tan := track.tangent_at(off)
			var vel := Vector3(k.velocity.x, 0.0, k.velocity.z)
			var moving_back := vel.length() > 4.0 and vel.normalized().dot(tan) < -0.5
			var facing_back := k.forward().dot(tan) < -0.6
			if moving_back or (facing_back and vel.length() > 1.0):
				_wrong_timer[k] = float(_wrong_timer[k]) + delta
			else:
				_wrong_timer[k] = 0.0
			var ww := float(_wrong_timer[k]) > 1.0
			if ww != bool(wrong_way[k]):
				wrong_way[k] = ww
				wrong_way_changed.emit(k, ww)
		# Manual recovery (R key / pad Back), at most every 2 s.
		if k.respawn_request:
			k.respawn_request = false
			if k.invulnerable_timer <= 0.0:
				respawn(k)
				continue
		# Fell off the world / stuck → respawn at last safe point.
		var fell := k.global_position.y < track.min_y - 6.0
		if k.control_enabled and not k.brake_input and k.spin_timer <= 0.0 and absf(k.speed) < 1.5:
			_stuck_timer[k] = float(_stuck_timer[k]) + delta
		else:
			_stuck_timer[k] = 0.0
		if fell or float(_stuck_timer[k]) > stuck_respawn_sec:
			respawn(k)


func respawn(k: KartController) -> void:
	var off := float(_safe_offset.get(k, 0.0))
	k.respawn_at(track.transform_at(off - 2.0, 0.0))
	_stuck_timer[k] = 0.0
	_wrong_timer[k] = 0.0
	kart_respawned.emit(k)


func _on_checkpoint(k: KartController, idx: int) -> void:
	if state != State.RACING or not lap_managers.has(k):
		return
	var lm: LapManager = lap_managers[k]
	var res := lm.on_checkpoint(idx, race_time)
	match res:
		"lap":
			lap_completed.emit(k, lm.laps_done, lm.lap_times[-1])
		"finish":
			lap_completed.emit(k, lm.laps_done, lm.lap_times[-1])
			mark_finished(k, race_time)


func mark_finished(k: KartController, t: float) -> void:
	var lm: LapManager = lap_managers[k]
	if lm.finish_order > 0:
		return
	lm.finished = true
	lm.finish_time = t
	_finish_counter += 1
	lm.finish_order = _finish_counter
	kart_finished.emit(k, _finish_counter, t)
	var all_done := true
	for other in karts:
		if not lap_managers[other].finished:
			all_done = false
	if all_done:
		if authoritative:
			_finalize()
	elif _grace_left < 0.0 and (k.is_player or not auto_finish_on_player):
		_grace_left = finish_grace_sec


## Sorted karts: finishers by order, then others by progress (desc).
func standings() -> Array[KartController]:
	var arr: Array[KartController] = []
	for k in karts:
		if is_instance_valid(k):
			arr.append(k)
	arr.sort_custom(func(a: KartController, b: KartController) -> bool:
		var la: LapManager = lap_managers[a]
		var lb: LapManager = lap_managers[b]
		if la.finished != lb.finished:
			return la.finished
		if la.finished:
			return la.finish_order < lb.finish_order
		return float(progress_by_kart.get(a, -INF)) > float(progress_by_kart.get(b, -INF)))
	return arr


func rank_of(k: KartController) -> int:
	return standings().find(k) + 1


func _finalize() -> void:
	if state == State.FINISHED:
		return
	state = State.FINISHED
	results = []
	var order := standings()
	for i in order.size():
		var k := order[i]
		var lm: LapManager = lap_managers[k]
		if not lm.finished:
			lm.dnf = true
		results.append({
			"rank": i + 1, "name": k.display_name, "time": lm.finish_time if lm.finished else -1.0,
			"best_lap": lm.best_lap if lm.best_lap < INF else -1.0, "dnf": lm.dnf,
			"is_player": k.is_player, "peer_id": k.peer_id, "laps": lm.laps_done,
			"lap_times": lm.lap_times.duplicate(),
		})
	for k in karts:
		k.control_enabled = false
	race_finished.emit(results)


func force_finish() -> void:
	_finalize()
