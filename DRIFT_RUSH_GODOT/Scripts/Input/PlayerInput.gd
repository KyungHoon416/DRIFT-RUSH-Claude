class_name PlayerInput
extends Node
## Local player driver. Steering priority: keyboard (A/D, ←/→) and on-screen
## touch arrows (they press the same actions) > device tilt (when
## control_mode == "tilt" and a gravity sensor reports data).

var kart: KartController
var tilt := TiltSteering.new()
var enabled := true
var sensor_available := false
var last_source := "none"
const KEY_STEER_IN := 6.5     # full lock in ~0.15 s
const KEY_STEER_OUT := 11.0   # back to centre in ~0.09 s
var _kb_steer := 0.0


func _ready() -> void:
	tilt.load_from_settings()
	SaveSettings.changed.connect(_on_setting_changed)


func _on_setting_changed(key: String, _v: Variant) -> void:
	if key.begins_with("tilt_") or key == "control_mode":
		tilt.load_from_settings()


func _physics_process(delta: float) -> void:
	if kart == null or not enabled:
		return
	var g := Input.get_gravity()
	sensor_available = TiltSteering.has_sensor(g)
	var raw := Input.get_axis("steer_left", "steer_right")
	# Keys are digital: ramp the wheel in (fast) and back to centre (faster)
	# so short taps give small corrections instead of full lock.
	var rate := KEY_STEER_IN if absf(raw) > absf(_kb_steer) and signf(raw) == signf(_kb_steer) or _kb_steer == 0.0 else KEY_STEER_OUT
	_kb_steer = move_toward(_kb_steer, raw, rate * delta)
	var kb := _kb_steer
	var steer := kb
	last_source = "keys/touch" if absf(kb) > 0.01 else "none"
	if absf(kb) < 0.01 and String(SaveSettings.get_value("control_mode")) == "tilt" and sensor_available:
		steer = tilt.update(g, delta)
		last_source = "tilt"
	kart.steer_input = steer
	kart.drift_input = Input.is_action_pressed("drift")
	kart.brake_input = Input.is_action_pressed("brake")
	if Input.is_action_just_pressed("boost"):
		kart.boost_request = true
	if Input.is_action_just_pressed("use_item"):
		kart.item_request = true
	if Input.is_action_just_pressed("respawn"):
		kart.respawn_request = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_UNPAUSED:
		tilt.reset_smoothing()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_all()


## Clears held touch actions (e.g. when the app goes to background).
func release_all() -> void:
	_kb_steer = 0.0
	for a in ["steer_left", "steer_right", "drift", "brake", "boost", "use_item"]:
		Input.action_release(a)
	if kart:
		kart.steer_input = 0.0
		kart.drift_input = false
		kart.brake_input = false
