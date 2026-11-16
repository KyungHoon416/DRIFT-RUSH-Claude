extends Node
## App-wide flow: scene routing, race configuration, input map, quality presets.
## Autoload name: GameFlow.

signal scene_changing(path: String)

const SCENES := {
	"bootstrap": "res://Scenes/App/Bootstrap.tscn",
	"login": "res://Scenes/UI/Login.tscn",
	"lobby": "res://Scenes/UI/Lobby.tscn",
	"mode_select": "res://Scenes/UI/ModeSelect.tscn",
	"room": "res://Scenes/UI/RoomLobby.tscn",
	"map_select": "res://Scenes/UI/MapSelect.tscn",
	"garage": "res://Scenes/UI/Garage.tscn",
	"tutorial": "res://Scenes/UI/TiltTutorial.tscn",
	"settings": "res://Scenes/UI/Settings.tscn",
	"profile": "res://Scenes/UI/Profile.tscn",
	"race": "res://Scenes/Race/RaceWorld.tscn",
	"result": "res://Scenes/UI/RaceResult.tscn",
}

const KART_COLORS := {
	"orange": Color(1.0, 0.42, 0.05),
	"sakura": Color(1.0, 0.45, 0.68),
	"neon_blue": Color(0.1, 0.55, 1.0),
	"lime": Color(0.45, 0.85, 0.15),
	"violet": Color(0.55, 0.25, 0.95),
	"white": Color(0.92, 0.93, 0.96),
}

const BOT_NAMES := ["LUNA", "METEOR", "SPARK", "BREEZE", "NOVA", "COMET", "RACER8"]

var maps: Dictionary = {}
var kart_stats: Dictionary = {}
var item_rules: Dictionary = {}

## Current race request. RaceWorld reads this.
## mode: "practice" (solo time attack) | "speed" | "item"
## online: false = offline vs bots, true = LAN/online session via Net autoload
var race_config := {
	"mode": "practice",
	"map": "sakura_valley",
	"laps": 3,
	"bots": 0,
	"online": false,
	"seed": 0,
}
var last_result: Dictionary = {}
var previous_scene := ""
var current_scene_key := ""
var ui_theme: Theme
## Test/demo flag: the local kart is driven by AIDriver (--autopilot).
var autopilot := false
## When true (automated tests) scene changes are recorded instead of executed.
var test_mode := false
var last_goto := ""
var cmdline: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		cmdline[kv[0]] = kv[1] if kv.size() > 1 else "true"
	autopilot = cmdline.has("autopilot")
	# Dev/demo shortcut: run RaceWorld.tscn directly with --mode=speed --bots=7 --map=neon_city --laps=1
	if cmdline.has("mode"):
		race_config["mode"] = cmdline["mode"]
	if cmdline.has("bots"):
		race_config["bots"] = int(cmdline["bots"])
	if cmdline.has("map"):
		race_config["map"] = cmdline["map"]
	if cmdline.has("laps"):
		race_config["laps"] = int(cmdline["laps"])
	maps = _load_json("res://Data/maps.json")
	kart_stats = _load_json("res://Data/kart_stats.json")
	item_rules = _load_json("res://Data/items.json")
	register_input_actions()
	ui_theme = preload("res://Scripts/UI/UITheme.gd").build()
	get_tree().root.theme = ui_theme
	get_tree().root.size_changed.connect(_on_root_resized)


func _load_json(p: String) -> Dictionary:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		push_error("GameFlow: missing data file %s" % p)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func get_kart_stats(id := "default") -> Dictionary:
	var base: Dictionary = kart_stats.get("default", {}).duplicate()
	if id != "default" and kart_stats.has(id):
		base.merge(kart_stats[id], true)
	return base


func kart_color(id: String) -> Color:
	return KART_COLORS.get(id, KART_COLORS["orange"])


func player_name() -> String:
	var n: String = SaveSettings.get_value("nickname")
	return n if n.strip_edges() != "" else "DRIFT_RUSH"


func goto(key: String) -> void:
	if not SCENES.has(key):
		push_error("GameFlow.goto: unknown scene key %s" % key)
		return
	previous_scene = current_scene_key
	current_scene_key = key
	last_goto = key
	if test_mode:
		return
	get_tree().paused = false
	scene_changing.emit(SCENES[key])
	get_tree().change_scene_to_file(SCENES[key])


func start_offline_race(mode: String, map_id: String, bots: int, laps := 3) -> void:
	race_config = {
		"mode": mode, "map": map_id, "laps": laps, "bots": clampi(bots, 0, 7),
		"online": false, "seed": randi(),
	}
	goto("race")


## ---------------------------------------------------------------- Input map
## Registered at runtime so the bindings are visible in one place and testable.
func register_input_actions() -> void:
	_bind("steer_left", [KEY_A, KEY_LEFT])
	_bind("steer_right", [KEY_D, KEY_RIGHT])
	_bind("brake", [KEY_S, KEY_DOWN])
	_bind("drift", [KEY_SPACE, KEY_SHIFT])
	_bind("boost", [KEY_W, KEY_UP, KEY_B])
	_bind("use_item", [KEY_E, KEY_CTRL])
	_bind("pause", [KEY_ESCAPE, KEY_P])
	_bind("respawn", [KEY_R])


func _bind(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


## ---------------------------------------------------------------- Quality
func quality_profile() -> Dictionary:
	match String(SaveSettings.get_value("graphics_quality")):
		"low":
			return {"name": "low", "shadows": false, "shadow_size": 1024, "particles": 0.4,
				"tree_density": 0.45, "glow": false, "fog": false, "msaa": Viewport.MSAA_DISABLED,
				"render_scale": 0.75, "decor_lights": false, "petals": false}
		"high":
			return {"name": "high", "shadows": true, "shadow_size": 4096, "particles": 1.0,
				"tree_density": 1.3, "glow": true, "fog": true, "msaa": Viewport.MSAA_2X,
				"render_scale": 1.0, "decor_lights": true, "petals": true}
		_:
			return {"name": "medium", "shadows": true, "shadow_size": 2048, "particles": 0.75,
				"tree_density": 1.0, "glow": true, "fog": true, "msaa": Viewport.MSAA_DISABLED,
				"render_scale": 1.0, "decor_lights": false, "petals": true}


func apply_viewport_quality(vp: Viewport) -> void:
	var q := quality_profile()
	vp.msaa_3d = q["msaa"]
	vp.scaling_3d_scale = q["render_scale"]
	RenderingServer.directional_shadow_atlas_set_size(int(q["shadow_size"]), true)


## Safe area (notch / gesture bar) in viewport coordinates.
func safe_margins(vp: Viewport) -> Dictionary:
	var out := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	if not OS.has_feature("mobile"):
		return out
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0 or win.y <= 0 or safe.size.x <= 0:
		return out
	var vs := vp.get_visible_rect().size
	var sx := vs.x / float(win.x)
	var sy := vs.y / float(win.y)
	out["left"] = maxf(0.0, safe.position.x * sx)
	out["top"] = maxf(0.0, safe.position.y * sy)
	out["right"] = maxf(0.0, (win.x - safe.end.x) * sx)
	out["bottom"] = maxf(0.0, (win.y - safe.end.y) * sy)
	return out


func _on_root_resized() -> void:
	pass


func format_time(sec: float) -> String:
	if sec < 0.0 or is_inf(sec) or is_nan(sec):
		return "--:--.---"
	var m := int(sec / 60.0)
	var s := fmod(sec, 60.0)
	return "%02d:%06.3f" % [m, s]


func ordinal(n: int) -> String:
	match n:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
		_: return "%dth" % n
