extends Node
## Persistent user settings (ConfigFile at user://settings.cfg).
## Autoload name: SaveSettings. Corrupt/unreadable files fall back to defaults
## and are backed up, so the game always starts.

signal changed(key: String, value: Variant)
signal save_failed(error_code: int)

const SECTION := "settings"
const DEFAULTS := {
	# Steering
	"control_mode": "tilt",          # "tilt" | "touch"
	"tilt_sensitivity": 1.0,         # 0.5 ~ 2.0
	"tilt_deadzone_deg": 3.0,        # 0 ~ 10
	"tilt_max_angle_deg": 28.0,      # tilt angle that equals full lock
	"tilt_smoothing": 0.08,          # seconds (time constant)
	"tilt_invert": false,
	"tilt_axis": "x",                # "x" | "y"  (device-dependent, see Docs/GAMEPLAY_SPEC.md)
	"tilt_neutral_deg": 0.0,
	# Feedback
	"vibration_enabled": true,
	"vibration_strength": 1.0,       # 0 ~ 1
	"camera_shake": true,
	"bgm_volume": 0.55,
	"sfx_volume": 0.85,
	# Graphics
	"graphics_quality": "medium",    # "low" | "medium" | "high"
	"fps_target": 60,                # 30 | 60
	# Profile / local state
	"nickname": "",
	"kart_color": "orange",
	"selected_map": "sakura_valley",
	"tutorial_done": false,
	"best_laps": {},                 # map_id -> seconds (local, NOT server-verified)
	"best_races": {},                # map_id -> seconds (local, NOT server-verified)
	"key_bindings": {},              # action -> [physical keycodes] (PC re-binding)
	"controls_hint": true,           # show the keyboard help at race start (PC)
}

var path := "user://settings.cfg"
var data: Dictionary = {}
var last_load_error := OK
var last_save_error := OK


func _ready() -> void:
	load_settings()
	apply_runtime()


func load_settings(custom_path := "") -> int:
	if custom_path != "":
		path = custom_path
	data = DEFAULTS.duplicate(true)
	var cfg := ConfigFile.new()
	if not FileAccess.file_exists(path):
		last_load_error = OK
		return OK
	var err := cfg.load(path)
	last_load_error = err
	if err != OK:
		# Keep the broken file for debugging and continue with defaults.
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bak"))
		push_warning("SaveSettings: could not read %s (err %d) — using defaults" % [path, err])
		return err
	for key in DEFAULTS.keys():
		if cfg.has_section_key(SECTION, key):
			var v: Variant = cfg.get_value(SECTION, key)
			if typeof(v) == typeof(DEFAULTS[key]) or (typeof(DEFAULTS[key]) == TYPE_FLOAT and typeof(v) == TYPE_INT):
				data[key] = v
	_sanitize()
	return OK


func save_settings() -> int:
	var cfg := ConfigFile.new()
	for key in data.keys():
		cfg.set_value(SECTION, key, data[key])
	var err := cfg.save(path)
	last_save_error = err
	if err != OK:
		save_failed.emit(err)
	return err


func get_value(key: String) -> Variant:
	if data.has(key):
		return data[key]
	return DEFAULTS.get(key)


func set_value(key: String, value: Variant, persist := true) -> void:
	data[key] = value
	_sanitize()
	changed.emit(key, data[key])
	if key in ["graphics_quality", "fps_target", "bgm_volume", "sfx_volume"]:
		apply_runtime()
	if persist:
		save_settings()


func reset_to_defaults() -> void:
	data = DEFAULTS.duplicate(true)
	save_settings()
	apply_runtime()


func record_local_best(map_id: String, best_lap: float, race_time: float) -> void:
	var laps: Dictionary = data["best_laps"]
	var races: Dictionary = data["best_races"]
	if best_lap > 0.0 and (not laps.has(map_id) or best_lap < float(laps[map_id])):
		laps[map_id] = best_lap
	if race_time > 0.0 and (not races.has(map_id) or race_time < float(races[map_id])):
		races[map_id] = race_time
	save_settings()


func _sanitize() -> void:
	data["tilt_sensitivity"] = clampf(float(data["tilt_sensitivity"]), 0.5, 2.0)
	data["tilt_deadzone_deg"] = clampf(float(data["tilt_deadzone_deg"]), 0.0, 10.0)
	data["tilt_max_angle_deg"] = clampf(float(data["tilt_max_angle_deg"]), 10.0, 60.0)
	data["tilt_smoothing"] = clampf(float(data["tilt_smoothing"]), 0.0, 0.4)
	data["vibration_strength"] = clampf(float(data["vibration_strength"]), 0.0, 1.0)
	data["bgm_volume"] = clampf(float(data["bgm_volume"]), 0.0, 1.0)
	data["sfx_volume"] = clampf(float(data["sfx_volume"]), 0.0, 1.0)
	if data["control_mode"] not in ["tilt", "touch"]:
		data["control_mode"] = "tilt"
	if data["graphics_quality"] not in ["low", "medium", "high"]:
		data["graphics_quality"] = "medium"
	if int(data["fps_target"]) not in [30, 60]:
		data["fps_target"] = 60
	if data["tilt_axis"] not in ["x", "y"]:
		data["tilt_axis"] = "x"


## Applies engine-level settings (FPS cap, audio buses). 3D quality presets are
## applied by RaceWorld/TrackBuilder via GameFlow.quality_profile().
func apply_runtime() -> void:
	Engine.max_fps = int(data.get("fps_target", 60))
	_ensure_bus("BGM")
	_ensure_bus("SFX")
	_set_bus_volume("BGM", float(data.get("bgm_volume", 0.5)))
	_set_bus_volume("SFX", float(data.get("sfx_volume", 0.8)))


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, linear <= 0.001)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
