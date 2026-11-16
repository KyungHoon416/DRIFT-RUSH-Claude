class_name DriftSystem
extends RefCounted
## Pure drift state machine (no scene dependency → unit-testable).
## Drift starts when DRIFT is held + steering beyond min_steer + speed >= min_speed
## while grounded. Releasing DRIFT ends it; charge decides the mini-boost tier.

var min_speed := 12.0
var min_steer := 0.3
var charge_rate := 0.55

var drifting := false
var direction := 0       # -1 left, +1 right (sign of steer at drift start)
var charge := 0.0        # 0..1 while drifting
var time := 0.0
var last_charge := 0.0
var last_time := 0.0
## Minimum drift time that already earns the instant (tier 1) boost.
var min_reward_time := 0.3


func configure(stats: Dictionary) -> void:
	min_speed = float(stats.get("drift_min_speed", min_speed))
	min_reward_time = float(stats.get("drift_boost_min_time", min_reward_time))
	min_steer = float(stats.get("drift_min_steer", min_steer))
	charge_rate = float(stats.get("drift_charge_rate", charge_rate))


## Returns "start", "end" or "".
func update(dt: float, held: bool, steer: float, speed: float, on_floor: bool) -> String:
	if not drifting:
		if held and on_floor and speed >= min_speed and absf(steer) >= min_steer:
			drifting = true
			direction = 1 if steer > 0.0 else -1
			charge = 0.0
			time = 0.0
			return "start"
		return ""
	if not held or speed < min_speed * 0.6:
		drifting = false
		last_charge = charge
		last_time = time
		return "end"
	time += dt
	# Steering into the drift charges faster than counter-steering.
	var into := clampf(steer * direction, -1.0, 1.0)
	charge = minf(1.0, charge + charge_rate * dt * (0.6 + 0.4 * into))
	return ""


func cancel() -> void:
	drifting = false
	charge = 0.0
	last_charge = 0.0
	last_time = 0.0


## Instant boost on drift release:
## 0 = none (tap < min_reward_time), 1 = BOOST, 2 = SUPER (charge ≥ 0.45), 3 = ULTRA (charge ≥ 0.9)
func reward_tier() -> int:
	if last_charge >= 0.9:
		return 3
	if last_charge >= 0.45:
		return 2
	if last_time >= min_reward_time:
		return 1
	return 0
