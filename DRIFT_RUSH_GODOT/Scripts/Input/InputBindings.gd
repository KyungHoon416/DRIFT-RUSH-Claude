class_name InputBindings
extends RefCounted
## Single source of truth for controls: default keyboard keys, user
## re-bindings (SaveSettings "key_bindings"), and gamepad buttons/axes.
##
## PC default layout (auto-acceleration, so no throttle key):
##   ← → / A D   steer          Shift / Space  drift (hold while turning)
##   ↑ / W       boost           Ctrl / E       use item
##   ↓ / S       brake           R              respawn on track
##   Esc / P     pause           F1 / H         controls help

const ACTIONS := ["steer_left", "steer_right", "drift", "boost", "use_item", "brake", "respawn", "pause", "help"]

const DEFAULT_KEYS := {
	"steer_left": [KEY_LEFT, KEY_A],
	"steer_right": [KEY_RIGHT, KEY_D],
	"drift": [KEY_SHIFT, KEY_SPACE],
	"boost": [KEY_UP, KEY_W],
	"use_item": [KEY_CTRL, KEY_E],
	"brake": [KEY_DOWN, KEY_S],
	"respawn": [KEY_R],
	"pause": [KEY_ESCAPE, KEY_P],
	"help": [KEY_F1, KEY_H],
}

const LABELS := {
	"steer_left": "왼쪽 조향", "steer_right": "오른쪽 조향", "drift": "드리프트", "boost": "부스터",
	"use_item": "아이템 사용", "brake": "브레이크", "respawn": "트랙 복귀", "pause": "일시정지", "help": "조작 도움말",
}

## Gamepad (Xbox layout names; PlayStation equivalents in parentheses):
## left stick / d-pad steer · A(✕)/RT drift · Y(△)/RB boost · X(□)/LB item ·
## B(○)/LT brake · Back respawn · Start pause
const PAD_BUTTONS := {
	"steer_left": [JOY_BUTTON_DPAD_LEFT],
	"steer_right": [JOY_BUTTON_DPAD_RIGHT],
	"drift": [JOY_BUTTON_A],
	"boost": [JOY_BUTTON_Y, JOY_BUTTON_RIGHT_SHOULDER],
	"use_item": [JOY_BUTTON_X, JOY_BUTTON_LEFT_SHOULDER],
	"brake": [JOY_BUTTON_B],
	"respawn": [JOY_BUTTON_BACK],
	"pause": [JOY_BUTTON_START],
}
const PAD_AXES := {
	"steer_left": [[JOY_AXIS_LEFT_X, -1.0]],
	"steer_right": [[JOY_AXIS_LEFT_X, 1.0]],
	"drift": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	"brake": [[JOY_AXIS_TRIGGER_LEFT, 1.0]],
}


static func keys_for(action: String) -> Array:
	var custom: Dictionary = SaveSettings.get_value("key_bindings")
	if custom.has(action) and custom[action] is Array and not (custom[action] as Array).is_empty():
		return custom[action]
	return DEFAULT_KEYS.get(action, [])


## (Re)builds every InputMap action from defaults + user bindings + gamepad.
static func apply() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		InputMap.action_erase_events(action)
		for k in keys_for(action):
			var ev := InputEventKey.new()
			ev.physical_keycode = int(k)
			InputMap.action_add_event(action, ev)
		for b in PAD_BUTTONS.get(action, []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = b
			InputMap.action_add_event(action, jb)
		for ax in PAD_AXES.get(action, []):
			var jm := InputEventJoypadMotion.new()
			jm.axis = ax[0]
			jm.axis_value = ax[1]
			InputMap.action_add_event(action, jm)


## Sets the primary key of an action (keeps its secondary key unless it clashes).
## Any other action already using this key loses it. Returns the action that
## lost the key ("" when none).
static func rebind(action: String, keycode: int) -> String:
	var custom: Dictionary = (SaveSettings.get_value("key_bindings") as Dictionary).duplicate(true)
	var stolen_from := ""
	for other in ACTIONS:
		if other == action:
			continue
		var ks: Array = keys_for(other).duplicate()
		if ks.has(keycode):
			ks.erase(keycode)
			custom[other] = ks
			stolen_from = other
	var mine: Array = keys_for(action).duplicate()
	mine.erase(keycode)
	mine.push_front(keycode)
	custom[action] = mine.slice(0, 2)
	SaveSettings.set_value("key_bindings", custom)
	apply()
	return stolen_from


static func reset_defaults() -> void:
	SaveSettings.set_value("key_bindings", {})
	apply()


static func key_name(keycode: int) -> String:
	match keycode:
		KEY_LEFT: return "←"
		KEY_RIGHT: return "→"
		KEY_UP: return "↑"
		KEY_DOWN: return "↓"
		KEY_SHIFT: return "Shift"
		KEY_CTRL: return "Ctrl"
		KEY_SPACE: return "Space"
		KEY_ESCAPE: return "Esc"
	return OS.get_keycode_string(keycode)


## "Shift / Space" style label for HUD hints and help.
static func label_for(action: String, max_keys := 2) -> String:
	var names: Array = []
	for k in keys_for(action).slice(0, max_keys):
		names.append(key_name(int(k)))
	return " / ".join(names) if not names.is_empty() else "-"


static func primary_label(action: String) -> String:
	var ks := keys_for(action)
	return key_name(int(ks[0])) if not ks.is_empty() else ""


## "← → / A D" — left/right pairs per binding slot.
static func steer_label() -> String:
	var l := keys_for("steer_left")
	var r := keys_for("steer_right")
	var parts: Array = []
	for i in mini(2, maxi(l.size(), r.size())):
		var ln := key_name(int(l[i])) if i < l.size() else "?"
		var rn := key_name(int(r[i])) if i < r.size() else "?"
		parts.append("%s %s" % [ln, rn])
	return " / ".join(parts)


static func help_lines() -> Array:
	return [
		[steer_label(), "조향 (가속은 자동)"],
		[label_for("drift"), "드리프트 — 누른 채 꺾고, 떼면 순간 부스터"],
		[label_for("boost"), "부스터 — 게이지(드리프트로 충전)가 가득 차면"],
		[label_for("use_item"), "아이템 사용 (아이템전)"],
		[label_for("brake"), "브레이크 (누르는 동안)"],
		[label_for("respawn"), "트랙으로 복귀"],
		[label_for("pause"), "일시정지"],
		[label_for("help"), "조작 도움말 켜기/끄기"],
	]
