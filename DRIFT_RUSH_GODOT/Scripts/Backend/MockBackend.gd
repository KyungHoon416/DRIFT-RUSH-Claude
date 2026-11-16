class_name MockBackend
extends Node
## Local stand-in for Firebase (no network, no account).
## Implements the same async API as FirebaseAdapter and the same room rules as
## Backend/functions/lib/rooms.js so the full UI flow and error states can be
## exercised offline. Everything here is clearly labelled MOCK in the UI.

const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # no 0/O/1/I
const STORE := "user://mock_backend.cfg"

var latency_sec := 0.2
var fail_next := ""            # e.g. "NETWORK" to simulate one failure
var user: Dictionary = {}
var rooms: Dictionary = {}     # code -> {host, members:[uid], capacity, started, mode, map, laps, public}
var current_room := ""
var records: Array = []
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()


func backend_name() -> String:
	return "mock"


func _delay() -> void:
	if latency_sec > 0.0 and is_inside_tree():
		await get_tree().create_timer(latency_sec).timeout


func _maybe_fail() -> Dictionary:
	if fail_next != "":
		var e := fail_next
		fail_next = ""
		return {"ok": false, "error": e}
	return {}


func restore_session() -> Dictionary:
	await _delay()
	var cfg := ConfigFile.new()
	if cfg.load(STORE) == OK and cfg.has_section_key("user", "uid"):
		user = {"uid": cfg.get_value("user", "uid"), "nickname": cfg.get_value("user", "nickname", ""),
			"anonymous": true, "provider": "mock-guest", "friend_code": cfg.get_value("user", "friend_code", "")}
		return {"ok": true, "user": user}
	return {"ok": false, "error": "NO_SESSION"}


func sign_in_guest() -> Dictionary:
	await _delay()
	var f := _maybe_fail()
	if not f.is_empty():
		return f
	user = {"uid": "mock_%08x" % rng.randi(), "nickname": "", "anonymous": true, "provider": "mock-guest",
		"friend_code": _code(8)}
	_persist()
	return {"ok": true, "user": user}


func sign_out() -> void:
	user = {}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))


func set_nickname(n: String) -> Dictionary:
	await _delay()
	n = n.strip_edges()
	if n.length() < 2 or n.length() > 12:
		return {"ok": false, "error": "INVALID_NICKNAME"}
	user["nickname"] = n
	_persist()
	return {"ok": true}


func _persist() -> void:
	var cfg := ConfigFile.new()
	for k in ["uid", "nickname", "friend_code"]:
		cfg.set_value("user", k, user.get(k, ""))
	cfg.save(STORE)


func _code(n := 6) -> String:
	var s := ""
	for i in n:
		s += CODE_ALPHABET[rng.randi() % CODE_ALPHABET.length()]
	return s


static func is_valid_code(code: String) -> bool:
	if code.length() != 6:
		return false
	for ch in code:
		if not CODE_ALPHABET.contains(ch):
			return false
	return true


func create_room(opts: Dictionary) -> Dictionary:
	await _delay()
	var f := _maybe_fail()
	if not f.is_empty():
		return f
	if user.is_empty():
		return {"ok": false, "error": "UNAUTHENTICATED"}
	if current_room != "":
		return {"ok": false, "error": "ALREADY_IN_ROOM"}
	var code := _code()
	while rooms.has(code):
		code = _code()
	rooms[code] = {"host": user["uid"], "members": [user["uid"]], "ready": {},
		"capacity": clampi(int(opts.get("capacity", 8)), 2, 8), "started": false,
		"mode": opts.get("mode", "speed"), "map": opts.get("map", "sakura_valley"),
		"laps": clampi(int(opts.get("laps", 3)), 1, 5), "public": bool(opts.get("public", false))}
	current_room = code
	return {"ok": true, "code": code, "room": rooms[code]}


func join_room(code: String) -> Dictionary:
	await _delay()
	var f := _maybe_fail()
	if not f.is_empty():
		return f
	code = code.strip_edges().to_upper()
	if not is_valid_code(code):
		return {"ok": false, "error": "INVALID_CODE"}
	if not rooms.has(code):
		return {"ok": false, "error": "ROOM_NOT_FOUND"}
	var r: Dictionary = rooms[code]
	if (r["members"] as Array).has(user.get("uid")):
		return {"ok": false, "error": "ALREADY_IN_ROOM"}
	if r["started"]:
		return {"ok": false, "error": "RACE_STARTED"}
	if (r["members"] as Array).size() >= int(r["capacity"]):
		return {"ok": false, "error": "ROOM_FULL"}
	(r["members"] as Array).append(user.get("uid"))
	current_room = code
	return {"ok": true, "code": code, "room": r}


func leave_room() -> Dictionary:
	await _delay()
	if current_room == "" or not rooms.has(current_room):
		current_room = ""
		return {"ok": true}
	var r: Dictionary = rooms[current_room]
	(r["members"] as Array).erase(user.get("uid"))
	if (r["members"] as Array).is_empty():
		rooms.erase(current_room)
	elif r["host"] == user.get("uid"):
		r["host"] = r["members"][0]    # host migration
	current_room = ""
	return {"ok": true}


func set_ready(ready: bool) -> Dictionary:
	await _delay()
	if current_room == "":
		return {"ok": false, "error": "NOT_IN_ROOM"}
	(rooms[current_room]["ready"] as Dictionary)[user.get("uid")] = ready
	return {"ok": true}


## Results are only accepted from the game server in production. The mock
## stores them locally and marks them unverified.
func submit_race_result(result: Dictionary) -> Dictionary:
	records.append(result)
	return {"ok": true, "verified": false, "note": "MOCK: 로컬 저장만, 서버 검증 없음"}


func get_friends() -> Dictionary:
	await _delay()
	return {"ok": true, "friends": []}


func debug_add_room(code: String, data: Dictionary) -> void:
	rooms[code] = data
