extends Node
## Two-process LAN test driver (lives under /root so it survives scene changes).
## host:   godot --headless --path . res://Tools/NetTest.tscn -- --autopilot --role=host --port=7800
## client: godot --headless --path . res://Tools/NetTest.tscn -- --autopilot --role=client --port=7800 [--latency=150 --loss=0.03] [--leave-after=15]

var role := "host"
var port := 7800
var t := 0.0
var results: Array = []
var started := false
var max_remote_dist := 0.0
var _last_remote := {}
var snapshots := 0
var leave_after := -1.0
var phase := "lobby"


func _ready() -> void:
	var a: Dictionary = GameFlow.cmdline
	role = String(a.get("role", "host"))
	port = int(a.get("port", "7800"))
	leave_after = float(a.get("leave-after", "-1"))
	Net.sim_latency_ms = int(a.get("latency", "0"))
	Net.sim_loss = float(a.get("loss", "0"))
	Net.results_received.connect(func(r): results = r)
	Net.race_start_requested.connect(func(_c): started = true)
	Net.room_settings["laps"] = 1
	if role == "host":
		Net.host_lan("HOST", "orange", port, 8)
		Net.update_room_settings({"laps": 1})
	else:
		Net.join_lan("127.0.0.1", "CLIENT", "neon_blue", port)
		Net.lobby_updated.connect(_on_lobby)
	print("NETTEST %s started (latency %d ms, loss %.2f)" % [role, Net.sim_latency_ms, Net.sim_loss])


func _on_lobby(p: Dictionary) -> void:
	if role == "client" and p.has(Net.my_id()) and not p[Net.my_id()]["ready"]:
		Net.set_ready(true)


func _process(delta: float) -> void:
	t += delta
	if role == "host" and not started and Net.can_start()["ok"]:
		print("NETTEST host: client ready, starting race")
		Net.host_start_race()
	var w := get_tree().current_scene as RaceWorld
	if w and w.session:
		snapshots = w.session.snapshots_applied
		for k in w.karts:
			if k.is_remote:
				if _last_remote.has(k):
					max_remote_dist += k.global_position.distance_to(_last_remote[k])
				_last_remote[k] = k.global_position
		if leave_after > 0.0 and w.race.state == RaceManager.State.RACING and w.race.race_time > leave_after:
			print("NETTEST client leaving mid-race on purpose")
			_finish(true)
			return
	if not results.is_empty() and phase != "done":
		phase = "done"
		await get_tree().create_timer(0.5).timeout
		_finish(false)
	if t > 150.0:
		print("NETTEST TIMEOUT")
		_finish(false)


func _finish(left: bool) -> void:
	var summary := {"role": role, "results": results, "remote_distance_m": snappedf(max_remote_dist, 0.1),
		"snapshots_applied": snapshots, "stats": Net.stats, "left_on_purpose": left}
	print("NETTEST RESULT " + JSON.stringify(summary))
	Net.leave()
	get_tree().quit(0 if (left or not results.is_empty()) else 1)
