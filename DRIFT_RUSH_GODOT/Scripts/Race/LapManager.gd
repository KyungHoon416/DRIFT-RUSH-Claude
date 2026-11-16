class_name LapManager
extends RefCounted
## Per-kart lap/checkpoint bookkeeping (pure logic → unit-testable).
## Checkpoints must be passed in order 0,1,..,N-1, then 0 completes a lap.
## The first pass of checkpoint 0 (karts start behind the line) only arms lap 1.

var checkpoint_count := 8
var total_laps := 3
var laps_done := 0
var next_cp := 0
var crossed_start := false
var finished := false
var dnf := false
var finish_time := -1.0
var lap_start_time := 0.0
var lap_times: Array[float] = []
var best_lap := INF
var cps_passed := 0
var finish_order := 0
## Minimum plausible lap time (anti-cheat for network reports). 0 = disabled.
var min_lap_time := 0.0


func _init(cp_count := 8, laps := 3) -> void:
	checkpoint_count = cp_count
	total_laps = laps


## Returns "start", "checkpoint", "lap", "finish", "ignored" or "invalid".
func on_checkpoint(idx: int, t: float) -> String:
	if finished:
		return "ignored"
	if idx != next_cp:
		return "ignored"
	cps_passed += 1
	if idx == 0:
		if not crossed_start:
			crossed_start = true
			next_cp = 1 % checkpoint_count
			return "start"
		var lt := t - lap_start_time
		if min_lap_time > 0.0 and lt < min_lap_time:
			return "invalid"
		laps_done += 1
		lap_times.append(lt)
		best_lap = minf(best_lap, lt)
		lap_start_time = t
		next_cp = 1 % checkpoint_count
		if laps_done >= total_laps:
			finished = true
			finish_time = t
			return "finish"
		return "lap"
	next_cp = (idx + 1) % checkpoint_count
	return "checkpoint"


func current_lap() -> int:
	return mini(laps_done + 1, total_laps)


func current_lap_time(t: float) -> float:
	return t - lap_start_time


## Continuous race progress in metres (for ranking) given the kart's offset on
## the centre line and the track length.
func progress(offset: float, track_length: float) -> float:
	if finished:
		return total_laps * track_length + 1000000.0 - finish_order
	if not crossed_start:
		return offset - track_length if offset > track_length * 0.5 else offset
	var o := offset
	if next_cp == 1 % checkpoint_count and o > track_length * 0.75:
		o -= track_length    # just crossed the line, centre-line offset not wrapped yet
	elif next_cp == 0 and o < track_length * 0.25:
		o += track_length    # approaching the line from the last sector
	return laps_done * track_length + o
