class_name TiltSteering
extends RefCounted
## Converts the device gravity vector into a steering value in [-1, 1].
##
## Godot API: Input.get_gravity() / Input.get_accelerometer() return Vector3.
## On desktop they return Vector3.ZERO → has_sensor() is false and keyboard /
## touch steering must be used.
##
## Landscape steering = rotating the phone like a wheel (around the screen
## normal). The roll angle is measured from the gravity component on the
## selected screen axis and is independent of how far the phone is tipped back:
##     roll = atan2(g[axis], sqrt(g.other^2 + g.z^2))
## Axis/sign conventions differ per platform/device/orientation → "axis" and
## "invert" options plus neutral calibration. MUST be verified on real devices
## (see Docs/QA_REPORT.md: 실기기 미검증).

var sensitivity := 1.0
var deadzone_deg := 3.0
var max_angle_deg := 28.0
var smoothing := 0.08
var invert := false
var axis := "x"
var neutral_deg := 0.0

var raw_deg := 0.0
var value := 0.0
var _suppress := 0.0


func load_from_settings() -> void:
	sensitivity = float(SaveSettings.get_value("tilt_sensitivity"))
	deadzone_deg = float(SaveSettings.get_value("tilt_deadzone_deg"))
	max_angle_deg = float(SaveSettings.get_value("tilt_max_angle_deg"))
	smoothing = float(SaveSettings.get_value("tilt_smoothing"))
	invert = bool(SaveSettings.get_value("tilt_invert"))
	axis = String(SaveSettings.get_value("tilt_axis"))
	neutral_deg = float(SaveSettings.get_value("tilt_neutral_deg"))


static func has_sensor(g: Vector3) -> bool:
	return g.length() > 1.0


static func roll_deg(g: Vector3, use_axis := "x") -> float:
	if g.length() < 0.001:
		return 0.0
	var a := g.x if use_axis == "x" else g.y
	var b := g.y if use_axis == "x" else g.x
	return rad_to_deg(atan2(a, sqrt(b * b + g.z * g.z)))


## Pure mapping (no smoothing) from a roll angle to steering.
func map_angle(angle_deg: float) -> float:
	var rel := wrapf(angle_deg - neutral_deg, -180.0, 180.0)
	if invert:
		rel = -rel
	var mag := absf(rel)
	if mag <= deadzone_deg:
		return 0.0
	var span := maxf(1.0, max_angle_deg - deadzone_deg)
	var v := (mag - deadzone_deg) / span * sensitivity
	return clampf(signf(rel) * v, -1.0, 1.0)


## Call every physics frame with Input.get_gravity().
func update(g: Vector3, dt: float) -> float:
	if not has_sensor(g):
		value = move_toward(value, 0.0, dt * 4.0)
		return value
	raw_deg = roll_deg(g, axis)
	var target := map_angle(raw_deg)
	if _suppress > 0.0:
		# After resume / rotation: ease in to avoid a sudden swerve.
		_suppress -= dt
		target = 0.0
	if smoothing <= 0.0:
		value = target
	else:
		value = lerpf(value, target, 1.0 - exp(-dt / smoothing))
	return value


func calibrate(g: Vector3) -> void:
	neutral_deg = roll_deg(g, axis)


## Called on app resume, orientation change or unpause.
func reset_smoothing(suppress_sec := 0.3) -> void:
	value = 0.0
	_suppress = suppress_sec
