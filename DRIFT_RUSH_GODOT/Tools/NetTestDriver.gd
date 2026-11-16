extends Node
## Multi-process network test driver (lives under /root so it survives scene changes).
## Roles:
##   host    LAN listen server (also races)
##   server  dedicated server (no kart; auto-starts when all clients are ready)
##   client  joins 127.0.0.1, or the first room found by LAN code discovery (--discover)
## Options: --port=7800 --mode=speed|item --laps=1 --latency=150 --loss=0.03
##          --leave-after=12 (client quits mid-race) --cheat=8 (client teleports at t=8 s)

var role := "host"
var port := 7800
var t := 0.0
var results: Array = []
var started := false
var remote_dist := 0.0
var _last_remote := {}
var snapshots := 0
var leave_after := -1.0
var cheat_at := -1.0
var cheated := false
var discover := false
var joined := false
var phase := "lobby"
var corrections := 0
var violations := {}
var item_events := 0
var items_used := 0
var hits := 0
var joined_code := ""


func _ready() -> void:
	var a: Dictionary = GameFlow.cmdline
	role = String(a.get("role", "host"))
	port = int(a.get("port", "7800"))
	leave_after = float(a.get("leave-after", "-1"))
	cheat_at = float(a.get("cheat", "-1"))
	discover = a.has("discover")
	Net.sim_latency_ms = int(a.get("latency", "0"))
	Net.sim_loss = float(a.get("loss", "0"))
	Net.results_received.connect(func(r): results = r)
	Net.race_start_requested.connect(func(_c): started = true)
	var settings := {"laps": int(a.get("laps", "1")), "mode": String(a.get("mode", "speed")), "map": String(a.get("map", "sakura_valley"))}
	if role == "host":
		Net.host_lan("HOST", "orange", port, 8)
		Net.update_room_settings(settings)
	elif role == "server":
		Net.auto_start_min_players = int(a.get("min-players", "2"))
		Net.host_dedicated(port, settings)
	else:
		Net.lobby_updated.connect(_on_lobby)
		if not discover:
			_join("127.0.0.1", port)
		else:
			Net.discovery.start_listen()
	print("NETTEST %s started (latency %d ms, loss %.2f, discover %s)" % [role, Net.sim_latency_ms, Net.sim_loss, discover])


func _join(ip: String, p: int) -> void:
	joined = true
	Net.join_lan(ip, "CLIENT%d" % (randi() % 90 + 10), "neon_blue", p)


func _on_lobby(p: Dictionary) -> void:
	if role == "client" and p.has(Net.my_id()) and not p[Net.my_id()]["ready"] and not started:
		joined_code = Net.room_code
		Net.set_ready(true)


func _process(delta: float) -> void:
	t += delta
	if role == "client" and discover and not joined:
		for code in Net.discovery.rooms.keys():
			var r: Dictionary = Net.discovery.rooms[code]
			if int(r["port"]) == port:
				print("NETTEST client discovered room %s at %s:%d" % [code, r["ip"], r["port"]])
				_join(String(r["ip"]), int(r["port"]))
				break
	if role == "host" and not started and Net.can_start()["ok"]:
		print("NETTEST host: client ready, starting race")
		Net.host_start_race()
	var w := get_tree().current_scene as RaceWorld
	if w and w.session:
		snapshots = w.session.snapshots_applied
		corrections = w.session.corrections_received
		violations = w.session.violations
		if w.items:
			item_events = w.items.events_seen
		for k in w.karts:
			if k.is_remote:
				if _last_remote.has(k):
					remote_dist += k.global_position.distance_to(_last_remote[k])
				_last_remote[k] = k.global_position
		if w.player and cheat_at > 0.0 and not cheated and w.race.state == RaceManager.State.RACING and w.race.race_time > cheat_at:
			cheated = true
			var off := w.track.closest_offset(w.player.global_position)
			w.player.place(w.track.transform_at(off + 250.0, 0.0, 0.1))
			print("NETTEST client CHEAT: teleported +250 m along the track")
		if leave_after > 0.0 and w.race.state == RaceManager.State.RACING and w.race.race_time > leave_after:
			print("NETTEST client leaving mid-race on purpose")
			_finish(true)
			return
	if not results.is_empty() and phase != "done":
		phase = "done"
		await get_tree().create_timer(0.5).timeout
		_finish(false)
	if t > 170.0:
		print("NETTEST TIMEOUT")
		_finish(false)


func _finish(left: bool) -> void:
	var summary := {"role": role, "results": results, "remote_distance_m": snappedf(remote_dist, 0.1),
		"snapshots_applied": snapshots, "stats": Net.stats, "left_on_purpose": left,
		"corrections_received": corrections, "violations": violations, "item_events": item_events,
		"room_code": Net.room_code if Net.room_code != "" else joined_code}
	print("NETTEST RESULT " + JSON.stringify(summary))
	Net.leave()
	get_tree().quit(0 if (left or not results.is_empty()) else 1)
