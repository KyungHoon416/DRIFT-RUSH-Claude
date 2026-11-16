class_name BoostSystem
extends RefCounted
## Timed speed boost (BOOST button, drift mini-boost, TURBO item).

var active := false
var remaining := 0.0
var bonus := 0.0
var kind := ""
var just_ended := false


func start(duration: float, bonus_speed: float, boost_kind: String) -> void:
	if active:
		remaining = maxf(remaining, duration)
		bonus = maxf(bonus, bonus_speed)
	else:
		remaining = duration
		bonus = bonus_speed
	active = true
	kind = boost_kind


## Advances the timer. Returns the current extra top speed (0 when inactive).
func update(dt: float) -> float:
	just_ended = false
	if not active:
		return 0.0
	remaining -= dt
	if remaining <= 0.0:
		active = false
		remaining = 0.0
		bonus = 0.0
		kind = ""
		just_ended = true
		return 0.0
	return bonus


func stop() -> void:
	if active:
		just_ended = true
	active = false
	remaining = 0.0
	bonus = 0.0
	kind = ""
