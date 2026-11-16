extends Node
## Vibration feedback. Autoload name: Haptics.
## - Uses Input.vibrate_handheld(duration_ms, amplitude) (Godot 4.7 API).
## - Android needs the VIBRATE permission (enabled in export_presets.cfg).
## - Global cooldown (default 300 ms) so scraping a wall does not buzz constantly.
## - Small impacts below MIN_STRENGTH are ignored (do not exaggerate).
## - Never sent over the network: each client vibrates for collision events it
##   receives/detects locally.

const MIN_STRENGTH := 0.15
const PATTERNS := {
	# kind: [min_ms, max_ms, amplitude_scale]
	"wall": [25, 90, 1.0],
	"kart": [20, 60, 0.75],
	"item": [80, 160, 1.0],
	"boost": [15, 30, 0.35],
	"ui": [10, 15, 0.25],
}

var cooldown_ms := 300
var last_event: Dictionary = {}     # for tests / debug overlay
var events_fired := 0
var _last_fire_ms := -100000
## Optional time source for deterministic tests (returns msec).
var time_source: Callable


func _now_ms() -> int:
	if time_source.is_valid():
		return int(time_source.call())
	return Time.get_ticks_msec()


func is_supported() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios")


## Returns true when a vibration was requested (or would be, on desktop).
func impact(kind: String, strength: float) -> bool:
	if not bool(SaveSettings.get_value("vibration_enabled")):
		return false
	var user_scale := float(SaveSettings.get_value("vibration_strength"))
	if user_scale <= 0.0:
		return false
	strength = clampf(strength, 0.0, 1.0)
	if strength < MIN_STRENGTH and kind != "ui":
		return false
	var now := _now_ms()
	if now - _last_fire_ms < cooldown_ms:
		return false
	_last_fire_ms = now
	var p: Array = PATTERNS.get(kind, PATTERNS["wall"])
	var duration := int(lerpf(float(p[0]), float(p[1]), strength))
	var amplitude := clampf(strength * float(p[2]) * user_scale, 0.05, 1.0)
	last_event = {"kind": kind, "duration_ms": duration, "amplitude": amplitude, "time": now}
	events_fired += 1
	if is_supported():
		Input.vibrate_handheld(duration, amplitude)
	return true


func reset_cooldown() -> void:
	_last_fire_ms = -100000
